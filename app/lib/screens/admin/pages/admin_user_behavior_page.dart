import 'package:flutter/material.dart';

import '../../../models/order_record.dart';
import '../../../models/review.dart';
import '../../../models/user.dart';
import '../../../services/mysql_database_service.dart';
import '../../../utils/admin_formatters.dart';
import '../widgets/admin_analytics_components.dart';

/// **User behavior** tab: audience scale, engagement, spend, and qualitative signals (reviews).
/// Keeps financial deep-dives in Sales Reports and operational pipeline in Overview.
class AdminUserBehaviorPage extends StatefulWidget {
  const AdminUserBehaviorPage({super.key, this.onOpenReviews});

  final VoidCallback? onOpenReviews;

  @override
  State<AdminUserBehaviorPage> createState() => _AdminUserBehaviorPageState();
}

class _AdminUserBehaviorPageState extends State<AdminUserBehaviorPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  bool _loading = true;
  String? _error;
  List<User> _users = const [];
  List<OrderRecord> _orders = const [];
  List<Review> _reviews = const [];
  AdminTrendGranularity _usersGranularity = AdminTrendGranularity.monthly;
  final List<int> _insightSegments = <int>[0, 0, 0];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _db.getAllUsers(),
        _db.getAllOrders(),
        _db.getAllReviews(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<User>;
        _orders = results[1] as List<OrderRecord>;
        _reviews = results[2] as List<Review>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load user behavior: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, User> get _userById => {for (final u in _users) u.id: u};

  List<AdminKpiItem> _buildKpis() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final thirtyAgo = now.subtract(const Duration(days: 30));

    final newThisMonth = _users.where((u) => !u.createdAt.isBefore(monthStart)).length;

    final activeIds = <String>{};
    for (final o in _orders) {
      if (o.createdAt.isAfter(thirtyAgo)) activeIds.add(o.userId);
    }
    for (final u in _users) {
      if (u.lastLoginAt.isAfter(thirtyAgo)) activeIds.add(u.id);
    }
    final reviewers = _reviews.map((r) => r.userId).toSet().length;

    return [
      AdminKpiItem(
        title: 'Total users',
        value: AdminFormatters.count(_users.length),
        subtitle: 'Registered accounts',
        accent: AdminAnalyticsColors.primary,
        icon: Icons.group_outlined,
      ),
      AdminKpiItem(
        title: 'New users',
        value: AdminFormatters.count(newThisMonth),
        subtitle: 'Signed up this calendar month',
        accent: AdminAnalyticsColors.secondary,
        icon: Icons.person_add_alt_1_outlined,
      ),
      AdminKpiItem(
        title: 'Current users',
        value: AdminFormatters.count(activeIds.length),
        subtitle: 'Ordered or signed in within 30 days',
        accent: AdminAnalyticsColors.positive,
        icon: Icons.person_pin_circle_outlined,
      ),
      AdminKpiItem(
        title: 'Reviewers',
        value: AdminFormatters.count(reviewers),
        subtitle: 'Users who submitted at least one review',
        accent: AdminAnalyticsColors.warning,
        icon: Icons.rate_review_outlined,
      ),
    ];
  }

  double _usersInRange(DateTime start, DateTime end) {
    return _users.where((u) => !u.createdAt.isBefore(start) && u.createdAt.isBefore(end)).length.toDouble();
  }

  List<AdminSeriesPoint> get _dailyUserPoints {
    final now = DateTime.now();
    final local = DateTime(now.year, now.month, now.day);
    final monday = local.subtract(Duration(days: local.weekday - DateTime.monday));
    final points = <AdminSeriesPoint>[];
    for (var i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      points.add(AdminSeriesPoint(x: day, y: _usersInRange(day, day.add(const Duration(days: 1)))));
    }
    return points;
  }

  List<AdminSeriesPoint> get _monthlyUserPoints {
    final now = DateTime.now();
    final points = <AdminSeriesPoint>[];
    for (var i = 11; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final next = DateTime(month.year, month.month + 1, 1);
      points.add(AdminSeriesPoint(x: month, y: _usersInRange(month, next)));
    }
    return points;
  }

  List<AdminSeriesPoint> get _yearlyUserPoints {
    final y0 = DateTime.now().year;
    final points = <AdminSeriesPoint>[];
    for (var i = 11; i >= 0; i--) {
      final y = y0 - i;
      points.add(AdminSeriesPoint(x: DateTime(y, 7, 1), y: _usersInRange(DateTime(y, 1, 1), DateTime(y + 1, 1, 1))));
    }
    return points;
  }

  List<AdminSeriesPoint> get _userTrendPoints {
    switch (_usersGranularity) {
      case AdminTrendGranularity.daily:
        return _dailyUserPoints;
      case AdminTrendGranularity.monthly:
        return _monthlyUserPoints;
      case AdminTrendGranularity.yearly:
        return _yearlyUserPoints;
    }
  }

  List<_UserSpendRow> _topSpenders({int limit = 12}) {
    final totals = <String, double>{};
    for (final o in _orders) {
      if (o.status.toLowerCase() == 'cancelled') continue;
      totals[o.userId] = (totals[o.userId] ?? 0) + o.totalAmount;
    }
    final rows = totals.entries.map((e) {
      final u = _userById[e.key];
      final name = u?.fullName.isNotEmpty == true ? u!.fullName : _nameFromOrders(e.key);
      return _UserSpendRow(userId: e.key, displayName: name, email: u?.email ?? '', total: e.value);
    }).toList();
    rows.sort((a, b) => b.total.compareTo(a.total));
    return rows.take(limit).toList();
  }

  /// Fallback label when user record is missing but orders carry a name.
  String _nameFromOrders(String userId) {
    try {
      return _orders.firstWhere((o) => o.userId == userId).userName;
    } catch (_) {
      return userId;
    }
  }

  List<Review> get _recentReviews {
    final list = List<Review>.from(_reviews)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(10).toList();
  }

  List<AdminInsightColumn> _buildBottomInsightColumns(List<_UserSpendRow> spenders) {
    final now = DateTime.now();
    final since30 = now.subtract(const Duration(days: 30));
    final since90 = now.subtract(const Duration(days: 90));
    List<OrderRecord> spendOrders = _orders.where((o) => o.status.toLowerCase() != 'cancelled').toList(growable: false);
    if (_insightSegments[0] == 1) {
      spendOrders = spendOrders.where((o) => !o.createdAt.isBefore(since90)).toList(growable: false);
    } else if (_insightSegments[0] == 2) {
      spendOrders = spendOrders.where((o) => !o.createdAt.isBefore(since30)).toList(growable: false);
    }
    final spendTotals = <String, double>{};
    for (final o in spendOrders) {
      spendTotals[o.userId] = (spendTotals[o.userId] ?? 0) + o.totalAmount;
    }
    final spendRows = spendTotals.entries.map((e) {
      final u = _userById[e.key];
      final name = u?.fullName.isNotEmpty == true ? u!.fullName : _nameFromOrders(e.key);
      return _UserSpendRow(userId: e.key, displayName: name, email: u?.email ?? '', total: e.value);
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final maxSpend = spendRows.isEmpty ? 1.0 : spendRows.first.total;
    final topSpenders = spendRows
        .take(6)
        .map(
          (s) => AdminInsightEntry(
            label: s.displayName,
            value: AdminFormatters.currency(s.total),
            progress: maxSpend <= 0 ? 0 : s.total / maxSpend,
          ),
        )
        .toList(growable: false);

    final reviewSource = _insightSegments[1] == 2
        ? _recentReviews
        : _reviews;
    final reviewByUser = <String, int>{};
    for (final r in reviewSource) {
      final name = r.userName.trim().isEmpty ? 'Unknown user' : r.userName.trim();
      reviewByUser[name] = (reviewByUser[name] ?? 0) + 1;
    }
    final reviewRows = reviewByUser.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final reviewMax = reviewRows.isEmpty ? 1 : reviewRows.first.value;
    final topReviewers = reviewRows
        .take(6)
        .map(
          (e) => AdminInsightEntry(
            label: e.key,
            value: AdminFormatters.count(e.value),
            progress: reviewMax <= 0 ? 0 : e.value / reviewMax,
          ),
        )
        .toList(growable: false);

    final statusSource = _insightSegments[2] == 1
        ? _reviews.where((r) => r.status.toLowerCase() == 'published').toList(growable: false)
        : _insightSegments[2] == 2
            ? _reviews.where((r) => r.status.toLowerCase() == 'pending').toList(growable: false)
            : _reviews;
    final statusCounts = <String, int>{};
    for (final r in statusSource) {
      final status = r.status.trim().isEmpty ? 'unknown' : r.status.trim().toLowerCase();
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    }
    final statusRows = statusCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final statusMax = statusRows.isEmpty ? 1 : statusRows.first.value;
    final statuses = statusRows
        .take(6)
        .map(
          (e) => AdminInsightEntry(
            label: e.key,
            value: AdminFormatters.count(e.value),
            progress: statusMax <= 0 ? 0 : e.value / statusMax,
          ),
        )
        .toList(growable: false);

    return [
      AdminInsightColumn(
        title: 'Paid Amount by User',
        segmentLabels: const ['Lifetime', '90 days', '30 days'],
        activeSegment: _insightSegments[0],
        entries: topSpenders,
        onSegmentSelected: (i) => setState(() => _insightSegments[0] = i),
        onOpenPanel: widget.onOpenReviews,
        openLabel: '',
      ),
      AdminInsightColumn(
        title: 'Top Reviewers',
        segmentLabels: const ['Count', 'Rating', 'Recent'],
        activeSegment: _insightSegments[1],
        entries: topReviewers,
        onSegmentSelected: (i) => setState(() => _insightSegments[1] = i),
        onOpenPanel: widget.onOpenReviews,
        openLabel: '',
      ),
      AdminInsightColumn(
        title: 'Review Statuses',
        segmentLabels: const ['All', 'Published', 'Pending'],
        activeSegment: _insightSegments[2],
        entries: statuses,
        onSegmentSelected: (i) => setState(() => _insightSegments[2] = i),
        onOpenPanel: widget.onOpenReviews,
        openLabel: '',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }

    final spenders = _topSpenders();
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminKpiStripRow(items: _buildKpis()),
            const SizedBox(height: 20),
            AdminUnifiedTrendChartCard(
              title: 'User Growth Trend',
              subtitle: _usersGranularity == AdminTrendGranularity.daily
                  ? 'Number of newly registered users by day (Mon-Sun).'
                  : _usersGranularity == AdminTrendGranularity.monthly
                      ? 'Number of newly registered users for each of the last 12 months.'
                      : 'Number of newly registered users for each of the last 12 years.',
              seriesLabel: 'Users',
              points: _userTrendPoints,
              granularity: _usersGranularity,
              onGranularityChanged: (g) => setState(() => _usersGranularity = g),
              valueFormatter: (v) => AdminFormatters.decimal(v, digits: 0),
            ),
            const SizedBox(height: 24),
            AdminInsightPanelRow(columns: _buildBottomInsightColumns(spenders)),
          ],
        ),
      ),
    );
  }
}

class _UserSpendRow {
  const _UserSpendRow({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.total,
  });

  final String userId;
  final String displayName;
  final String email;
  final double total;
}
