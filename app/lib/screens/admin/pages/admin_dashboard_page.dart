import 'package:flutter/material.dart';

import '../../../models/order_record.dart';
import '../../../models/product.dart';
import '../../../models/review.dart';
import '../../../models/user.dart';
import '../../../services/mysql_database_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_summary_card.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key, required this.onOpenReviews});

  final VoidCallback onOpenReviews;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  bool _loading = true;
  String? _error;

  // Stored for future inventory analytics; currently unused in the dashboard cards.
  // ignore: unused_field
  List<Product> _products = const [];
  List<OrderRecord> _orders = const [];
  List<Review> _reviews = const [];
  List<User> _users = const [];

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
      final results = await Future.wait([
        _db.getAllProducts(),
        _db.getAllOrders(),
        _db.getAllReviews(),
        _db.getAllUsers(),
      ]);
      if (!mounted) return;
      setState(() {
        // Store results (products stored but not currently used in UI)
        _products = results[0] as List<Product>;
        _orders = results[1] as List<OrderRecord>;
        _reviews = results[2] as List<Review>;
        _users = results[3] as List<User>;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load dashboard: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
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

    final List<AdminSummaryMetric> metrics = _buildSummaryMetrics();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool wide = constraints.maxWidth > 1000;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _HeroBanner(onRefresh: _loadData),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 2,
                        child: _SalesOverviewCard(metrics: metrics),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroBanner(onRefresh: _loadData),
                      const SizedBox(height: 20),
                      _SalesOverviewCard(metrics: metrics),
                    ],
                  ),
                const SizedBox(height: 24),
                _SummaryGrid(metrics: metrics),
                const SizedBox(height: 24),
                _OrdersSection(
                  orders: _recentOrders,
                  onRefresh: _loadData,
                ),
                const SizedBox(height: 24),
                _ReviewHealthCard(reviews: _reviews, onOpenReviews: widget.onOpenReviews),
              ],
            );
          },
        ),
      ),
    );
  }

  List<AdminSummaryMetric> _buildSummaryMetrics() {
    final double revenue = _orders.fold(0, (sum, order) => sum + order.totalAmount);
    final int pendingReviews = _reviews.where((review) => review.status != 'published').length;
    final double avgTicket = _orders.isEmpty ? 0 : revenue / _orders.length;
    return [
      AdminSummaryMetric(
        title: 'Revenue',
        value: '₱${revenue.toStringAsFixed(1)}',
        deltaLabel: '${_orders.length} orders',
        icon: Icons.attach_money_rounded,
        background: AdminPalette.brown,
      ),
      AdminSummaryMetric(
        title: 'Active users',
        value: _users.length.toString(),
        deltaLabel: 'Top regions: US, SG',
        icon: Icons.group_outlined,
        background: AdminPalette.accent,
      ),
      AdminSummaryMetric(
        title: 'Avg ticket',
        value: '₱${avgTicket.toStringAsFixed(2)}',
        deltaLabel: 'per order',
        icon: Icons.shopping_basket_outlined,
        background: AdminPalette.brown,
      ),
      AdminSummaryMetric(
        title: 'Pending reviews',
        value: pendingReviews.toString(),
        deltaLabel: 'Need moderation',
        icon: Icons.rate_review_outlined,
        background: AdminPalette.clay,
      ),
    ];
  }

  List<OrderRecord> get _recentOrders {
    final List<OrderRecord> sorted = List.of(_orders);
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(5).toList();
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fulfilment performance',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Track catalog health, approve reviews, and keep orders flowing — all with the same warm palette.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[700]),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.tonalIcon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.tune),
                label: const Text('Filters'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact sales overview card on the right of the hero area, similar to the
/// "Sales Overview" block in the provided template.
class _SalesOverviewCard extends StatelessWidget {
  const _SalesOverviewCard({required this.metrics});

  final List<AdminSummaryMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Sales overview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              metrics.isNotEmpty ? metrics.first.value : '₱0.0',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _MiniBarChart(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBarChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bars = [40.0, 65.0, 30.0, 80.0, 55.0, 70.0, 48.0];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final barWidth = (width - (bars.length - 1) * 8) / bars.length;
        return SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final value in bars) ...[
                Container(
                  width: barWidth,
                  height: value + 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF111827), Color(0xFF4B5563)],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
                if (value != bars.last) const SizedBox(width: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Orders section styled closer to the template: tab-like status filters above
/// a compact list of recent orders.
class _OrdersSection extends StatelessWidget {
  const _OrdersSection({
    required this.orders,
    required this.onRefresh,
  });

  final List<OrderRecord> orders;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Orders',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    orders.length.toString(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: () {
                    onRefresh();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: const [
                  _OrdersFilterChip(label: 'Pending', count: 0, active: false),
                  SizedBox(width: 8),
                  _OrdersFilterChip(label: 'Responded', count: 0, active: false),
                  SizedBox(width: 8),
                  _OrdersFilterChip(label: 'Assigned', count: 0, active: true),
                  SizedBox(width: 8),
                  _OrdersFilterChip(label: 'Completed', count: 0, active: false),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (orders.isEmpty)
              const Text('Orders will appear here once customers start checking out.')
            else
              Column(
                children: orders
                    .map(
                      (order) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _OrderRow(order: order),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrdersFilterChip extends StatelessWidget {
  const _OrdersFilterChip({
    required this.label,
    required this.count,
    required this.active,
  });

  final String label;
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? Colors.black : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.black,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: active ? Colors.white12 : Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: active ? Colors.white : Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final OrderRecord order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '#${order.id.length >= 8 ? order.id.substring(0, 8) : order.id}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(order.userName.isEmpty ? 'Guest user' : order.userName),
          ),
          Expanded(
            flex: 3,
            child: Text(order.shippingAddress['city']?.toString() ?? ''),
          ),
          Expanded(
            flex: 2,
            child: Text(
              order.createdAt.toLocal().toString().substring(0, 10),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('₱${order.totalAmount.toStringAsFixed(2)}'),
          ),
          const SizedBox(width: 8),
          Chip(
            label: Text(order.status),
            backgroundColor: Colors.green.withValues(alpha: 0.08),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () {},
            child: const Text('See more'),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.metrics});

  final List<AdminSummaryMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int columns = constraints.maxWidth > 1100 ? 4 : constraints.maxWidth > 720 ? 2 : 1;
        // Increased childAspectRatio to prevent overflow - cards are wider relative to height
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            // Increased from 2.7 to 3.2 to make cards wider and prevent bottom overflow
            childAspectRatio: 3.2,
          ),
          itemCount: metrics.length,
          itemBuilder: (context, index) => AdminSummaryCard(metric: metrics[index]),
        );
      },
    );
  }
}

class _ReviewHealthCard extends StatelessWidget {
  const _ReviewHealthCard({required this.reviews, required this.onOpenReviews});

  final List<Review> reviews;
  final VoidCallback onOpenReviews;

  @override
  Widget build(BuildContext context) {
    final int pending = reviews.where((review) => review.status == 'pending').length;
    final int flagged = reviews.where((review) => review.status == 'flagged').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review moderation',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ReviewStat(label: 'Pending approvals', value: pending.toString(), color: Colors.orange),
                _ReviewStat(label: 'Flagged entries', value: flagged.toString(), color: Colors.red),
                _ReviewStat(
                  label: 'Published',
                  value: (reviews.length - pending - flagged).toString(),
                  color: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onOpenReviews,
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Go to reviews'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewStat extends StatelessWidget {
  const _ReviewStat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color.shade700,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

