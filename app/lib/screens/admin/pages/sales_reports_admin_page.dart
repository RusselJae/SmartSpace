import 'dart:typed_data';

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

class SalesReportsAdminPage extends StatefulWidget {
  const SalesReportsAdminPage({super.key});

  @override
  State<SalesReportsAdminPage> createState() => _SalesReportsAdminPageState();
}

class _SalesReportsAdminPageState extends State<SalesReportsAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
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

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Select report month',
    );
    if (picked == null) return;
    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month, 1);
    });
  }

  DateTime get _monthStart => DateTime(_selectedMonth.year, _selectedMonth.month, 1);
  DateTime get _monthEnd => DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);

  bool _isIncludedOrder(OrderRecord o) {
    final status = o.status.toLowerCase();
    return status != 'cancelled' && !o.createdAt.isBefore(_monthStart) && o.createdAt.isBefore(_monthEnd);
  }

  List<OrderRecord> get _monthOrders => _orders.where(_isIncludedOrder).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<OrderRecord> get _monthCancelledOrders => _orders
      .where((o) =>
          o.status.toLowerCase() == 'cancelled' &&
          !o.createdAt.isBefore(_monthStart) &&
          o.createdAt.isBefore(_monthEnd))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  double get _monthSales => _monthOrders.fold<double>(0, (s, o) => s + o.totalAmount);

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
      if (review.createdAt.isBefore(_monthStart) || !review.createdAt.isBefore(_monthEnd)) {
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

  bool _isCancelled(OrderRecord o) => o.status.toLowerCase() == 'cancelled';

  double _revenueInRange(DateTime start, DateTime end) {
    return _orders
        .where((o) => !_isCancelled(o) && !o.createdAt.isBefore(start) && o.createdAt.isBefore(end))
        .fold<double>(0, (sum, o) => sum + o.totalAmount);
  }

  List<AdminSeriesPoint> get _dailyTrendPoints {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
    final points = <AdminSeriesPoint>[];
    for (var i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final next = day.add(const Duration(days: 1));
      points.add(AdminSeriesPoint(x: day, y: _revenueInRange(day, next)));
    }
    return points;
  }

  List<AdminSeriesPoint> get _monthlyTrendPoints {
    final points = <AdminSeriesPoint>[];
    for (var i = 11; i >= 0; i--) {
      final month = DateTime(_selectedMonth.year, _selectedMonth.month - i, 1);
      final next = DateTime(month.year, month.month + 1, 1);
      points.add(AdminSeriesPoint(x: month, y: _revenueInRange(month, next)));
    }
    return points;
  }

  List<AdminSeriesPoint> get _yearlyTrendPoints {
    final y0 = _selectedMonth.year;
    final points = <AdminSeriesPoint>[];
    for (var i = 11; i >= 0; i--) {
      final year = y0 - i;
      final start = DateTime(year, 1, 1);
      final end = DateTime(year + 1, 1, 1);
      points.add(AdminSeriesPoint(x: DateTime(year, 7, 1), y: _revenueInRange(start, end)));
    }
    return points;
  }

  List<AdminSeriesPoint> get _activeTrendPoints {
    switch (_trendGranularity) {
      case AdminTrendGranularity.daily:
        return _dailyTrendPoints;
      case AdminTrendGranularity.monthly:
        return _monthlyTrendPoints;
      case AdminTrendGranularity.yearly:
        return _yearlyTrendPoints;
    }
  }

  Map<DateTime, double> get _dailySales {
    final map = <DateTime, double>{};
    for (final order in _monthOrders) {
      final key = DateTime(order.createdAt.year, order.createdAt.month, order.createdAt.day);
      map[key] = (map[key] ?? 0) + order.totalAmount;
    }
    final sortedKeys = map.keys.toList()..sort((a, b) => a.compareTo(b));
    return {
      for (final key in sortedKeys) key: map[key]!,
    };
  }

  Future<void> _exportExcelCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final csv = _buildCsv();
      final bytes = Uint8List.fromList(csv.codeUnits);
      final filename = 'sales_report_${AdminFormatters.monthKey(_selectedMonth)}.csv';
      final savedAt = await saveReportFile(
        filename: filename,
        bytes: bytes,
        mimeType: 'text/csv;charset=utf-8',
      );
      if (!mounted) return;
      Toast.success(context, 'Excel-compatible report exported: $savedAt');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to export CSV: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _printPdfReport() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final doc = await _buildPdfDocument();
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
      if (!mounted) return;
      Toast.success(context, 'PDF print dialog opened');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to generate PDF: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _buildCsv() {
    final buffer = StringBuffer();
    final summary = _summaryRows();
    buffer.writeln('Wood Home Furniture Trading');
    buffer.writeln('Sales Report,${_csv(AdminFormatters.monthYear(_selectedMonth))}');
    buffer.writeln('Generated At,${_csv(AdminFormatters.dateYmdHm(DateTime.now()))}');
    buffer.writeln('');
    buffer.writeln('Summary,Value');
    for (final row in summary) {
      buffer.writeln('${_csv(row.$1)},${_csv(row.$2)}');
    }
    buffer.writeln('');
    buffer.writeln('Daily Sales Date,Amount');
    _dailySales.forEach((date, value) {
      buffer.writeln('${_csv(AdminFormatters.dateYmd(date))},${AdminFormatters.decimal(value)}');
    });
    buffer.writeln('');
    buffer.writeln('Best Selling Products');
    buffer.writeln('Product,Units Sold,Estimated Revenue');
    for (final item in _bestSellingInMonth) {
      buffer.writeln(
        '${_csv(item.name)},${AdminFormatters.decimal(item.value, digits: 0)},${AdminFormatters.decimal(item.secondaryValue)}',
      );
    }
    buffer.writeln('');
    buffer.writeln('Top Rated Products');
    buffer.writeln('Product,Average Rating,Review Count');
    for (final item in _topRatedInMonth) {
      buffer.writeln(
        '${_csv(item.name)},${AdminFormatters.decimal(item.value)},${AdminFormatters.decimal(item.secondaryValue, digits: 0)}',
      );
    }
    return buffer.toString();
  }

  String _csv(String raw) {
    final escaped = raw.replaceAll('"', '""');
    return '"$escaped"';
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

  Future<pw.Document> _buildPdfDocument() async {
    final doc = pw.Document();
    pw.MemoryImage? logo;
    try {
      final bytes = (await rootBundle.load('assets/images/logo.jpg')).buffer.asUint8List();
      logo = pw.MemoryImage(bytes);
    } catch (_) {
      logo = null;
    }

    final summary = _summaryRows();
    final dailyRows = _dailySales.entries
        .map((e) => <String>[AdminFormatters.dateYmd(e.key), AdminFormatters.currency(e.value)])
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
                      'Sales Report - ${AdminFormatters.monthYear(_selectedMonth)}',
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
          pw.Text('Daily Sales Report', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const <String>['Date', 'Amount'],
            data: dailyRows,
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
            selectedMonth: _selectedMonth,
            onPickMonth: _pickMonth,
            onExport: _exporting ? null : _exportExcelCsv,
            onPrint: _exporting ? null : _printPdfReport,
            points: _activeTrendPoints,
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
    required this.selectedMonth,
    required this.onPickMonth,
    required this.onExport,
    required this.onPrint,
    required this.points,
  });

  final AdminTrendGranularity granularity;
  final ValueChanged<AdminTrendGranularity> onGranularityChanged;
  final DateTime selectedMonth;
  final VoidCallback onPickMonth;
  final VoidCallback? onExport;
  final VoidCallback? onPrint;
  final List<AdminSeriesPoint> points;

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
                const Spacer(),
                SegmentedButton<AdminTrendGranularity>(
                  segments: const [
                    ButtonSegment(value: AdminTrendGranularity.daily, label: Text('Daily')),
                    ButtonSegment(value: AdminTrendGranularity.monthly, label: Text('Monthly')),
                    ButtonSegment(value: AdminTrendGranularity.yearly, label: Text('Yearly')),
                  ],
                  selected: {granularity},
                  onSelectionChanged: (s) {
                    if (s.isEmpty) return;
                    onGranularityChanged(s.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (granularity == AdminTrendGranularity.daily)
              _SalesDailyTemplate(points: points)
            else if (granularity == AdminTrendGranularity.monthly)
              AdminUnifiedTrendChartCard(
                title: 'Revenue Trend (Monthly)',
                subtitle: 'Net revenue for each of the last 12 months.',
                seriesLabel: 'Net revenue',
                points: points,
                granularity: granularity,
                onGranularityChanged: onGranularityChanged,
                showGranularitySelector: false,
                valueFormatter: AdminFormatters.currency,
              )
            else
              _SalesYearlyTemplate(points: points),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onPickMonth,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(AdminFormatters.monthYear(selectedMonth)),
                ),
                OutlinedButton.icon(
                  onPressed: onExport,
                  icon: const Icon(Icons.table_view_outlined, size: 18),
                  label: const Text('Export CSV'),
                ),
                OutlinedButton.icon(
                  onPressed: onPrint,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Print PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesDailyTemplate extends StatelessWidget {
  const _SalesDailyTemplate({required this.points});
  final List<AdminSeriesPoint> points;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in points)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(AdminFormatters.currency(p.y), style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: points.isEmpty
                              ? 0
                              : (p.y / (points.map((e) => e.y).fold<double>(1, (a, b) => a > b ? a : b))).clamp(0.08, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFB7B0A6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(DateFormat.E().format(p.x), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SalesYearlyTemplate extends StatelessWidget {
  const _SalesYearlyTemplate({required this.points});
  final List<AdminSeriesPoint> points;
  @override
  Widget build(BuildContext context) {
    final max = points.isEmpty ? 1.0 : points.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final p in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 50, child: Text('${p.x.year}', style: Theme.of(context).textTheme.bodySmall)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (p.y / max).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: AdminAnalyticsColors.neutralTrack,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8D6E63)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: Text(
                    AdminFormatters.currency(p.y),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

