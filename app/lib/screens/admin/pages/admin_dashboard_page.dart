import 'package:flutter/material.dart';

import '../../../models/order_record.dart';
import '../../../models/product.dart';
import '../../../models/review.dart';
import '../../../models/user.dart';
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
                        child: _SalesOverviewCard(orders: _orders),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroBanner(onRefresh: _loadData),
                      const SizedBox(height: 20),
                      _SalesOverviewCard(orders: _orders),
                    ],
                  ),
                const SizedBox(height: 24),
                _SummaryGrid(metrics: metrics),
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
class _SalesOverviewCard extends StatelessWidget {
  const _SalesOverviewCard({required this.orders});

  final List<OrderRecord> orders;

  /// Calculate monthly sales for the current month
  double get _monthlySales {
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    
    return orders
        .where((order) => order.createdAt.isAfter(currentMonthStart) || 
                         order.createdAt.isAtSameMomentAs(currentMonthStart))
        .fold(0.0, (sum, order) => sum + order.totalAmount);
  }

  /// Get sales data for the last 6 months for the bar chart
  List<double> get _monthlySalesData {
    final now = DateTime.now();
    final List<double> monthlyData = [];
    
    // Calculate sales for each of the last 6 months
    for (int i = 5; i >= 0; i--) {
      final monthStart = DateTime(now.year, now.month - i, 1);
      final monthEnd = DateTime(now.year, now.month - i + 1, 1);
      
      final monthSales = orders
          .where((order) => 
              order.createdAt.isAfter(monthStart.subtract(const Duration(milliseconds: 1))) &&
              order.createdAt.isBefore(monthEnd))
          .fold(0.0, (sum, order) => sum + order.totalAmount);
      
      monthlyData.add(monthSales);
    }
    
    return monthlyData;
  }

  @override
  Widget build(BuildContext context) {
    final monthlySales = _monthlySales;
    final chartData = _monthlySalesData;
    final maxSales = chartData.isEmpty ? 1.0 : chartData.reduce((a, b) => a > b ? a : b);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Sales',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              '₱${monthlySales.toStringAsFixed(1)}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: _MiniBarChart(data: chartData, maxValue: maxSales),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mini bar chart widget that displays monthly sales data
/// Uses actual sales data from orders to visualize trends
class _MiniBarChart extends StatelessWidget {
  const _MiniBarChart({required this.data, required this.maxValue});

  final List<double> data;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    // If no data, show empty chart
    if (data.isEmpty || maxValue == 0) {
      return Center(
        child: Text(
          'No sales data',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final barWidth = (width - (data.length - 1) * 6) / data.length;
        final maxHeight = constraints.maxHeight;
        
        return SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < data.length; i++) ...[
                Container(
                  width: barWidth,
                  // Scale height based on max value, with minimum height of 4 for visibility
                  height: maxValue > 0 
                      ? (data[i] / maxValue * maxHeight).clamp(4.0, maxHeight)
                      : 4.0,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: const Color(0xFF8D6E63),
                  ),
                ),
                if (i < data.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        );
      },
    );
  }
}

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
        // For web-based admin panel, use a lower childAspectRatio to give cards more height
        // Lower ratio = taller cards (more vertical space)
        // Set to 1.75 to provide 2x the height for card content without overflow
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            // Decreased to 1.75 for web - gives cards 2x more height to fit content comfortably
            // This ratio makes cards approximately 1.75x wider than they are tall (much taller cards)
            childAspectRatio: 1.75,
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

