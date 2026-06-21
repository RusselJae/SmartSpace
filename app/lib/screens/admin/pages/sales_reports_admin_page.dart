import 'dart:typed_data';

import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../models/order_record.dart';
import '../../../models/product.dart';
import '../../../models/review.dart';
import '../../../services/mysql_database_service.dart';
import '../../../utils/admin_formatters.dart';
import '../../../utils/report_file_saver.dart';
import '../../../widgets/toast.dart';
import '../widgets/admin_analytics_components.dart';

// ---------------------------------------------------------------------------
// Sales report period helpers (local week = Mon 00:00 → next Mon 00:00).
// ---------------------------------------------------------------------------

DateTime _mondayOfWeekContaining(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

/// Trend + CSV/PDF x-axis: weekly = weekday; monthly = in-month week index; yearly = month short name.
String _salesTrendXLabel(AdminTrendGranularity g, DateTime x) {
  switch (g) {
    case AdminTrendGranularity.weekly:
      return DateFormat.E().format(x);
    case AdminTrendGranularity.monthly:
      final d = x.day;
      if (d <= 7) return 'Week 1';
      if (d <= 14) return 'Week 2';
      if (d <= 21) return 'Week 3';
      return 'Week 4';
    case AdminTrendGranularity.yearly:
      return DateFormat.MMM().format(x);
  }
}

/// Which date endpoint the admin is currently editing (drives button focus styling).
enum _SalesRangeField { none, from, to }

class SalesReportsAdminPage extends StatefulWidget {
  const SalesReportsAdminPage({super.key});

  @override
  State<SalesReportsAdminPage> createState() => _SalesReportsAdminPageState();
}

class _SalesReportsAdminPageState extends State<SalesReportsAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  AdminTrendGranularity _trendGranularity = AdminTrendGranularity.monthly;
  /// Custom report window — both ends must be set before filtering overrides granularity.
  DateTime? _rangeFrom;
  DateTime? _rangeTo;
  _SalesRangeField _activeRangeField = _SalesRangeField.none;
  List<OrderRecord> _orders = const [];
  List<Product> _products = const [];
  List<Review> _reviews = const [];
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  final List<int> _insightSegments = <int>[0, 0, 0];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _db.getAllOrders(),
        _db.getAllProducts(),
        _db.getAllReviews(),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = results[0] as List<OrderRecord>;
        _products = results[1] as List<Product>;
        _reviews = results[2] as List<Review>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load sales reports: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// White, compact picker — not full-screen (Apple-style modal on admin web).
  ThemeData _salesReportPickerTheme(BuildContext context) {
    final base = Theme.of(context);
    const walnut = Color(0xFF5D4037);
    return base.copyWith(
      canvasColor: Colors.white,
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      colorScheme: base.colorScheme.copyWith(
        surface: Colors.white,
        onSurface: Colors.black87,
        primary: walnut,
        onPrimary: Colors.white,
      ),
      datePickerTheme: base.datePickerTheme.copyWith(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: walnut,
        headerForegroundColor: Colors.white,
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return Colors.black87;
        }),
        rangeSelectionBackgroundColor: const Color(0xFF8D6E63).withValues(alpha: 0.18),
        rangeSelectionOverlayColor: WidgetStateProperty.all(
          const Color(0xFF8D6E63).withValues(alpha: 0.10),
        ),
      ),
    );
  }

  Widget _salesReportDatePickerBuilder(BuildContext context, Widget? child) {
    return Theme(
      data: _salesReportPickerTheme(context),
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  bool get _hasCustomRange => _rangeFrom != null && _rangeTo != null;

  String _formatRangeButtonDate(DateTime date) => DateFormat.yMMMd().format(date);

  /// Opens a compact modal so the admin can pick the range **start** date.
  Future<void> _pickRangeFrom() async {
    final now = DateTime.now();
    setState(() => _activeRangeField = _SalesRangeField.from);
    final picked = await showDatePicker(
      context: context,
      initialDate: _rangeFrom ?? _rangeTo ?? now,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Select range start date',
      builder: _salesReportDatePickerBuilder,
    );
    if (!mounted) return;
    setState(() => _activeRangeField = _SalesRangeField.none);
    if (picked == null) return;
    setState(() {
      _rangeFrom = DateTime(picked.year, picked.month, picked.day);
      // Keep the window valid when the user adjusts the start after picking an end.
      if (_rangeTo != null && _rangeTo!.isBefore(_rangeFrom!)) {
        _rangeTo = _rangeFrom;
      }
    });
  }

  /// Opens a compact modal so the admin can pick the range **end** date.
  Future<void> _pickRangeTo() async {
    final now = DateTime.now();
    setState(() => _activeRangeField = _SalesRangeField.to);
    final picked = await showDatePicker(
      context: context,
      initialDate: _rangeTo ?? _rangeFrom ?? now,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Select range end date',
      builder: _salesReportDatePickerBuilder,
    );
    if (!mounted) return;
    setState(() => _activeRangeField = _SalesRangeField.none);
    if (picked == null) return;
    setState(() {
      _rangeTo = DateTime(picked.year, picked.month, picked.day);
      // Keep the window valid when the user adjusts the end before picking a start.
      if (_rangeFrom != null && _rangeFrom!.isAfter(_rangeTo!)) {
        _rangeFrom = _rangeTo;
      }
    });
  }

  void _clearDateRange() {
    setState(() {
      _rangeFrom = null;
      _rangeTo = null;
      _activeRangeField = _SalesRangeField.none;
    });
  }

  DateTime get _periodStart {
    if (_hasCustomRange) {
      return DateTime(
        _rangeFrom!.year,
        _rangeFrom!.month,
        _rangeFrom!.day,
      );
    }
    switch (_trendGranularity) {
      case AdminTrendGranularity.weekly:
        return _mondayOfWeekContaining(_selectedDate);
      case AdminTrendGranularity.monthly:
        return DateTime(_selectedDate.year, _selectedDate.month, 1);
      case AdminTrendGranularity.yearly:
        return DateTime(_selectedDate.year, 1, 1);
    }
  }

  DateTime get _periodEnd {
    if (_hasCustomRange) {
      return DateTime(
        _rangeTo!.year,
        _rangeTo!.month,
        _rangeTo!.day + 1,
      );
    }
    switch (_trendGranularity) {
      case AdminTrendGranularity.weekly:
        return _mondayOfWeekContaining(_selectedDate).add(const Duration(days: 7));
      case AdminTrendGranularity.monthly:
        return DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
      case AdminTrendGranularity.yearly:
        return DateTime(_selectedDate.year + 1, 1, 1);
    }
  }

  String get _selectedPeriodLabel {
    if (_hasCustomRange) {
      return '${DateFormat.yMMMd().format(_rangeFrom!)} – ${DateFormat.yMMMd().format(_rangeTo!)}';
    }
    switch (_trendGranularity) {
      case AdminTrendGranularity.weekly:
        final mon = _mondayOfWeekContaining(_selectedDate);
        final sun = mon.add(const Duration(days: 6));
        return '${DateFormat.yMMMd().format(mon)} – ${DateFormat.yMMMd().format(sun)}';
      case AdminTrendGranularity.monthly:
        return DateFormat.yMMM().format(_selectedDate);
      case AdminTrendGranularity.yearly:
        return DateFormat.y().format(_selectedDate);
    }
  }

  static const String _storeBrandName = 'Wood Home Furniture Trading';

  List<OrderRecord> get _periodAllOrders => _orders
      .where(
        (o) =>
            !o.createdAt.isBefore(_periodStart) && o.createdAt.isBefore(_periodEnd),
      )
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int get _completedOrdersCount => _periodAllOrders
      .where((o) => o.status.toLowerCase() != 'cancelled')
      .length;

  int get _grossOrdersCount => _periodAllOrders.length;

  Map<String, int> get _productGrossOrderCounts {
    final counts = <String, int>{};
    for (final order in _periodAllOrders) {
      for (final productId in order.productIds) {
        counts[productId] = (counts[productId] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// One row per calendar day inside the active report window.
  List<_DailyRevenueTrendRow> get _dailyRevenueTrendRows {
    final rows = <_DailyRevenueTrendRow>[];
    var day = DateTime(_periodStart.year, _periodStart.month, _periodStart.day);
    final endDay = _periodEnd.subtract(const Duration(days: 1));
    while (!day.isAfter(endDay)) {
      final next = day.add(const Duration(days: 1));
      final dayOrders = _orders.where((o) {
        final status = o.status.toLowerCase();
        final isCancelled = status == 'cancelled';
        final includeCancelledForRevenue = _isPaymentDefaultCancelled(o);
        return (!isCancelled || includeCancelledForRevenue) &&
            !o.createdAt.isBefore(day) &&
            o.createdAt.isBefore(next);
      }).toList();
      final revenue = dayOrders.fold<double>(
        0,
        (sum, o) => sum + _orderRevenueForSalesReports(o),
      );
      final orderCount = dayOrders.length;
      rows.add(
        _DailyRevenueTrendRow(
          date: day,
          orders: orderCount,
          revenue: revenue,
          avgOrderValue: orderCount == 0 ? 0 : revenue / orderCount,
        ),
      );
      day = next;
    }
    return rows;
  }

  bool _isPaymentDefaultCancelled(OrderRecord o) {
    final status = o.status.toLowerCase();
    if (status != 'cancelled') return false;
    return o.shippingAddress['cancellationReason']?.toString() ==
        'payment_default_non_payment_6_months';
  }

  bool _isIncludedOrder(OrderRecord o) {
    final status = o.status.toLowerCase();
    final isCancelled = status == 'cancelled';
    // Count deposit forfeiture as revenue even though the order is cancelled.
    final includeCancelledForRevenue = _isPaymentDefaultCancelled(o);
    return (isCancelled ? includeCancelledForRevenue : true) &&
        !o.createdAt.isBefore(_periodStart) &&
        o.createdAt.isBefore(_periodEnd);
  }

  List<OrderRecord> get _monthOrders => _orders.where(_isIncludedOrder).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<OrderRecord> get _monthCancelledOrders => _orders
      .where((o) =>
          o.status.toLowerCase() == 'cancelled' &&
          !o.createdAt.isBefore(_periodStart) &&
          o.createdAt.isBefore(_periodEnd))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  double _orderRevenueForSalesReports(OrderRecord o) {
    if (!_isPaymentDefaultCancelled(o)) return o.totalAmount;

    final raw = o.shippingAddress['downpayment'];
    if (raw is num) return raw.toDouble();
    final parsed = double.tryParse(raw?.toString() ?? '');
    return parsed ?? 0.0;
  }

  double get _monthSales =>
      _monthOrders.fold<double>(0, (s, o) => s + _orderRevenueForSalesReports(o));

  Map<String, Product> get _productsById => {
        for (final p in _products) p.id: p,
      };

  List<_SalesProductStat> get _bestSellingInMonth {
    final counts = <String, int>{};
    final revenue = <String, double>{};
    for (final order in _monthOrders) {
      for (final productId in order.productIds) {
        counts[productId] = (counts[productId] ?? 0) + 1;
        final productPrice = _productsById[productId]?.price ?? 0;
        revenue[productId] = (revenue[productId] ?? 0) + productPrice;
      }
    }
    final rows = <_SalesProductStat>[];
    counts.forEach((productId, qty) {
      final product = _productsById[productId];
      rows.add(
        _SalesProductStat(
          productId: productId,
          name: product?.name ?? 'Unknown product',
          value: qty.toDouble(),
          secondaryValue: revenue[productId] ?? 0,
        ),
      );
    });
    rows.sort((a, b) => b.value.compareTo(a.value));
    return rows.take(10).toList();
  }

  List<_SalesProductStat> get _topRatedInMonth {
    final productReviews = <String, List<Review>>{};
    for (final review in _reviews) {
      if (review.createdAt.isBefore(_periodStart) ||
          !review.createdAt.isBefore(_periodEnd)) {
        continue;
      }
      productReviews.putIfAbsent(review.productId, () => <Review>[]).add(review);
    }
    final rows = <_SalesProductStat>[];
    productReviews.forEach((productId, reviews) {
      if (reviews.isEmpty) return;
      final avgRating = reviews.fold<double>(0, (sum, r) => sum + r.rating) / reviews.length;
      rows.add(
        _SalesProductStat(
          productId: productId,
          name: _productsById[productId]?.name ?? reviews.first.productName,
          value: avgRating,
          secondaryValue: reviews.length.toDouble(),
        ),
      );
    });
    rows.sort((a, b) => b.value.compareTo(a.value));
    if (rows.isNotEmpty) return rows.take(10).toList();

    final fallback = _products
        .where((p) => p.rating > 0)
        .map(
          (p) => _SalesProductStat(
            productId: p.id,
            name: p.name,
            value: p.rating,
            secondaryValue: p.reviewCount.toDouble(),
          ),
        )
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return fallback.take(10).toList();
  }

  List<_SalesProductStat> get _mostCancelledInMonth {
    final counts = <String, int>{};
    for (final order in _monthCancelledOrders) {
      for (final productId in order.productIds) {
        counts[productId] = (counts[productId] ?? 0) + 1;
      }
    }
    final rows = <_SalesProductStat>[];
    counts.forEach((productId, qty) {
      rows.add(
        _SalesProductStat(
          productId: productId,
          name: _productsById[productId]?.name ?? 'Unknown product',
          value: qty.toDouble(),
          secondaryValue: 0,
        ),
      );
    });
    rows.sort((a, b) => b.value.compareTo(a.value));
    return rows.take(10).toList();
  }

  double _revenueInRange(DateTime start, DateTime end) {
    return _orders
        .where((o) {
          final status = o.status.toLowerCase();
          final isCancelled = status == 'cancelled';
          final includeCancelledForRevenue = _isPaymentDefaultCancelled(o);
          return (!isCancelled || includeCancelledForRevenue) &&
              !o.createdAt.isBefore(start) &&
              o.createdAt.isBefore(end);
        })
        .fold<double>(0, (sum, o) => sum + _orderRevenueForSalesReports(o));
  }

  /// Mon–Sun revenue for the ISO week that contains [_selectedDate].
  List<AdminSeriesPoint> get _weeklyTrendPoints {
    final monday = _mondayOfWeekContaining(_selectedDate);
    final points = <AdminSeriesPoint>[];
    for (var i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final next = day.add(const Duration(days: 1));
      points.add(AdminSeriesPoint(x: day, y: _revenueInRange(day, next)));
    }
    return points;
  }

  /// Four buckets within the selected month only: days 1–7, 8–14, 15–21, 22–end.
  List<AdminSeriesPoint> get _monthlyTrendPoints {
    final y = _selectedDate.year;
    final m = _selectedDate.month;
    DateTime segmentStart(int weekIndex) {
      switch (weekIndex) {
        case 0:
          return DateTime(y, m, 1);
        case 1:
          return DateTime(y, m, 8);
        case 2:
          return DateTime(y, m, 15);
        case 3:
        default:
          return DateTime(y, m, 22);
      }
    }

    DateTime segmentEndExclusive(int weekIndex) {
      if (weekIndex < 3) return segmentStart(weekIndex + 1);
      return DateTime(y, m + 1, 1);
    }

    return List<AdminSeriesPoint>.generate(4, (w) {
      final start = segmentStart(w);
      final end = segmentEndExclusive(w);
      return AdminSeriesPoint(x: start, y: _revenueInRange(start, end));
    });
  }

  /// January–December net revenue for [_selectedDate.year] only.
  List<AdminSeriesPoint> get _yearlyTrendPoints {
    final y = _selectedDate.year;
    final points = <AdminSeriesPoint>[];
    for (var month = 1; month <= 12; month++) {
      final start = DateTime(y, month, 1);
      final end = DateTime(y, month + 1, 1);
      points.add(AdminSeriesPoint(x: start, y: _revenueInRange(start, end)));
    }
    return points;
  }

  List<AdminSeriesPoint> get _activeTrendPoints {
    switch (_trendGranularity) {
      case AdminTrendGranularity.weekly:
        return _weeklyTrendPoints;
      case AdminTrendGranularity.monthly:
        return _monthlyTrendPoints;
      case AdminTrendGranularity.yearly:
        return _yearlyTrendPoints;
    }
  }

  String get _granularityLabel {
    switch (_trendGranularity) {
      case AdminTrendGranularity.weekly:
        return 'weekly';
      case AdminTrendGranularity.monthly:
        return 'monthly';
      case AdminTrendGranularity.yearly:
        return 'yearly';
    }
  }

  /// Explicit label for PDF/XLSX exports (always includes start–end when custom range is set).
  String get _exportDateRangeLabel => _selectedPeriodLabel;

  String _exportFilenameStem() {
    if (_hasCustomRange) {
      final s = DateFormat('yyyyMMdd').format(_rangeFrom!);
      final e = DateFormat('yyyyMMdd').format(_rangeTo!);
      return 'sales_report_${s}_$e';
    }
    return 'sales_report_${_granularityLabel}_${_selectedDate.year}_'
        '${_selectedDate.month.toString().padLeft(2, '0')}_'
        '${_selectedDate.day.toString().padLeft(2, '0')}';
  }

  Future<void> _exportExcelXlsx() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = _buildXlsxForGranularity();
      final filename = '${_exportFilenameStem()}.xlsx';
      final savedAt = await saveReportFile(
        filename: filename,
        bytes: bytes,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      Toast.success(context, '$_granularityLabel XLSX exported: $savedAt');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to export XLSX: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _printPdfReport() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final doc = await _buildPdfDocumentForGranularity();
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
      if (!mounted) return;
      Toast.success(context, '$_granularityLabel PDF print dialog opened');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to generate PDF: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<(String, String)> _summaryRows() {
    final avgOrderValue =
        _monthOrders.isEmpty ? 0.0 : _monthSales / _monthOrders.length;
    final topBestSeller = _bestSellingInMonth.isEmpty ? '-' : _bestSellingInMonth.first.name;
    final topRated = _topRatedInMonth.isEmpty ? '-' : _topRatedInMonth.first.name;
    final topCancelled =
        _mostCancelledInMonth.isEmpty ? '-' : _mostCancelledInMonth.first.name;
    return <(String, String)>[
      ('Total Sales', AdminFormatters.currency(_monthSales)),
      ('Gross Orders', AdminFormatters.count(_grossOrdersCount)),
      ('Completed Orders', AdminFormatters.count(_completedOrdersCount)),
      ('Cancelled Orders', AdminFormatters.count(_monthCancelledOrders.length)),
      ('Average Order Value', AdminFormatters.currency(avgOrderValue)),
      ('Best Selling Product', topBestSeller),
      ('Top Rated Product', topRated),
      ('Most Cancelled Product', topCancelled),
    ];
  }

  excel.CellStyle _xlsxBorderedStyle({
    required String backgroundHex,
    bool bold = false,
    excel.HorizontalAlign align = excel.HorizontalAlign.Left,
    excel.NumFormat? numberFormat,
  }) {
    const borderColor = '#D7CCC8';
    final border = excel.Border(
      borderStyle: excel.BorderStyle.Thin,
      borderColorHex: excel.ExcelColor.fromHexString(borderColor),
    );
    return excel.CellStyle(
      bold: bold,
      backgroundColorHex: excel.ExcelColor.fromHexString(backgroundHex),
      horizontalAlign: align,
      verticalAlign: excel.VerticalAlign.Center,
      leftBorder: border,
      rightBorder: border,
      topBorder: border,
      bottomBorder: border,
      numberFormat: numberFormat ?? excel.NumFormat.standard_2,
    );
  }

  void _writeXlsxRow(
    excel.Sheet sheet,
    int rowIndex,
    List<excel.CellValue> values, {
    required excel.CellStyle style,
    int startColumn = 0,
  }) {
    for (var col = 0; col < values.length; col++) {
      final cell = sheet.cell(
        excel.CellIndex.indexByColumnRow(columnIndex: startColumn + col, rowIndex: rowIndex),
      );
      cell.value = values[col];
      cell.cellStyle = style;
    }
  }

  void _autoFitXlsxColumns(excel.Sheet sheet, int columnCount) {
    for (var col = 0; col < columnCount; col++) {
      var maxLen = 12.0;
      final limit = sheet.maxRows.clamp(0, 500);
      for (var row = 0; row < limit; row++) {
        final cell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
        final String text = switch (cell.value) {
          excel.TextCellValue v => v.value.toString(),
          excel.DoubleCellValue v => v.value.toString(),
          excel.IntCellValue v => v.value.toString(),
          _ => '',
        };
        final len = text.length;
        if (len > maxLen) maxLen = len.toDouble();
      }
      sheet.setColumnWidth(col, (maxLen + 4).clamp(14, 48));
    }
  }

  Uint8List _buildXlsxForGranularity() {
    const walnut = '#5D4037';
    const walnutSoft = '#EFE8E3';
    const beigeAlt = '#F9F5F2';

    final workbook = excel.Excel.createExcel();
    workbook.delete('Sheet1');
    final sheet = workbook['Sales Report'];

    final brandBanner = excel.CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: excel.ExcelColor.white,
      backgroundColorHex: excel.ExcelColor.fromHexString(walnut),
      horizontalAlign: excel.HorizontalAlign.Left,
      verticalAlign: excel.VerticalAlign.Center,
    );
    final metaLabel = excel.CellStyle(
      bold: true,
      backgroundColorHex: excel.ExcelColor.fromHexString(walnutSoft),
    );
    final sectionTitle = excel.CellStyle(
      bold: true,
      fontSize: 12,
      fontColorHex: excel.ExcelColor.fromHexString(walnut),
    );
    final tableHeader = excel.CellStyle(
      bold: true,
      fontColorHex: excel.ExcelColor.white,
      backgroundColorHex: excel.ExcelColor.fromHexString(walnut),
      horizontalAlign: excel.HorizontalAlign.Center,
      verticalAlign: excel.VerticalAlign.Center,
      leftBorder: excel.Border(
        borderStyle: excel.BorderStyle.Thin,
        borderColorHex: excel.ExcelColor.fromHexString('#D7CCC8'),
      ),
      rightBorder: excel.Border(
        borderStyle: excel.BorderStyle.Thin,
        borderColorHex: excel.ExcelColor.fromHexString('#D7CCC8'),
      ),
      topBorder: excel.Border(
        borderStyle: excel.BorderStyle.Thin,
        borderColorHex: excel.ExcelColor.fromHexString('#D7CCC8'),
      ),
      bottomBorder: excel.Border(
        borderStyle: excel.BorderStyle.Thin,
        borderColorHex: excel.ExcelColor.fromHexString('#D7CCC8'),
      ),
    );

    final generatedAt = AdminFormatters.dateYmdHm(DateTime.now());
    final summaryRows = _summaryRows();
    final trendRows = _dailyRevenueTrendRows;
    final topSelling = _bestSellingInMonth;
    final topRated = _topRatedInMonth;
    final mostCancelled = _mostCancelledInMonth;
    final grossByProduct = _productGrossOrderCounts;

    var row = 0;

    // -------------------------------------------------------------------------
    // Header / branding (single sheet, stacked sections)
    // -------------------------------------------------------------------------
    sheet.setRowHeight(row, 34);
    _writeXlsxRow(
      sheet,
      row,
      List<excel.CellValue>.generate(4, (_) => excel.TextCellValue('')),
      style: brandBanner,
    );
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
        excel.TextCellValue(_storeBrandName);
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle =
        brandBanner;
    row++;

    _writeXlsxRow(
      sheet,
      row,
      [excel.TextCellValue('Report Type'), excel.TextCellValue('Sales Report (${_granularityLabel.toUpperCase()})')],
      style: metaLabel,
    );
    row++;
    _writeXlsxRow(
      sheet,
      row,
      [excel.TextCellValue('Date Range'), excel.TextCellValue(_exportDateRangeLabel)],
      style: metaLabel,
    );
    row++;
    _writeXlsxRow(
      sheet,
      row,
      [excel.TextCellValue('Generated At'), excel.TextCellValue(generatedAt)],
      style: metaLabel,
    );
    row += 2;

    // -------------------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------------------
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
        excel.TextCellValue('Summary');
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle =
        sectionTitle;
    row++;
    _writeXlsxRow(
      sheet,
      row,
      [excel.TextCellValue('Metric'), excel.TextCellValue('Value')],
      style: tableHeader,
    );
    row++;
    for (var i = 0; i < summaryRows.length; i++) {
      final entry = summaryRows[i];
      final bg = i.isEven ? beigeAlt : '#FFFFFF';
      _writeXlsxRow(
        sheet,
        row,
        [excel.TextCellValue(entry.$1), excel.TextCellValue(entry.$2)],
        style: _xlsxBorderedStyle(backgroundHex: bg),
      );
      row++;
    }
    row++;

    // -------------------------------------------------------------------------
    // Revenue trend (daily)
    // -------------------------------------------------------------------------
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
        excel.TextCellValue('Revenue Trend');
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle =
        sectionTitle;
    row++;
    _writeXlsxRow(
      sheet,
      row,
      [
        excel.TextCellValue('Date'),
        excel.TextCellValue('Orders'),
        excel.TextCellValue('Revenue'),
        excel.TextCellValue('Avg Order Value'),
      ],
      style: tableHeader,
    );
    row++;
    for (var i = 0; i < trendRows.length; i++) {
      final entry = trendRows[i];
      final bg = i.isEven ? beigeAlt : '#FFFFFF';
      _writeXlsxRow(
        sheet,
        row,
        [
          excel.TextCellValue(DateFormat.yMMMd().format(entry.date)),
          excel.IntCellValue(entry.orders),
          excel.TextCellValue(AdminFormatters.currency(entry.revenue)),
          excel.TextCellValue(AdminFormatters.currency(entry.avgOrderValue)),
        ],
        style: _xlsxBorderedStyle(backgroundHex: bg, align: excel.HorizontalAlign.Center),
      );
      row++;
    }
    row++;

    // -------------------------------------------------------------------------
    // Top selling products
    // -------------------------------------------------------------------------
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
        excel.TextCellValue('Top Selling Products');
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle =
        sectionTitle;
    row++;
    _writeXlsxRow(
      sheet,
      row,
      [
        excel.TextCellValue('Rank'),
        excel.TextCellValue('Product Name'),
        excel.TextCellValue('Units Sold'),
        excel.TextCellValue('Revenue'),
      ],
      style: tableHeader,
    );
    row++;
    for (var i = 0; i < topSelling.length; i++) {
      final item = topSelling[i];
      final bg = i.isEven ? beigeAlt : '#FFFFFF';
      _writeXlsxRow(
        sheet,
        row,
        [
          excel.IntCellValue(i + 1),
          excel.TextCellValue(item.name),
          excel.IntCellValue(item.value.round()),
          excel.TextCellValue(AdminFormatters.currency(item.secondaryValue)),
        ],
        style: _xlsxBorderedStyle(backgroundHex: bg),
      );
      row++;
    }
    row++;

    // -------------------------------------------------------------------------
    // Top rated products
    // -------------------------------------------------------------------------
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
        excel.TextCellValue('Top Rated Products');
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle =
        sectionTitle;
    row++;
    _writeXlsxRow(
      sheet,
      row,
      [
        excel.TextCellValue('Rank'),
        excel.TextCellValue('Product Name'),
        excel.TextCellValue('Avg Rating'),
        excel.TextCellValue('No. of Reviews'),
      ],
      style: tableHeader,
    );
    row++;
    for (var i = 0; i < topRated.length; i++) {
      final item = topRated[i];
      final bg = i.isEven ? beigeAlt : '#FFFFFF';
      _writeXlsxRow(
        sheet,
        row,
        [
          excel.IntCellValue(i + 1),
          excel.TextCellValue(item.name),
          excel.TextCellValue(AdminFormatters.decimal(item.value)),
          excel.IntCellValue(item.secondaryValue.round()),
        ],
        style: _xlsxBorderedStyle(backgroundHex: bg),
      );
      row++;
    }
    row++;

    // -------------------------------------------------------------------------
    // Most cancelled products
    // -------------------------------------------------------------------------
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
        excel.TextCellValue('Most Cancelled Products');
    sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle =
        sectionTitle;
    row++;
    _writeXlsxRow(
      sheet,
      row,
      [
        excel.TextCellValue('Rank'),
        excel.TextCellValue('Product Name'),
        excel.TextCellValue('Cancellations'),
        excel.TextCellValue('Cancellation Rate %'),
      ],
      style: tableHeader,
    );
    row++;
    for (var i = 0; i < mostCancelled.length; i++) {
      final item = mostCancelled[i];
      final gross = grossByProduct[item.productId] ?? 0;
      final rate = gross == 0 ? 0.0 : (item.value / gross) * 100;
      final bg = i.isEven ? beigeAlt : '#FFFFFF';
      _writeXlsxRow(
        sheet,
        row,
        [
          excel.IntCellValue(i + 1),
          excel.TextCellValue(item.name),
          excel.IntCellValue(item.value.round()),
          excel.TextCellValue(AdminFormatters.decimal(rate)),
        ],
        style: _xlsxBorderedStyle(backgroundHex: bg),
      );
      row++;
    }

    _autoFitXlsxColumns(sheet, 4);

    final encoded = workbook.encode();
    if (encoded == null || encoded.isEmpty) {
      throw StateError('Failed to encode XLSX workbook.');
    }
    return Uint8List.fromList(encoded);
  }

  Future<pw.Document> _buildPdfDocumentForGranularity() async {
    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    pw.MemoryImage? logo;
    try {
      final bytes = (await rootBundle.load('assets/images/logo.jpg')).buffer.asUint8List();
      logo = pw.MemoryImage(bytes);
    } catch (_) {
      logo = null;
    }

    const walnut = PdfColor.fromInt(0xFF5D4037);
    final headerDecoration = const pw.BoxDecoration(color: walnut);
    final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white);

    final summary = _summaryRows();
    final trendRows = _dailyRevenueTrendRows
        .map(
          (e) => <String>[
            DateFormat.yMMMd().format(e.date),
            AdminFormatters.count(e.orders),
            AdminFormatters.currency(e.revenue),
            AdminFormatters.currency(e.avgOrderValue),
          ],
        )
        .toList();
    final grossByProduct = _productGrossOrderCounts;
    final bestRows = <List<String>>[];
    for (var i = 0; i < _bestSellingInMonth.length; i++) {
      final e = _bestSellingInMonth[i];
      bestRows.add([
        '${i + 1}',
        e.name,
        AdminFormatters.decimal(e.value, digits: 0),
        AdminFormatters.currency(e.secondaryValue),
      ]);
    }
    final ratedRows = <List<String>>[];
    for (var i = 0; i < _topRatedInMonth.length; i++) {
      final e = _topRatedInMonth[i];
      ratedRows.add([
        '${i + 1}',
        e.name,
        AdminFormatters.decimal(e.value),
        AdminFormatters.decimal(e.secondaryValue, digits: 0),
      ]);
    }
    final cancelledRows = <List<String>>[];
    for (var i = 0; i < _mostCancelledInMonth.length; i++) {
      final e = _mostCancelledInMonth[i];
      final gross = grossByProduct[e.productId] ?? 0;
      final rate = gross == 0 ? 0.0 : (e.value / gross) * 100;
      cancelledRows.add([
        '${i + 1}',
        e.name,
        AdminFormatters.decimal(e.value, digits: 0),
        AdminFormatters.decimal(rate),
      ]);
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(24),
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null)
                  pw.Container(
                    width: 44,
                    height: 44,
                    margin: const pw.EdgeInsets.only(right: 12),
                    child: pw.Image(logo),
                  ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _storeBrandName,
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Sales Report (${_granularityLabel.toUpperCase()})',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Date Range: $_exportDateRangeLabel',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.brown800,
                      ),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Text(
                  'Generated ${AdminFormatters.dateYmdHm(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Summary', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Metric', 'Value'],
            data: summary.map((e) => <String>[e.$1, e.$2]).toList(),
            headerStyle: headerStyle,
            headerDecoration: headerDecoration,
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Revenue Trend', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Date', 'Orders', 'Revenue', 'Avg Order Value'],
            data: trendRows,
            headerStyle: headerStyle,
            headerDecoration: headerDecoration,
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Top Selling Products',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Rank', 'Product Name', 'Units Sold', 'Revenue'],
            data: bestRows,
            headerStyle: headerStyle,
            headerDecoration: headerDecoration,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Top Rated Products',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Rank', 'Product Name', 'Avg Rating', 'No. of Reviews'],
            data: ratedRows,
            headerStyle: headerStyle,
            headerDecoration: headerDecoration,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Most Cancelled Products',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const <String>[
              'Rank',
              'Product Name',
              'Cancellations',
              'Cancellation Rate %',
            ],
            data: cancelledRows,
            headerStyle: headerStyle,
            headerDecoration: headerDecoration,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
        ],
      ),
    );
    return doc;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadData, child: const Text('Try again')),
          ],
        ),
      );
    }

    final summary = _summaryRows();
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          _ReportKpiStrip(summary: summary),
          const SizedBox(height: 14),
          _SalesTrendSection(
            granularity: _trendGranularity,
            onGranularityChanged: (g) => setState(() => _trendGranularity = g),
            selectedLabel: _selectedPeriodLabel,
            rangeFrom: _rangeFrom,
            rangeTo: _rangeTo,
            activeRangeField: _activeRangeField,
            formatRangeDate: _formatRangeButtonDate,
            onPickRangeFrom: _pickRangeFrom,
            onPickRangeTo: _pickRangeTo,
            onClearRange: _hasCustomRange ? _clearDateRange : null,
            onExport: _exporting ? null : _exportExcelXlsx,
            onPrint: _exporting ? null : _printPdfReport,
            points: _activeTrendPoints,
            trendXFormatter: (x) => _salesTrendXLabel(_trendGranularity, x),
          ),
          const SizedBox(height: 16),
          _SalesBreakdownSection(
            orders: _monthOrders,
            orderRevenueForSalesReports: _orderRevenueForSalesReports,
          ),
          const SizedBox(height: 16),
          AdminInsightPanelRow(
            columns: [
              AdminInsightColumn(
                title: 'Top Selling Products',
                segmentLabels: const ['Units', 'Revenue', 'All'],
                activeSegment: _insightSegments[0],
                onSegmentSelected: (i) => setState(() => _insightSegments[0] = i),
                entries: _toInsightEntries(
                  _bestSellingInMonth.take(6).toList(growable: false),
                  valueOf: (e) => _insightSegments[0] == 1 ? e.secondaryValue : e.value,
                  labelOf: (e) => e.name,
                  displayOf: (e) => _insightSegments[0] == 1
                      ? AdminFormatters.currency(e.secondaryValue)
                      : AdminFormatters.decimal(e.value, digits: 0),
                ),
              ),
              AdminInsightColumn(
                title: 'Top Rated Products',
                segmentLabels: const ['Rating', 'Reviews', 'All'],
                activeSegment: _insightSegments[1],
                onSegmentSelected: (i) => setState(() => _insightSegments[1] = i),
                entries: _toInsightEntries(
                  _topRatedInMonth.take(6).toList(growable: false),
                  valueOf: (e) => _insightSegments[1] == 1 ? e.secondaryValue : e.value,
                  labelOf: (e) => e.name,
                  displayOf: (e) => _insightSegments[1] == 1
                      ? AdminFormatters.decimal(e.secondaryValue, digits: 0)
                      : '${AdminFormatters.decimal(e.value)}★',
                ),
              ),
              AdminInsightColumn(
                title: 'Most Cancelled Products',
                segmentLabels: const ['Units', 'Rate', 'All'],
                activeSegment: _insightSegments[2],
                onSegmentSelected: (i) => setState(() => _insightSegments[2] = i),
                entries: _toInsightEntries(
                  _mostCancelledInMonth.take(6).toList(growable: false),
                  valueOf: (e) => e.value,
                  labelOf: (e) => e.name,
                  displayOf: (e) => AdminFormatters.decimal(e.value, digits: 0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<AdminInsightEntry> _toInsightEntries(
    List<_SalesProductStat> rows, {
    required double Function(_SalesProductStat row) valueOf,
    required String Function(_SalesProductStat row) labelOf,
    required String Function(_SalesProductStat row) displayOf,
  }) {
    final max = rows.isEmpty ? 1.0 : rows.map(valueOf).reduce((a, b) => a > b ? a : b);
    return rows
        .map(
          (r) => AdminInsightEntry(
            label: labelOf(r),
            value: displayOf(r),
            progress: max <= 0 ? 0 : valueOf(r) / max,
          ),
        )
        .toList(growable: false);
  }
}

class _DailyRevenueTrendRow {
  const _DailyRevenueTrendRow({
    required this.date,
    required this.orders,
    required this.revenue,
    required this.avgOrderValue,
  });

  final DateTime date;
  final int orders;
  final double revenue;
  final double avgOrderValue;
}

class _SalesProductStat {
  const _SalesProductStat({
    required this.productId,
    required this.name,
    required this.value,
    required this.secondaryValue,
  });

  final String productId;
  final String name;
  final double value;
  final double secondaryValue;
}

class _ReportKpiStrip extends StatelessWidget {
  const _ReportKpiStrip({required this.summary});

  final List<(String, String)> summary;

  @override
  Widget build(BuildContext context) {
    final primary = summary.take(4).map(
          (item) => AdminKpiItem(
            title: item.$1,
            value: item.$2,
            subtitle: 'Compare to last period',
            accent: AdminAnalyticsColors.primary,
            icon: _iconForMetric(item.$1),
          ),
        );
    return AdminKpiStripRow(items: primary.toList(growable: false));
  }

  IconData _iconForMetric(String metric) {
    final m = metric.toLowerCase();
    if (m.contains('sales')) return Icons.payments_outlined;
    if (m.contains('order')) return Icons.shopping_cart_outlined;
    if (m.contains('cancel')) return Icons.cancel_schedule_send_outlined;
    return Icons.trending_up_outlined;
  }
}

class _SalesRangeDateButton extends StatelessWidget {
  const _SalesRangeDateButton({
    required this.caption,
    required this.dateLabel,
    required this.isActive,
    required this.hasValue,
    required this.onPressed,
  });

  final String caption;
  final String dateLabel;
  final bool isActive;
  final bool hasValue;
  final VoidCallback onPressed;

  static const Color _walnut = Color(0xFF5D4037);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minWidth: 128),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isActive
                ? _walnut.withValues(alpha: 0.14)
                : hasValue
                    ? const Color(0xFFF9F5F2)
                    : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? _walnut : const Color(0xFFD7CCC8),
              width: isActive ? 2 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: _walnut.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                caption,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isActive ? _walnut : const Color(0xFF8D6E63),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
                  color: hasValue ? const Color(0xFF3E2723) : const Color(0xFF9E9E9E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesTrendSection extends StatelessWidget {
  const _SalesTrendSection({
    required this.granularity,
    required this.onGranularityChanged,
    required this.selectedLabel,
    required this.rangeFrom,
    required this.rangeTo,
    required this.activeRangeField,
    required this.formatRangeDate,
    required this.onPickRangeFrom,
    required this.onPickRangeTo,
    this.onClearRange,
    required this.onExport,
    required this.onPrint,
    required this.points,
    required this.trendXFormatter,
  });

  final AdminTrendGranularity granularity;
  final ValueChanged<AdminTrendGranularity> onGranularityChanged;
  final String selectedLabel;
  final DateTime? rangeFrom;
  final DateTime? rangeTo;
  final _SalesRangeField activeRangeField;
  final String Function(DateTime date) formatRangeDate;
  final VoidCallback onPickRangeFrom;
  final VoidCallback onPickRangeTo;
  final VoidCallback? onClearRange;
  final VoidCallback? onExport;
  final VoidCallback? onPrint;
  final List<AdminSeriesPoint> points;
  final String Function(DateTime x) trendXFormatter;

  @override
  Widget build(BuildContext context) {
    const rangeSeparatorColor = Color(0xFF8D6E63);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<AdminTrendGranularity>(
                  segments: const [
                    ButtonSegment(value: AdminTrendGranularity.weekly, label: Text('Weekly')),
                    ButtonSegment(value: AdminTrendGranularity.monthly, label: Text('Monthly')),
                    ButtonSegment(value: AdminTrendGranularity.yearly, label: Text('Yearly')),
                  ],
                  selected: {granularity},
                  onSelectionChanged: (s) {
                    if (s.isEmpty) return;
                    onGranularityChanged(s.first);
                  },
                ),
                const Spacer(),
                // Date inputs scroll when crowded; ellipsis stays pinned on the right.
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SalesRangeDateButton(
                          caption: 'From',
                          dateLabel: rangeFrom == null ? 'Select date' : formatRangeDate(rangeFrom!),
                          isActive: activeRangeField == _SalesRangeField.from,
                          hasValue: rangeFrom != null,
                          onPressed: onPickRangeFrom,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: rangeSeparatorColor.withValues(alpha: 0.85),
                          ),
                        ),
                        _SalesRangeDateButton(
                          caption: 'To',
                          dateLabel: rangeTo == null ? 'Select date' : formatRangeDate(rangeTo!),
                          isActive: activeRangeField == _SalesRangeField.to,
                          hasValue: rangeTo != null,
                          onPressed: onPickRangeTo,
                        ),
                        if (onClearRange != null) ...[
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: onClearRange,
                            icon: const Icon(Icons.clear_outlined, size: 18),
                            label: const Text('Clear'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF8D6E63),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: const Color(0xFFE0E0E0),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Report actions',
                  enabled: onExport != null || onPrint != null,
                  offset: const Offset(0, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  itemBuilder: (context) => [
                    if (onExport != null)
                      const PopupMenuItem(
                        value: 'excel',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.table_view_outlined, size: 20),
                          title: Text('Export Excel'),
                        ),
                      ),
                    if (onPrint != null)
                      const PopupMenuItem(
                        value: 'pdf',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.picture_as_pdf_outlined, size: 20),
                          title: Text('Print PDF'),
                        ),
                      ),
                  ],
                  onSelected: (value) {
                    switch (value) {
                      case 'excel':
                        onExport?.call();
                      case 'pdf':
                        onPrint?.call();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD7CCC8)),
                      color: Colors.white,
                    ),
                    child: const Icon(Icons.more_horiz, size: 22, color: Color(0xFF5D4037)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Report period: $selectedLabel',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF5D4037),
                  ),
            ),
            const SizedBox(height: 12),
            AdminUnifiedTrendChartCard(
              title: granularity == AdminTrendGranularity.weekly
                  ? 'Revenue Trend (Weekly)'
                  : granularity == AdminTrendGranularity.monthly
                      ? 'Revenue Trend (Monthly)'
                      : 'Revenue Trend (Yearly)',
              subtitle: granularity == AdminTrendGranularity.weekly
                  ? 'Net revenue Mon–Sun for the current week (or your custom date range).'
                  : granularity == AdminTrendGranularity.monthly
                      ? 'Net revenue for weeks 1–4 inside the selected month only.'
                      : 'Net revenue per month for the selected calendar year.',
              seriesLabel: 'Net revenue',
              points: points,
              granularity: granularity,
              onGranularityChanged: onGranularityChanged,
              showGranularitySelector: false,
              valueFormatter: AdminFormatters.currency,
              xAxisLabelFormatter: trendXFormatter,
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesBreakdownSection extends StatelessWidget {
  const _SalesBreakdownSection({
    required this.orders,
    required this.orderRevenueForSalesReports,
  });

  final List<OrderRecord> orders;
  final double Function(OrderRecord) orderRevenueForSalesReports;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sales Breakdown Details',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 10),
            if (orders.isEmpty)
              const Text('No orders in selected period.')
            else
              ...orders.take(20).map((order) {
                final customer = order.userName.trim().isEmpty ? order.userId : order.userName;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${order.id.substring(0, 8).toUpperCase()} · $customer',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(AdminFormatters.currency(orderRevenueForSalesReports(order))),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

