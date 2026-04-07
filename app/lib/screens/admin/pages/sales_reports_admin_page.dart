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
import '../../../utils/report_file_saver.dart';
import '../../../widgets/toast.dart';
import '../widgets/admin_toolbar.dart';

class SalesReportsAdminPage extends StatefulWidget {
  const SalesReportsAdminPage({super.key});

  @override
  State<SalesReportsAdminPage> createState() => _SalesReportsAdminPageState();
}

class _SalesReportsAdminPageState extends State<SalesReportsAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final DateFormat _monthLabel = DateFormat('MMMM yyyy');
  final DateFormat _axisMonthLabel = DateFormat('MMM');
  final DateFormat _dateLabel = DateFormat('yyyy-MM-dd');

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<OrderRecord> _orders = const [];
  List<Product> _products = const [];
  List<Review> _reviews = const [];
  bool _loading = true;
  bool _exporting = false;
  String? _error;

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

  List<_MonthPoint> get _monthlyTrend {
    final points = <_MonthPoint>[];
    for (var i = 11; i >= 0; i--) {
      final month = DateTime(_selectedMonth.year, _selectedMonth.month - i, 1);
      final nextMonth = DateTime(month.year, month.month + 1, 1);
      final value = _orders
          .where((o) {
            final s = o.status.toLowerCase();
            if (s == 'cancelled') return false;
            return !o.createdAt.isBefore(month) && o.createdAt.isBefore(nextMonth);
          })
          .fold<double>(0, (sum, o) => sum + o.totalAmount);
      points.add(_MonthPoint(month: month, sales: value));
    }
    return points;
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
      final filename = 'sales_report_${DateFormat('yyyy_MM').format(_selectedMonth)}.csv';
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
    buffer.writeln('Sales Report,${_csv(_monthLabel.format(_selectedMonth))}');
    buffer.writeln('Generated At,${_csv(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()))}');
    buffer.writeln('');
    buffer.writeln('Summary,Value');
    for (final row in summary) {
      buffer.writeln('${_csv(row.$1)},${_csv(row.$2)}');
    }
    buffer.writeln('');
    buffer.writeln('Daily Sales Date,Amount');
    _dailySales.forEach((date, value) {
      buffer.writeln('${_csv(_dateLabel.format(date))},${value.toStringAsFixed(2)}');
    });
    buffer.writeln('');
    buffer.writeln('Best Selling Products');
    buffer.writeln('Product,Units Sold,Estimated Revenue');
    for (final item in _bestSellingInMonth) {
      buffer.writeln('${_csv(item.name)},${item.value.toStringAsFixed(0)},${item.secondaryValue.toStringAsFixed(2)}');
    }
    buffer.writeln('');
    buffer.writeln('Top Rated Products');
    buffer.writeln('Product,Average Rating,Review Count');
    for (final item in _topRatedInMonth) {
      buffer.writeln('${_csv(item.name)},${item.value.toStringAsFixed(2)},${item.secondaryValue.toStringAsFixed(0)}');
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
    return <(String, String)>[
      ('Total Sales', 'PHP ${_monthSales.toStringAsFixed(2)}'),
      ('Total Orders', '${_monthOrders.length}'),
      ('Average Order Value', 'PHP ${avgOrderValue.toStringAsFixed(2)}'),
      ('Best Selling Product', topBestSeller),
      ('Top Rated Product', topRated),
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
        .map((e) => <String>[_dateLabel.format(e.key), 'PHP ${e.value.toStringAsFixed(2)}'])
        .toList();
    final bestRows = _bestSellingInMonth
        .map((e) => <String>[e.name, e.value.toStringAsFixed(0), 'PHP ${e.secondaryValue.toStringAsFixed(2)}'])
        .toList();
    final ratedRows = _topRatedInMonth
        .map((e) => <String>[e.name, e.value.toStringAsFixed(2), e.secondaryValue.toStringAsFixed(0)])
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
                      'Sales Report - ${_monthLabel.format(_selectedMonth)}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Text(
                  'Generated ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          AdminToolbar(
            title: 'Sales Reports',
            actions: [
              AdminToolbarAction(label: 'Refresh', icon: Icons.refresh, onPressed: _loadData),
              AdminToolbarAction(
                label: 'Export Excel',
                icon: Icons.table_view_outlined,
                onPressed: _exporting ? null : _exportExcelCsv,
                primary: true,
              ),
              AdminToolbarAction(
                label: 'Print PDF',
                icon: Icons.picture_as_pdf_outlined,
                onPressed: _exporting ? null : _printPdfReport,
              ),
            ],
            trailing: FilledButton.icon(
              onPressed: _pickMonth,
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(_monthLabel.format(_selectedMonth)),
            ),
            showTitle: true,
          ),
          const SizedBox(height: 10),
          _SummaryCards(summary: summary),
          const SizedBox(height: 16),
          _SalesChartCard(
            points: _monthlyTrend,
            axisFormatter: _axisMonthLabel,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1000;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _BestSellingCard(items: _bestSellingInMonth),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _TopRatedCard(items: _topRatedInMonth),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  _BestSellingCard(items: _bestSellingInMonth),
                  const SizedBox(height: 16),
                  _TopRatedCard(items: _topRatedInMonth),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.summary});

  final List<(String, String)> summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 5 : constraints.maxWidth >= 760 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: summary.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.3,
          ),
          itemBuilder: (context, index) {
            final item = summary[index];
            return DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE3E8EF)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(item.$1, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700])),
                    const SizedBox(height: 6),
                    Text(item.$2, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SalesChartCard extends StatelessWidget {
  const _SalesChartCard({required this.points, required this.axisFormatter});

  final List<_MonthPoint> points;
  final DateFormat axisFormatter;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monthly Sales Trend', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: points.isEmpty
                  ? const Center(child: Text('No data'))
                  : _LineChart(points: points, axisFormatter: axisFormatter),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.points, required this.axisFormatter});

  final List<_MonthPoint> points;
  final DateFormat axisFormatter;

  @override
  Widget build(BuildContext context) {
    final maxSales = points.fold<double>(0, (max, p) => p.sales > max ? p.sales : max);
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _LineChartPainter(points: points, maxValue: maxSales <= 0 ? 1 : maxSales),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final p in points.where((e) => e.month.month.isEven))
              Text(axisFormatter.format(p.month), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.points, required this.maxValue});

  final List<_MonthPoint> points;
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final gridPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = const Color(0xFF8D6E63)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = const Color(0xFF8D6E63).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final path = Path();
    final area = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height - ((points[i].sales / maxValue) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
        area.moveTo(x, size.height);
        area.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        area.lineTo(x, y);
      }
    }
    area.lineTo(size.width, size.height);
    area.close();

    canvas.drawPath(area, fillPaint);
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = const Color(0xFF5D4037);
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height - ((points[i].sales / maxValue) * size.height);
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.maxValue != maxValue;
  }
}

class _BestSellingCard extends StatelessWidget {
  const _BestSellingCard({required this.items});

  final List<_SalesProductStat> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Best Selling Products', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Text('No sales data for selected month.')
            else
              ...items.take(8).map(
                    (e) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Est. revenue: PHP ${e.secondaryValue.toStringAsFixed(2)}'),
                      trailing: Text('${e.value.toStringAsFixed(0)} sold'),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _TopRatedCard extends StatelessWidget {
  const _TopRatedCard({required this.items});

  final List<_SalesProductStat> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top Rated Products', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Text('No ratings available.')
            else
              ...items.take(8).map(
                    (e) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${e.secondaryValue.toStringAsFixed(0)} reviews'),
                      trailing: Text('${e.value.toStringAsFixed(2)} / 5'),
                    ),
                  ),
          ],
        ),
      ),
    );
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

class _MonthPoint {
  const _MonthPoint({required this.month, required this.sales});

  final DateTime month;
  final double sales;
}
