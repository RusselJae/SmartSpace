import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/order_record.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';

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
  final List<String> _statuses = const ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled'];
  
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
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
      
      await _loadOrders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update order: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
              IconButton.outlined(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export functionality coming soon')),
                  );
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
        AdminToolbar(
          title: 'Orders',
          actions: const [],
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
  const _StatusPill({required this.status, required this.onChanged});

  final String status;
  final ValueChanged<String> onChanged;

  /// Returns a clean, light color palette for status indicators
  /// Following Apple HIG with subtle, approachable colors
  Color _statusColor(String value) {
    switch (value) {
      case 'pending':
        return CupertinoColors.systemOrange;
      case 'confirmed':
        return CupertinoColors.systemBlue;
      case 'shipped':
        return CupertinoColors.systemTeal;
      case 'delivered':
        return CupertinoColors.systemGreen;
      case 'cancelled':
        return CupertinoColors.systemRed;
      default:
        return CupertinoColors.systemGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'pending', child: Text('Pending')),
        PopupMenuItem(value: 'confirmed', child: Text('Confirmed')),
        PopupMenuItem(value: 'shipped', child: Text('Shipped')),
        PopupMenuItem(value: 'delivered', child: Text('Delivered')),
        PopupMenuItem(value: 'cancelled', child: Text('Cancelled')),
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
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
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
