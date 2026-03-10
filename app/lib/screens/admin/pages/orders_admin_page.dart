import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/order_record.dart';
import '../../../services/mysql_database_service.dart';
import '../../../config/api_config.dart';
import '../widgets/admin_toolbar.dart';
import '../../../widgets/toast.dart';

/// Orders management page with search, filtering, and status updates.
/// Follows Apple HIG principles with clean layouts and smooth animations.
class OrdersAdminPage extends StatefulWidget {
  const OrdersAdminPage({super.key});

  @override
  State<OrdersAdminPage> createState() => _OrdersAdminPageState();
}

class _OrdersAdminPageState extends State<OrdersAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final TextEditingController _searchController = TextEditingController();
  final List<String> _statuses = const ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled', 'expired'];
  
  List<OrderRecord> _orders = [];
  Map<String, String> _productNames = {}; // Cache product names by ID
  bool _loading = true;
  String _filter = 'all';
  String _searchQuery = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Loads all orders from the database with error handling.
  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await _db.getAllOrders();
      // Fetch all products to get names
      final products = await _db.getAllProducts();
      final productNamesMap = <String, String>{};
      for (final product in products) {
        productNamesMap[product.id] = product.name;
      }
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _productNames = productNamesMap;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load orders: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Filters orders by status and search query for a responsive, fast UI.
  List<OrderRecord> get _filtered {
    var filtered = _filter == 'all' 
        ? _orders 
        : _orders.where((o) => o.status == _filter).toList();
    
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((order) {
        return order.id.toLowerCase().contains(_searchQuery) ||
               order.userName.toLowerCase().contains(_searchQuery) ||
               order.productIds.any((id) => id.toLowerCase().contains(_searchQuery));
      }).toList();
    }
    
    return filtered;
  }

  /// Shows order history dialog with cancelled and delivered orders
  void _showOrderHistory() {
    final cancelledOrders = _orders.where((o) => o.status == 'cancelled').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final deliveredOrders = _orders.where((o) => o.status == 'delivered').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order History',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Tabs for Cancelled and Delivered
              DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      labelColor: const Color(0xFF8D6E63),
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: const Color(0xFF8D6E63),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Cancelled'),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: CupertinoColors.systemRed.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${cancelledOrders.length}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.systemRed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Delivered'),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: CupertinoColors.systemGreen.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${deliveredOrders.length}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.systemGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Cancelled orders tab
                          cancelledOrders.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.cancel_outlined, size: 64, color: Colors.grey[400]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No cancelled orders',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          color: Colors.grey[600],
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: cancelledOrders.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final order = cancelledOrders[index];
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      title: Text(
                                        'Order #${order.id.length >= 8 ? order.id.substring(0, 8) : order.id}',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.black,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            'Customer: ${order.userName.isEmpty ? 'Guest' : order.userName}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Colors.grey[700],
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Date: ${order.createdAt.toLocal().toString().substring(0, 16)}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Total: ₱${order.totalAmount.toStringAsFixed(2)}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black,
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: CupertinoColors.systemRed.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Text(
                                          'Cancelled',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: CupertinoColors.systemRed,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        _showOrderDetails(order);
                                      },
                                    );
                                  },
                                ),
                          // Delivered orders tab
                          deliveredOrders.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No delivered orders',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          color: Colors.grey[600],
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: deliveredOrders.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final order = deliveredOrders[index];
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      title: Text(
                                        'Order #${order.id.length >= 8 ? order.id.substring(0, 8) : order.id}',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.black,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            'Customer: ${order.userName.isEmpty ? 'Guest' : order.userName}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Colors.grey[700],
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Date: ${order.createdAt.toLocal().toString().substring(0, 16)}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Total: ₱${order.totalAmount.toStringAsFixed(2)}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black,
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.systemGreen.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: CupertinoColors.systemGreen.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Text(
                                          'Delivered',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: CupertinoColors.systemGreen,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        _showOrderDetails(order);
                                      },
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Updates order status with a smooth animation and user feedback.
  Future<void> _updateStatus(OrderRecord order, String status) async {
    // Show confirmation dialog for order confirmation
    if (status == 'confirmed' && order.status != 'confirmed') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Confirm Order',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: Text(
            'Confirming this order will send an email notification to the customer. Continue?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Confirm',
                style: GoogleFonts.poppins(
                  color: CupertinoColors.systemBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
      
      if (confirmed != true) {
        return; // User cancelled
      }
    }
    
    try {
      await _db.updateOrderStatus(order.id, status);
      if (!mounted) return;
      
      String message = 'Order #${order.id.length >= 8 ? order.id.substring(0, 8) : order.id} updated to $status';
      if (status == 'confirmed') {
        message += '. Email notification sent to customer.';
      }
      
      Toast.success(context, message);
      
      await _loadOrders();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to update order: $e');
    }
  }

  /// Shows detailed order information in a centered modal dialog following Apple's
  /// modal presentation style.
  void _showOrderDetails(OrderRecord order) {
    showDialog(
      context: context,
      builder: (context) => _OrderDetailsDialog(
        order: order,
        productNames: _productNames,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToolbar(
          title: 'Orders',
          actions: const [],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search orders by ID, customer, or product...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8F8F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: CupertinoColors.systemBlue.withValues(alpha: 0.5), width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _showOrderHistory,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('History'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8D6E63),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: () {
                  Toast.info(context, 'Export functionality coming soon');
                },
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Export',
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadOrders,
                tooltip: 'Refresh orders',
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<String>(
            segments: [
              const ButtonSegment<String>(value: 'all', label: Text('All')),
              ..._statuses.map((status) => ButtonSegment<String>(
                    value: status,
                    label: Text(status[0].toUpperCase() + status.substring(1)),
                  )),
            ],
            selected: {_filter},
            onSelectionChanged: (Set<String> values) {
              setState(() => _filter = values.first);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            '${filtered.length} ${filtered.length == 1 ? 'order' : 'orders'}',
            style: GoogleFonts.poppins(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_bag_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty || _filter != 'all'
                                ? 'No orders match your filters'
                                : 'No orders yet',
                            style: GoogleFonts.poppins(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: CupertinoColors.separator.withValues(alpha: 0.1),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          _OrdersHeaderRow(onAnyTap: () {}),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: CupertinoColors.separator.withValues(alpha: 0.1),
                          ),
                          Expanded(
                            child: ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                thickness: 1,
                                indent: 16,
                                endIndent: 16,
                                color: CupertinoColors.separator.withValues(alpha: 0.1),
                              ),
                              itemBuilder: (context, index) {
                                final order = filtered[index];
                                return _OrdersTableRow(
                                  order: order,
                                  productNames: _productNames,
                                  onTap: () => _showOrderDetails(order),
                                  onStatusChanged: (value) => _updateStatus(order, value),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}

class _OrdersHeaderRow extends StatelessWidget {
  const _OrdersHeaderRow({required this.onAnyTap});

  final VoidCallback onAnyTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'Order ID',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Customer',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'City',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Date',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Total',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              'Status',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const SizedBox(width: 70),
        ],
      ),
    );
  }
}

class _OrdersTableRow extends StatelessWidget {
  const _OrdersTableRow({
    required this.order,
    required this.productNames,
    required this.onTap,
    required this.onStatusChanged,
  });

  final OrderRecord order;
  final Map<String, String> productNames;
  final VoidCallback onTap;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final dateStr = order.createdAt.toLocal().toString().substring(0, 10);
    return InkWell(
      onTap: onTap,
      hoverColor: CupertinoColors.systemGrey6.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                '#${order.id.length >= 8 ? order.id.substring(0, 8) : order.id}',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: CupertinoColors.label,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                order.userName.isEmpty ? 'Guest user' : order.userName,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: CupertinoColors.label,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    order.shippingAddress['city']?.toString() ?? '-',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: CupertinoColors.secondaryLabel,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (order.productIds.isNotEmpty)
                    Text(
                      '${order.productIds.length} ${order.productIds.length == 1 ? 'item' : 'items'}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: CupertinoColors.tertiaryLabel,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                dateStr,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '₱${order.totalAmount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _StatusPill(
                status: order.status,
                onChanged: onStatusChanged,
                isEditable: order.status != 'delivered' && order.status != 'cancelled',
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: const Size(70, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.3)),
                ),
                backgroundColor: Colors.transparent,
              ),
              child: Text(
                'View',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.systemBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
    required this.onChanged,
    this.isEditable = true,
  });

  final String status;
  final ValueChanged<String> onChanged;
  final bool isEditable; // Whether the status can be edited

  /// Returns a clean, light color palette for status indicators
  /// Following Apple HIG with subtle, approachable colors
  Color _statusColor(String value) {
    switch (value) {
      case 'pending':
        return Colors.yellow.shade700; // Yellow color for pending status
      case 'confirmed':
        return CupertinoColors.systemBlue;
      case 'shipped':
        return CupertinoColors.systemTeal;
      case 'delivered':
        return CupertinoColors.systemGreen;
      case 'cancelled':
        return CupertinoColors.systemRed;
      case 'expired':
        return CupertinoColors.systemGrey;
      default:
        return CupertinoColors.systemGrey;
    }
  }

  /// Icon per status for clearer affordance in the dropdown
  IconData _statusIcon(String value) {
    switch (value) {
      case 'pending':
        return Icons.hourglass_top_outlined;
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'shipped':
        return Icons.local_shipping_outlined;
      case 'delivered':
        return Icons.task_alt_outlined;
      case 'cancelled':
        return Icons.cancel_outlined;
      case 'expired':
        return Icons.schedule_send_outlined;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final isDeliveredOrCancelled = status == 'delivered' || status == 'cancelled';
    
    // For delivered and cancelled orders, show non-editable status pill
    if (!isEditable || isDeliveredOrCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                status[0].toUpperCase() + status.substring(1),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Only show dropdown icon if editable and not delivered/cancelled
            if (isEditable && !isDeliveredOrCancelled) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.expand_more,
                size: 16,
                color: color.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      );
    }
    
    // For editable orders, show dropdown menu
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final s in const ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled', 'expired'])
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                Icon(_statusIcon(s), size: 18, color: _statusColor(s)),
                const SizedBox(width: 10),
                Text(
                  s[0].toUpperCase() + s.substring(1),
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                status[0].toUpperCase() + status.substring(1),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more,
              size: 16,
              color: color.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered dialog showing detailed order information in Apple's modal style.
class _OrderDetailsDialog extends StatelessWidget {
  const _OrderDetailsDialog({
    required this.order,
    required this.productNames,
  });

  final OrderRecord order;
  final Map<String, String> productNames;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Row(
                children: [
                  Text(
                    'Order Details',
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    _DetailRow(label: 'Order ID', value: order.id),
                    _DetailRow(label: 'Customer', value: order.userName.isNotEmpty ? order.userName : 'Guest'),
                    _DetailRow(label: 'Status', value: order.status[0].toUpperCase() + order.status.substring(1)),
                    _DetailRow(
                      label: 'Total Amount',
                      value: '₱${order.totalAmount.toStringAsFixed(2)}',
                    ),
                    if (order.shippingAddress['phone'] != null)
                      _DetailRow(
                        label: 'Contact Phone',
                        value: order.shippingAddress['phone'].toString(),
                      ),
                    _DetailRow(
                      label: 'Created',
                      value: order.createdAt.toLocal().toString().substring(0, 19),
                    ),
                    _DetailRow(
                      label: 'Last Updated',
                      value: order.updatedAt.toLocal().toString().substring(0, 19),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Products (${order.productIds.length})',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (order.productIds.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'No products',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      )
                    else
                      ...order.productIds.map((id) {
                        final productName = productNames[id] ?? id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    productName.trim(),
                                    style: GoogleFonts.poppins(
                                      color: Colors.black,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                                Text(
                                  'ID: ${id.length >= 8 ? id.substring(0, 8) : id}',
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    Text(
                      'Shipping Address',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (order.shippingAddress['name'] != null && order.shippingAddress['name'].toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                order.shippingAddress['name'].toString().trim(),
                                style: GoogleFonts.poppins(
                                  color: Colors.black,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          if (order.shippingAddress['phone'] != null && order.shippingAddress['phone'].toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                order.shippingAddress['phone'].toString().trim(),
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          if (order.shippingAddress['line1'] != null && order.shippingAddress['line1'].toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                order.shippingAddress['line1'].toString().trim(),
                                style: GoogleFonts.poppins(
                                  color: Colors.black,
                                  fontSize: 15,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          if (order.shippingAddress['line2'] != null && order.shippingAddress['line2'].toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                order.shippingAddress['line2'].toString().trim(),
                                style: GoogleFonts.poppins(
                                  color: Colors.black,
                                  fontSize: 15,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          if (order.shippingAddress['city'] != null && order.shippingAddress['city'].toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${order.shippingAddress['city'].toString().trim()}${order.shippingAddress['postalCode'] != null && order.shippingAddress['postalCode'].toString().trim().isNotEmpty ? ', ${order.shippingAddress['postalCode'].toString().trim()}' : ''}',
                                style: GoogleFonts.poppins(
                                  color: Colors.black,
                                  fontSize: 15,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          if (order.shippingAddress['label'] != null && order.shippingAddress['label'].toString().trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                order.shippingAddress['label'].toString().trim(),
                                style: GoogleFonts.poppins(
                                  color: Colors.blue[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Payment Proof Section
                    // Check for payment proof URL in order field first, then fall back to shippingAddress
                    if (order.paymentProofUrl != null ||
                        order.shippingAddress['paymentProofUrl'] != null ||
                        order.shippingAddress['paymentProof'] != null)
                      ...[
                        const SizedBox(height: 12),
                        Text(
                          'Payment Proof',
                          style: GoogleFonts.poppins(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Get payment proof URL from order field first, then shippingAddress (for backward compatibility)
                              Builder(
                                builder: (context) {
                                  final proofUrl = order.paymentProofUrl ??
                                      order.shippingAddress['paymentProofUrl'] as String? ??
                                      order.shippingAddress['paymentProof'] as String?;
                                  
                                  if (proofUrl == null || proofUrl.isEmpty) {
                                    return Text(
                                      'No payment proof available',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                        decoration: TextDecoration.none,
                                      ),
                                    );
                                  }
                                  
                                  // Convert relative URL to absolute if needed
                                  String finalImageUrl = proofUrl;
                                  
                                  // If URL is relative (starts with /), construct full URL
                                  if (finalImageUrl.startsWith('/')) {
                                    // Remove /api from base URL if present, then append the image path
                                    final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
                                    finalImageUrl = '$baseUrl$finalImageUrl';
                                  } else if (!finalImageUrl.startsWith('http')) {
                                    // If it's a relative path without leading slash, prepend base URL
                                    final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
                                    finalImageUrl = '$baseUrl/$finalImageUrl';
                                  }
                                  
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Payment Screenshot:',
                                        style: GoogleFonts.poppins(
                                          color: Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Display payment proof image with tap to view full size
                                      Builder(
                                        builder: (context) {
                                          // Use the already constructed finalImageUrl
                                          
                                          return GestureDetector(
                                            onTap: () {
                                              // Show full-size image in a dialog with zoom capability
                                              showDialog(
                                                context: context,
                                                builder: (dialogContext) => Dialog(
                                                  backgroundColor: Colors.transparent,
                                                  insetPadding: const EdgeInsets.all(20),
                                                  child: Stack(
                                                    children: [
                                                      Center(
                                                        child: InteractiveViewer(
                                                          minScale: 0.5,
                                                          maxScale: 4.0,
                                                          child: Image.network(
                                                            finalImageUrl,
                                                            fit: BoxFit.contain,
                                                            errorBuilder: (context, error, stackTrace) {
                                                              return Container(
                                                                padding: const EdgeInsets.all(40),
                                                                color: Colors.black54,
                                                                child: const Column(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    Icon(Icons.error_outline, color: Colors.white, size: 48),
                                                                    SizedBox(height: 12),
                                                                    Text('Failed to load image', style: TextStyle(color: Colors.white)),
                                                                  ],
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                      Positioned(
                                                        top: 8,
                                                        right: 8,
                                                        child: IconButton(
                                                          icon: const Icon(Icons.close, color: Colors.white),
                                                          onPressed: () => Navigator.of(dialogContext).pop(),
                                                          style: IconButton.styleFrom(
                                                            backgroundColor: Colors.black54,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.network(
                                                finalImageUrl,
                                                width: double.infinity,
                                                fit: BoxFit.contain,
                                                headers: const {
                                                  'Accept': 'image/*',
                                                },
                                                loadingBuilder: (context, child, loadingProgress) {
                                                  if (loadingProgress == null) return child;
                                                  return Container(
                                                    height: 200,
                                                    color: Colors.grey[200],
                                                    child: Center(
                                                      child: CircularProgressIndicator(
                                                        value: loadingProgress.expectedTotalBytes != null
                                                            ? loadingProgress.cumulativeBytesLoaded /
                                                                loadingProgress.expectedTotalBytes!
                                                            : null,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                errorBuilder: (context, error, stackTrace) {
                                                  // Log the error for debugging
                                                  developer.log(
                                                    'Failed to load payment proof image: $error',
                                                    name: 'OrdersAdmin',
                                                    error: error,
                                                    stackTrace: stackTrace,
                                                  );
                                                  developer.log('Image URL: $finalImageUrl', name: 'OrdersAdmin');
                                                  
                                                  return Container(
                                                    height: 200,
                                                    color: Colors.grey[200],
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        const Icon(
                                                          Icons.error_outline,
                                                          color: Colors.red,
                                                          size: 48,
                                                        ),
                                                        const SizedBox(height: 8),
                                                        Text(
                                                          'Failed to load image',
                                                          style: GoogleFonts.poppins(
                                                            color: Colors.grey[600],
                                                            fontSize: 14,
                                                            decoration: TextDecoration.none,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Padding(
                                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                                          child: Text(
                                                            finalImageUrl.length > 50 
                                                                ? '${finalImageUrl.substring(0, 50)}...'
                                                                : finalImageUrl,
                                                            style: GoogleFonts.poppins(
                                                              color: Colors.grey[500],
                                                              fontSize: 10,
                                                              decoration: TextDecoration.none,
                                                            ),
                                                            textAlign: TextAlign.center,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 8),
                                                        TextButton(
                                                          onPressed: () {
                                                            // Trigger rebuild to retry loading
                                                            (context as Element).markNeedsBuild();
                                                          },
                                                          child: const Text('Retry'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tap image to view full size',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                          fontStyle: FontStyle.italic,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Payment status
                                      if (order.shippingAddress['paymentStatus'] != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: order.shippingAddress['paymentStatus'] == 'confirmed' ||
                                                    order.shippingAddress['paymentStatus'] == 'downpayment_paid'
                                                ? Colors.green[50]
                                                : Colors.orange[50],
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: order.shippingAddress['paymentStatus'] == 'confirmed' ||
                                                      order.shippingAddress['paymentStatus'] == 'downpayment_paid'
                                                  ? Colors.green[300]!
                                                  : Colors.orange[300]!,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                order.shippingAddress['paymentStatus'] == 'confirmed' ||
                                                        order.shippingAddress['paymentStatus'] == 'downpayment_paid'
                                                    ? Icons.check_circle
                                                    : Icons.pending,
                                                size: 16,
                                                color: order.shippingAddress['paymentStatus'] == 'confirmed' ||
                                                        order.shippingAddress['paymentStatus'] == 'downpayment_paid'
                                                    ? Colors.green[700]
                                                    : Colors.orange[700],
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Payment Status: ${(order.shippingAddress['paymentStatus'] as String? ?? 'pending').toUpperCase()}',
                                                style: GoogleFonts.poppins(
                                                  color: order.shippingAddress['paymentStatus'] == 'confirmed' ||
                                                          order.shippingAddress['paymentStatus'] == 'downpayment_paid'
                                                      ? Colors.green[700]
                                                      : Colors.orange[700],
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  decoration: TextDecoration.none,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim(),
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
