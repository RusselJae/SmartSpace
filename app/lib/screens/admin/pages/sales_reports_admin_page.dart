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

class SalesReportsAdminPage extends StatefulWidget {
  const SalesReportsAdminPage({super.key});

  @override
  State<SalesReportsAdminPage> createState() => _SalesReportsAdminPageState();
}

class _SalesReportsAdminPageState extends State<SalesReportsAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  AdminTrendGranularity _trendGranularity = AdminTrendGranularity.monthly;
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

  Future<void> _pickSelectedPeriod() async {
    final now = DateTime.now();
    final base = Theme.of(context);
    final pickerTheme = base.copyWith(
      dialogTheme: base.dialogTheme.copyWith(backgroundColor: Colors.white),
      colorScheme: base.colorScheme.copyWith(surface: Colors.white),
      datePickerTheme: base.datePickerTheme.copyWith(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        rangeSelectionBackgroundColor: const Color(0xFF8D6E63).withValues(alpha: 0.12),
      ),
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: _trendGranularity == AdminTrendGranularity.weekly
          ? 'Select any day in the report week (Mon–Sun)'
          : _trendGranularity == AdminTrendGranularity.monthly
              ? 'Select report month'
              : 'Select report year',
      builder: (context, child) => Theme(
        data: pickerTheme,
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = _trendGranularity == AdminTrendGranularity.weekly
          ? DateTime(picked.year, picked.month, picked.day)
          : _trendGranularity == AdminTrendGranularity.monthly
              ? DateTime(picked.year, picked.month, 1)
              : DateTime(picked.year, 1, 1);
    });
  }

  DateTime get _periodStart {
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

  String _trendXAxisLabel(DateTime date) => _salesTrendXLabel(_trendGranularity, date);

  Future<void> _exportExcelXlsx() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = _buildXlsxForGranularity();
      final filename =
          'sales_report_${_granularityLabel}_${_selectedDate.year}_${_selectedDate.month.toString().padLeft(2, '0')}_${_selectedDate.day.toString().padLeft(2, '0')}.xlsx';
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

  Uint8List _buildXlsxForGranularity() {
    final workbook = excel.Excel.createExcel();
    workbook.delete('Sheet1');

    final generatedAt = AdminFormatters.dateYmdHm(DateTime.now());
    final trend = _activeTrendPoints;
    final summaryRows = _summaryRows();
    final topSelling = _bestSellingInMonth;
    final topRated = _topRatedInMonth;
    final mostCancelled = _mostCancelledInMonth;

    final overview = workbook['Overview'];
    overview.setColumnWidth(0, 34);
    overview.setColumnWidth(1, 30);
    overview.appendRow([
      excel.TextCellValue('Wood Home Furniture Trading'),
      excel.TextCellValue(''),
    ]);
    overview.appendRow([
      excel.TextCellValue('Sales Report (${_granularityLabel.toUpperCase()})'),
      excel.TextCellValue(_selectedPeriodLabel),
    ]);
    overview.appendRow([
      excel.TextCellValue('Generated At'),
      excel.TextCellValue(generatedAt),
    ]);
    overview.appendRow([excel.TextCellValue(''), excel.TextCellValue('')]);
    overview.appendRow([excel.TextCellValue('Summary'), excel.TextCellValue('Value')]);
    for (final row in summaryRows) {
      overview.appendRow([excel.TextCellValue(row.$1), excel.TextCellValue(row.$2)]);
    }

    final trendSheet = workbook['Revenue Trend'];
    trendSheet.setColumnWidth(0, 20);
    trendSheet.setColumnWidth(1, 18);
    trendSheet.appendRow([
      excel.TextCellValue(_granularityLabel.toUpperCase()),
      excel.TextCellValue('Amount'),
    ]);
    for (final p in trend) {
      trendSheet.appendRow([
        excel.TextCellValue(_trendXAxisLabel(p.x)),
        excel.DoubleCellValue(p.y),
      ]);
    }

    final sellingSheet = workbook['Top Selling'];
    sellingSheet.setColumnWidth(0, 30);
    sellingSheet.setColumnWidth(1, 14);
    sellingSheet.setColumnWidth(2, 18);
    sellingSheet.appendRow([
      excel.TextCellValue('Product'),
      excel.TextCellValue('Units Sold'),
      excel.TextCellValue('Estimated Revenue'),
    ]);
    for (final item in topSelling) {
      sellingSheet.appendRow([
        excel.TextCellValue(item.name),
        excel.DoubleCellValue(item.value),
        excel.DoubleCellValue(item.secondaryValue),
      ]);
    }

    final ratedSheet = workbook['Top Rated'];
    ratedSheet.setColumnWidth(0, 30);
    ratedSheet.setColumnWidth(1, 14);
    ratedSheet.setColumnWidth(2, 14);
    ratedSheet.appendRow([
      excel.TextCellValue('Product'),
      excel.TextCellValue('Average Rating'),
      excel.TextCellValue('Review Count'),
    ]);
    for (final item in topRated) {
      ratedSheet.appendRow([
        excel.TextCellValue(item.name),
        excel.DoubleCellValue(item.value),
        excel.DoubleCellValue(item.secondaryValue),
      ]);
    }

    final cancelledSheet = workbook['Most Cancelled'];
    cancelledSheet.setColumnWidth(0, 30);
    cancelledSheet.setColumnWidth(1, 20);
    cancelledSheet.appendRow([
      excel.TextCellValue('Product'),
      excel.TextCellValue('Cancelled Orders'),
    ]);
    for (final item in mostCancelled) {
      cancelledSheet.appendRow([
        excel.TextCellValue(item.name),
        excel.DoubleCellValue(item.value),
      ]);
    }

    final encoded = workbook.encode();
    if (encoded == null || encoded.isEmpty) {
      throw StateError('Failed to encode XLSX workbook.');
    }
    return Uint8List.fromList(encoded);
  }

  List<(String, String)> _summaryRows() {
    final avgOrderValue = _monthOrders.isEmpty ? 0.0 : _monthSales / _monthOrders.length;
    final topBestSeller = _bestSellingInMonth.isEmpty ? '-' : _bestSellingInMonth.first.name;
    final topRated = _topRatedInMonth.isEmpty ? '-' : _topRatedInMonth.first.name;
    final topCancelled = _mostCancelledInMonth.isEmpty ? '-' : _mostCancelledInMonth.first.name;
    return <(String, String)>[
      ('Total Sales', AdminFormatters.currency(_monthSales)),
      ('Total Orders', AdminFormatters.count(_monthOrders.length)),
      ('Cancelled Orders', AdminFormatters.count(_monthCancelledOrders.length)),
      ('Average Order Value', AdminFormatters.currency(avgOrderValue)),
      ('Best Selling Product', topBestSeller),
      ('Top Rated Product', topRated),
      ('Most Cancelled Product', topCancelled),
    ];
  }

  Future<pw.Document> _buildPdfDocumentForGranularity() async {
    final doc = pw.Document();
    pw.MemoryImage? logo;
    try {
      final bytes = (await rootBundle.load('assets/images/logo.jpg')).buffer.asUint8List();
      logo = pw.MemoryImage(bytes);
    } catch (_) {
      logo = null;
    }

    final summary = _summaryRows();
    final trendRows = _activeTrendPoints
        .map(
          (e) => <String>[
            _trendXAxisLabel(e.x),
            AdminFormatters.currency(e.y),
          ],
        )
        .toList();
    final bestRows = _bestSellingInMonth
        .map((e) => <String>[
              e.name,
              AdminFormatters.decimal(e.value, digits: 0),
              AdminFormatters.currency(e.secondaryValue),
            ])
        .toList();
    final ratedRows = _topRatedInMonth
        .map((e) => <String>[
              e.name,
              AdminFormatters.decimal(e.value),
              AdminFormatters.decimal(e.secondaryValue, digits: 0),
            ])
        .toList();
    final cancelledRows = _mostCancelledInMonth
        .map((e) => <String>[e.name, AdminFormatters.decimal(e.value, digits: 0)])
        .toList();

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
                      'Wood Home Furniture Trading',
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Sales Report (${_granularityLabel.toUpperCase()}) - $_selectedPeriodLabel',
                      style: const pw.TextStyle(fontSize: 11),
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
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            '${_granularityLabel[0].toUpperCase()}${_granularityLabel.substring(1)} Revenue Report',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: <String>[_granularityLabel.toUpperCase(), 'Amount'],
            data: trendRows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey700),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Best Selling Products', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Product', 'Units Sold', 'Estimated Revenue'],
            data: bestRows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.brown700),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Top Rated Products', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Product', 'Avg Rating', 'Review Count'],
            data: ratedRows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Most Cancelled Products', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Product', 'Cancelled Orders'],
            data: cancelledRows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
            onPickDate: _pickSelectedPeriod,
            onExport: _exporting ? null : _exportExcelXlsx,
            onPrint: _exporting ? null : _printPdfReport,
            points: _activeTrendPoints,
            trendXFormatter: (x) => _salesTrendXLabel(_trendGranularity, x),
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

