import 'package:flutter/material.dart';

import '../../../models/order_record.dart';
import '../../../services/mysql_database_service.dart';
import '../../../utils/admin_formatters.dart';
import '../widgets/admin_analytics_components.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key, required this.onOpenOrders});

  final VoidCallback onOpenOrders;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  bool _loading = true;
  String? _error;
  List<OrderRecord> _orders = const [];
  AdminTrendGranularity _ordersGranularity = AdminTrendGranularity.monthly;
  final List<int> _insightSegments = <int>[2, 2, 2];

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
      final orders = await _db.getAllOrders();
      if (!mounted) return;
      setState(() => _orders = orders);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load overview: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _statusCount(String status) {
    final s = status.toLowerCase();
    return _orders.where((o) => o.status.toLowerCase() == s).length;
  }

  double _ordersInRange(DateTime start, DateTime end) {
    return _orders.where((o) => !o.createdAt.isBefore(start) && o.createdAt.isBefore(end)).length.toDouble();
  }

  List<AdminSeriesPoint> get _dailyOrderPoints {
    final now = DateTime.now();
    final local = DateTime(now.year, now.month, now.day);
    final monday = local.subtract(Duration(days: local.weekday - DateTime.monday));
    final points = <AdminSeriesPoint>[];
    for (var i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      points.add(AdminSeriesPoint(x: day, y: _ordersInRange(day, day.add(const Duration(days: 1)))));
    }
    return points;
  }

  List<AdminSeriesPoint> get _monthlyOrderPoints {
    final now = DateTime.now();
    final points = <AdminSeriesPoint>[];
    for (var i = 11; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final next = DateTime(month.year, month.month + 1, 1);
      points.add(AdminSeriesPoint(x: month, y: _ordersInRange(month, next)));
    }
    return points;
  }

  List<AdminSeriesPoint> get _yearlyOrderPoints {
    final y0 = DateTime.now().year;
    final points = <AdminSeriesPoint>[];
    for (var i = 11; i >= 0; i--) {
      final y = y0 - i;
      points.add(
        AdminSeriesPoint(
          x: DateTime(y, 7, 1),
          y: _ordersInRange(DateTime(y, 1, 1), DateTime(y + 1, 1, 1)),
        ),
      );
    }
    return points;
  }

  List<AdminSeriesPoint> get _orderTrendPoints {
    switch (_ordersGranularity) {
      case AdminTrendGranularity.daily:
        return _dailyOrderPoints;
      case AdminTrendGranularity.monthly:
        return _monthlyOrderPoints;
      case AdminTrendGranularity.yearly:
        return _yearlyOrderPoints;
    }
  }

  List<AdminKpiItem> get _pipelineKpis {
    return [
      AdminKpiItem(
        title: 'Pending',
        value: AdminFormatters.count(_statusCount('pending')),
        subtitle: 'Awaiting confirmation or payment',
        accent: AdminAnalyticsColors.warning,
        icon: Icons.pending_actions_outlined,
      ),
      AdminKpiItem(
        title: 'Cancelled',
        value: AdminFormatters.count(_statusCount('cancelled')),
        subtitle: 'Requires follow-up or inventory review',
        accent: AdminAnalyticsColors.negative,
        icon: Icons.cancel_outlined,
      ),
      AdminKpiItem(
        title: 'Shipped',
        value: AdminFormatters.count(_statusCount('shipped')),
        subtitle: 'In transit to customers',
        accent: AdminAnalyticsColors.primary,
        icon: Icons.local_shipping_outlined,
      ),
      AdminKpiItem(
        title: 'Delivered',
        value: AdminFormatters.count(_statusCount('delivered')),
        subtitle: 'Completed deliveries',
        accent: AdminAnalyticsColors.positive,
        icon: Icons.inventory_2_outlined,
      ),
    ];
  }

  List<AdminInsightColumn> get _bottomInsights {
    final pendingByUser = <String, int>{};
    final cancelledByUser = <String, int>{};
    final pendingRequestsByUser = <String, int>{};
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - DateTime.monday));
    final monthStart = DateTime(now.year, now.month, 1);

    for (final o in _orders) {
      final status = o.status.toLowerCase();
      final includePending = _matchesSegmentWindow(o.createdAt, _insightSegments[0], weekStart, monthStart);
      final includeCancelled = _matchesSegmentWindow(o.createdAt, _insightSegments[1], weekStart, monthStart);
      final includeRequests = _matchesSegmentWindow(o.createdAt, _insightSegments[2], weekStart, monthStart);
      final name = o.userName.trim().isEmpty ? 'Unknown user' : o.userName.trim();
      if (status == 'pending' && includePending) pendingByUser[name] = (pendingByUser[name] ?? 0) + 1;
      if (status == 'cancelled' && includeCancelled) cancelledByUser[name] = (cancelledByUser[name] ?? 0) + 1;
      if (status == 'pending' && includeRequests) pendingRequestsByUser[name] = (pendingRequestsByUser[name] ?? 0) + 1;
    }

    List<AdminInsightEntry> entriesFromCounts(Map<String, int> source) {
      final rows = source.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final top = rows.take(6).toList(growable: false);
      final max = top.isEmpty ? 1 : top.first.value;
      return top
          .map(
            (e) => AdminInsightEntry(
              label: e.key,
              value: AdminFormatters.count(e.value),
              progress: max <= 0 ? 0 : e.value / max,
            ),
          )
          .toList(growable: false);
    }

    return [
      AdminInsightColumn(
        title: 'Pending Orders by Customers',
        entries: entriesFromCounts(pendingByUser),
        segmentLabels: const ['This week', 'This month', 'All'],
        activeSegment: _insightSegments[0],
        onSegmentSelected: (i) => setState(() => _insightSegments[0] = i),
        onOpenPanel: widget.onOpenOrders,
        openLabel: '',
      ),
      AdminInsightColumn(
        title: 'Cancelled Orders by Customers',
        entries: entriesFromCounts(cancelledByUser),
        segmentLabels: const ['This week', 'This month', 'All'],
        activeSegment: _insightSegments[1],
        onSegmentSelected: (i) => setState(() => _insightSegments[1] = i),
        onOpenPanel: widget.onOpenOrders,
        openLabel: '',
      ),
      AdminInsightColumn(
        title: 'Pending Requests by Customers',
        entries: entriesFromCounts(pendingRequestsByUser),
        segmentLabels: const ['This week', 'This month', 'All'],
        activeSegment: _insightSegments[2],
        onSegmentSelected: (i) => setState(() => _insightSegments[2] = i),
        onOpenPanel: widget.onOpenOrders,
        openLabel: '',
      ),
    ];
  }

  bool _matchesSegmentWindow(DateTime createdAt, int segment, DateTime weekStart, DateTime monthStart) {
    if (segment == 0) {
      return !createdAt.isBefore(weekStart);
    }
    if (segment == 1) {
      return !createdAt.isBefore(monthStart);
    }
    return true;
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

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminKpiStripRow(items: _pipelineKpis),
            const SizedBox(height: 20),
            AdminUnifiedTrendChartCard(
              title: 'Order Volume Trend',
              subtitle: _ordersGranularity == AdminTrendGranularity.daily
                  ? 'Number of orders by day (Mon-Sun).'
                  : _ordersGranularity == AdminTrendGranularity.monthly
                      ? 'Number of orders for each of the last 12 months.'
                      : 'Number of orders for each of the last 12 years.',
              seriesLabel: 'Orders',
              points: _orderTrendPoints,
              granularity: _ordersGranularity,
              onGranularityChanged: (g) => setState(() => _ordersGranularity = g),
              valueFormatter: (v) => AdminFormatters.decimal(v, digits: 0),
            ),
            const SizedBox(height: 20),
            AdminInsightPanelRow(columns: _bottomInsights),
          ],
        ),
      ),
    );
  }
}
