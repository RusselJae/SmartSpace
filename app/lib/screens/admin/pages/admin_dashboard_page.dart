import 'package:flutter/material.dart';

import '../../../models/order_record.dart';
import '../../../models/product.dart';
import '../../../models/review.dart';
import '../../../models/user.dart';
import '../../../models/made_to_order_request.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_summary_card.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key, required this.onOpenReviews, required this.onOpenOrders});

  final VoidCallback onOpenReviews;
  final VoidCallback onOpenOrders;

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
  List<MadeToOrderRequest> _mtoRequests = const [];

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
        _db.getMadeToOrderRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        // Store results (products stored but not currently used in UI)
        _products = results[0] as List<Product>;
        _orders = results[1] as List<OrderRecord>;
        _reviews = results[2] as List<Review>;
        _users = results[3] as List<User>;
        _mtoRequests = results[4] as List<MadeToOrderRequest>;
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroBanner(onRefresh: _loadData),
                const SizedBox(height: 24),
                _SummaryGrid(metrics: metrics),
                const SizedBox(height: 24),
                _RecentOverviewPanel(
                  users: _users,
                  productsById: {for (final p in _products) p.id: p},
                  orders: _orders,
                  mtoRequests: _mtoRequests,
                ),
                const SizedBox(height: 24),
                _OrdersSection(
                  orders: _recentOrders,
                  onRefresh: _loadData,
                  onViewAll: widget.onOpenOrders,
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

  /// Builds summary metrics dynamically based on current database data.
  /// All calculations are done from actual loaded data, making the dashboard fully dynamic.
  List<AdminSummaryMetric> _buildSummaryMetrics() {
    // Calculate total revenue from all orders
    final double totalRevenue = _orders.fold(0.0, (sum, order) => sum + order.totalAmount);
    
    // Calculate monthly revenue (current month)
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final double monthlyRevenue = _orders
        .where((order) => order.createdAt.isAfter(currentMonthStart.subtract(const Duration(milliseconds: 1))) ||
                         order.createdAt.isAtSameMomentAs(currentMonthStart))
        .fold(0.0, (sum, order) => sum + order.totalAmount);
    
    // Calculate active users (users with orders in the last 30 days or recent login)
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final activeUserIds = _orders
        .where((order) => order.createdAt.isAfter(thirtyDaysAgo))
        .map((order) => order.userId)
        .toSet();
    final recentLoginUsers = _users
        .where((user) => user.lastLoginAt.isAfter(thirtyDaysAgo))
        .map((user) => user.id)
        .toSet();
    final int activeUsersCount = (activeUserIds.union(recentLoginUsers)).length;
    
    // Calculate total orders per month (excluding cancelled)
    final int monthlyOrders = _orders
        .where((order) => 
            (order.createdAt.isAfter(currentMonthStart.subtract(const Duration(milliseconds: 1))) ||
             order.createdAt.isAtSameMomentAs(currentMonthStart)) &&
            order.status.toLowerCase() != 'cancelled')
        .length;
    
    // Calculate total orders (excluding cancelled) for comparison
    final int totalValidOrders = _orders
        .where((order) => 
            order.status.toLowerCase() != 'cancelled')
        .length;
    
    // Calculate total products count
    final int totalProducts = _products.length;
    
    // Calculate low stock products (inventory 1..3).
    // Threshold requested: "at least 3 lower" → we treat <= 3 as low stock.
    const int lowStockThreshold = 3;
    final int lowStockProducts =
        _products.where((p) => p.inventoryQty > 0 && p.inventoryQty <= lowStockThreshold).length;
    
    return [
      AdminSummaryMetric(
        title: 'Total Revenue',
        value: '₱${totalRevenue.toStringAsFixed(1)}',
        deltaLabel: '₱${monthlyRevenue.toStringAsFixed(1)} this month',
        icon: Icons.payments_rounded,
        // Distinct grid colors to make each card instantly recognizable.
        background: const Color(0xFF1D4ED8), // Blue
      ),
      AdminSummaryMetric(
        title: 'Active users',
        value: activeUsersCount.toString(),
        deltaLabel: '${_users.length} total users',
        icon: Icons.group_outlined,
        background: const Color(0xFF059669), // Emerald
      ),
      AdminSummaryMetric(
        title: 'Orders this month',
        value: monthlyOrders.toString(),
        deltaLabel: '$totalValidOrders total valid orders',
        icon: Icons.shopping_bag_outlined,
        background: const Color(0xFFF97316), // Orange
      ),
      AdminSummaryMetric(
        title: 'Products',
        value: totalProducts.toString(),
        deltaLabel: lowStockProducts > 0 ? '$lowStockProducts low stock' : 'All in stock',
        icon: Icons.inventory_2_outlined,
        background: const Color(0xFF7C3AED), // Purple
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
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your store efficiently',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: onRefresh,
                tooltip: 'Refresh',
              ),
              IconButton(
                icon: const Icon(Icons.tune),
                onPressed: () {},
                tooltip: 'Filters',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact sales overview card on the right of the hero area
/// Shows monthly sales data with a bar chart visualization
/// Orders section with simplified design
class _OrdersSection extends StatelessWidget {
  const _OrdersSection({
    required this.orders,
    required this.onRefresh,
    required this.onViewAll,
  });

  final List<OrderRecord> orders;
  final Future<void> Function() onRefresh;
  final VoidCallback onViewAll;

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
                  'Recent Orders',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onViewAll,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('View All'),
                ),
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
            if (orders.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'No orders yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ),
              )
            else
              ...orders.take(5).map(
                    (order) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _OrderRow(order: order),
                    ),
                  ),
          ],
        ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${order.id.length >= 8 ? order.id.substring(0, 8) : order.id}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  order.userName.isEmpty ? 'Guest user' : order.userName,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${order.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(order.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.status,
                    style: TextStyle(
                      fontSize: 11,
                      color: _getStatusColor(order.status),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
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
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.3,
          ),
          itemCount: metrics.length,
          itemBuilder: (context, index) {
            final metric = metrics[index];
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
                    Text(metric.title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700])),
                    const SizedBox(height: 6),
                    Text(metric.value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(metric.deltaLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
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

class _RecentOverviewPanel extends StatelessWidget {
  const _RecentOverviewPanel({
    required this.users,
    required this.productsById,
    required this.orders,
    required this.mtoRequests,
  });

  final List<User> users;
  final Map<String, Product> productsById;
  final List<OrderRecord> orders;
  final List<MadeToOrderRequest> mtoRequests;

  @override
  Widget build(BuildContext context) {
    final recentUsers = List<User>.from(users)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recentOrders = List<OrderRecord>.from(orders)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recentMtoUnquoted = mtoRequests
        .where((r) => r.quotedTotal == null && r.status.toLowerCase() != 'declined')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;
        final children = <Widget>[
          Expanded(
            child: _RecentListCard<User>(
              title: 'Recently Made Accounts',
              items: recentUsers.take(5).toList(),
              emptyText: 'No recent accounts.',
              lineBuilder: (u) => u.fullName,
              sublineBuilder: (u) => u.email,
              trailingBuilder: (u) => _dateLabel(u.createdAt),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _RecentListCard<OrderRecord>(
              title: 'Recently Bought Product',
              items: recentOrders.take(5).toList(),
              emptyText: 'No recent product purchases.',
              lineBuilder: (o) {
                final productId = o.productIds.isEmpty ? '' : o.productIds.first;
                return productsById[productId]?.name ?? 'Unknown product';
              },
              sublineBuilder: (o) => o.userName.isEmpty ? 'Guest user' : o.userName,
              trailingBuilder: (o) => _dateLabel(o.createdAt),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _RecentListCard<MadeToOrderRequest>(
              title: 'Recently Made-to-Order (Unquoted)',
              items: recentMtoUnquoted.take(5).toList(),
              emptyText: 'No unquoted made-to-order requests.',
              lineBuilder: (r) => r.itemName,
              sublineBuilder: (r) => r.userName,
              trailingBuilder: (r) => _dateLabel(r.createdAt),
            ),
          ),
        ];
        if (isWide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
        }
        return Column(
          children: [
            _RecentListCard<User>(
              title: 'Recently Made Accounts',
              items: recentUsers.take(5).toList(),
              emptyText: 'No recent accounts.',
              lineBuilder: (u) => u.fullName,
              sublineBuilder: (u) => u.email,
              trailingBuilder: (u) => _dateLabel(u.createdAt),
            ),
            const SizedBox(height: 12),
            _RecentListCard<OrderRecord>(
              title: 'Recently Bought Product',
              items: recentOrders.take(5).toList(),
              emptyText: 'No recent product purchases.',
              lineBuilder: (o) {
                final productId = o.productIds.isEmpty ? '' : o.productIds.first;
                return productsById[productId]?.name ?? 'Unknown product';
              },
              sublineBuilder: (o) => o.userName.isEmpty ? 'Guest user' : o.userName,
              trailingBuilder: (o) => _dateLabel(o.createdAt),
            ),
            const SizedBox(height: 12),
            _RecentListCard<MadeToOrderRequest>(
              title: 'Recently Made-to-Order (Unquoted)',
              items: recentMtoUnquoted.take(5).toList(),
              emptyText: 'No unquoted made-to-order requests.',
              lineBuilder: (r) => r.itemName,
              sublineBuilder: (r) => r.userName,
              trailingBuilder: (r) => _dateLabel(r.createdAt),
            ),
          ],
        );
      },
    );
  }

  static String _dateLabel(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class _RecentListCard<T> extends StatelessWidget {
  const _RecentListCard({
    required this.title,
    required this.items,
    required this.emptyText,
    required this.lineBuilder,
    required this.sublineBuilder,
    required this.trailingBuilder,
  });

  final String title;
  final List<T> items;
  final String emptyText;
  final String Function(T) lineBuilder;
  final String Function(T) sublineBuilder;
  final String Function(T) trailingBuilder;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (items.isEmpty)
              Text(emptyText, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]))
            else
              ...items.map(
                (item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(lineBuilder(item), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(sublineBuilder(item), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(trailingBuilder(item), style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewHealthCard extends StatelessWidget {
  const _ReviewHealthCard({required this.reviews, required this.onOpenReviews});

  final List<Review> reviews;
  final VoidCallback onOpenReviews;

  /// Get the latest 2 reviews sorted by creation date (newest first)
  List<Review> get _latestReviews {
    final sorted = List<Review>.from(reviews);
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(2).toList();
  }

  @override
  Widget build(BuildContext context) {
    final latestReviews = _latestReviews;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Review Moderation',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                TextButton.icon(
                  onPressed: onOpenReviews,
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (latestReviews.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'No reviews yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ),
              )
            else
              ...latestReviews.map((review) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _LatestReviewRow(review: review),
                  )),
          ],
        ),
      ),
    );
  }
}

/// Widget displaying a single latest review row
class _LatestReviewRow extends StatelessWidget {
  const _LatestReviewRow({required this.review});

  final Review review;

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'published':
        return Colors.green;
      case 'flagged':
        return Colors.red;
      case 'rejected':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stars = List.generate(
      5,
      (index) => Icon(
        index < review.rating ? Icons.star : Icons.star_border,
        size: 14,
        color: Colors.amber,
      ),
    );
    final statusColor = _getStatusColor(review.status);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  review.productName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    ...stars,
                    const SizedBox(width: 4),
                    Text(
                      '${review.rating}/5',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'by ${review.userName.isEmpty ? 'Anonymous' : review.userName}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                if (review.content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    review.content,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              review.status[0].toUpperCase() + review.status.substring(1),
              style: TextStyle(
                fontSize: 11,
                color: statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
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