class _SalesTrendSection extends StatelessWidget {
  const _SalesTrendSection({
    required this.granularity,
    required this.onGranularityChanged,
    required this.selectedLabel,
    required this.onPickDate,
    required this.onExport,
    required this.onPrint,
    required this.points,
    required this.trendXFormatter,
  });

  final AdminTrendGranularity granularity;
  final ValueChanged<AdminTrendGranularity> onGranularityChanged;
  final String selectedLabel;
  final VoidCallback onPickDate;
  final VoidCallback? onExport;
  final VoidCallback? onPrint;
  final List<AdminSeriesPoint> points;
  final String Function(DateTime x) trendXFormatter;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                IconButton.outlined(
                  onPressed: onPickDate,
                  tooltip: selectedLabel,
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: onExport,
                  tooltip: 'Export XLSX',
                  icon: const Icon(Icons.table_view_outlined),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: onPrint,
                  tooltip: 'Print PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdminUnifiedTrendChartCard(
              title: granularity == AdminTrendGranularity.weekly
                  ? 'Revenue Trend (Weekly)'
                  : granularity == AdminTrendGranularity.monthly
                      ? 'Revenue Trend (Monthly)'
                      : 'Revenue Trend (Yearly)',
              subtitle: granularity == AdminTrendGranularity.weekly
                  ? 'Net revenue Mon–Sun for the week you picked on the calendar.'
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

