import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/order_record.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../../widgets/toast.dart';
import '../views/sign_in.dart';
import '../checkout/payment_confirmation_screen.dart';
import '../checkout/models.dart';

/// =============================================================
/// OrdersTab
///
/// Main orders screen with top navigation bar for filtering:
/// - To Pay: Orders requiring payment
/// - To Ship: Confirmed orders awaiting shipment
/// - To Deliver: Shipped orders awaiting delivery
/// - Confirm: Confirmed orders
/// - Cancelled: Cancelled orders
///
/// Follows Apple HIG with clean, modern design and smooth animations.
/// =============================================================
class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  final AuthService _auth = AuthService();
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final TextEditingController _searchController = TextEditingController();

  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  List<OrderRecord> _orders = [];
  Map<String, Product> _productLookup = {};
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  
  // Selected filter value matching admin panel style
  // 'all', 'to_pay', 'to_ship', 'to_deliver', 'confirm', 'cancelled', 'expired'
  String _selectedFilter = 'all';
  
  // Filter options matching admin panel style
  static const List<Map<String, String>> _filterOptions = [
    {'value': 'all', 'label': 'All'},
    {'value': 'to_pay', 'label': 'To Pay'},
    {'value': 'to_ship', 'label': 'To Ship'},
    {'value': 'to_deliver', 'label': 'To Deliver'},
    {'value': 'confirm', 'label': 'Confirm'},
    {'value': 'cancelled', 'label': 'Cancelled'},
    {'value': 'expired', 'label': 'Expired'},
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _loadOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Load all orders for the current user
  Future<void> _loadOrders({bool showLoader = true}) async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _orders = [];
        _productLookup = {};
        _loading = false;
        _error = null;
      });
      return;
    }

    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // Fetch orders and products in parallel for better performance
      final ordersFuture = _db.getAllOrders();
      final productsFuture = _db.getAllProducts();
      
      final allOrders = await ordersFuture;
      developer.log('📦 Loaded ${allOrders.length} total orders from database');
      developer.log('👤 Current user ID: ${user.id}');
      
      // Filter orders for current user and sort by creation date (newest first)
      final orders = allOrders
          .where((order) => order.userId == user.id)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      developer.log('✅ Found ${orders.length} orders for current user');
      
      final products = await productsFuture;
      setState(() {
        _orders = orders;
        _productLookup = {for (final product in products) product.id: product};
        _loading = false;
        _error = null;
      });
    } catch (e, stackTrace) {
      developer.log('❌ Error loading orders: $e');
      developer.log('Stack trace: $stackTrace');
      setState(() {
        _error = 'Failed to load orders: $e';
        _loading = false;
      });
    }
  }

  /// Filter orders based on selected filter (matching admin panel style)
  List<OrderRecord> _getFilteredOrders() {
    Iterable<OrderRecord> filtered = _orders;

    if (_selectedFilter != 'all') {
      filtered = filtered.where((order) {
      final status = order.status.toLowerCase();
      final paymentStatus = order.shippingAddress['paymentStatus'] as String?;
      
      switch (_selectedFilter) {
        case 'to_pay':
          // Orders that need payment (pending, pending_payment_verification)
          // Exclude cancelled, expired, and confirmed orders
          if (status == 'cancelled' || status == 'expired') return false;
          if (status == 'confirmed' && 
              (paymentStatus == 'confirmed' || paymentStatus == 'downpayment_paid')) {
            return false;
          }
          return true;
          
        case 'to_ship':
          // Confirmed orders that are ready to ship (not yet shipped)
          if (status == 'cancelled' || status == 'expired') return false;
          if (status == 'confirmed' && 
              (paymentStatus == 'confirmed' || paymentStatus == 'downpayment_paid')) {
            return true;
          }
          return false;
          
        case 'to_deliver':
          // Shipped orders awaiting delivery
          return status == 'shipped';
          
        case 'confirm':
          // Confirmed orders (general confirmed status)
          if (status == 'cancelled' || status == 'expired') return false;
          return status == 'confirmed' || 
                 paymentStatus == 'confirmed' || 
                 paymentStatus == 'downpayment_paid';
          
        case 'cancelled':
          return status == 'cancelled';
          
        case 'expired':
          return status == 'expired';
          
        default:
          return true;
      }
      });
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery;
      filtered = filtered.where((order) {
        // match order id
        if (order.id.toLowerCase().contains(query)) return true;

        // match product names
        for (final pid in order.productIds) {
          final product = _productLookup[pid];
          if (product != null &&
              product.name.toLowerCase().contains(query)) {
            return true;
          }
        }
        return false;
      });
    }

    return filtered.toList();
  }

  /// Get payment amount for an order
  double _getPaymentAmount(OrderRecord order) {
    final paymentMethod = order.shippingAddress['paymentMethod']?.toString();
    final totalAmount = order.totalAmount;

    // Handle downpayment value coming back as num or string from backend
    final downpaymentRaw = order.shippingAddress['downpayment'];
    double? downpayment;
    if (downpaymentRaw is num) {
      downpayment = downpaymentRaw.toDouble();
    } else if (downpaymentRaw is String) {
      downpayment = double.tryParse(downpaymentRaw);
    }
    
    if (paymentMethod == 'cod') {
      // COD: 20% downpayment (fallback if downpayment missing)
      return downpayment ?? (totalAmount * 0.20);
    }
    // GCash: Full payment upfront
    return totalAmount;
  }

  /// Get payment method enum
  PaymentMethod _getPaymentMethod(OrderRecord order) {
    final paymentMethod = order.shippingAddress['paymentMethod'] as String?;
    return paymentMethod == 'gcash' ? PaymentMethod.gcash : PaymentMethod.cod;
  }

  /// Navigate to payment confirmation screen
  void _navigateToPayment(OrderRecord order) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => PaymentConfirmationScreen(
          orderId: order.id,
          paymentAmount: _getPaymentAmount(order),
          paymentMethod: _getPaymentMethod(order),
          totalAmount: order.totalAmount,
          orderCreatedAt: order.createdAt,
        ),
      ),
    ).then((_) {
      // Reload orders after returning from payment screen
      _loadOrders();
    });
  }

  /// Cancel an expired order
  Future<void> _cancelExpiredOrder(OrderRecord order) async {
    try {
      // Set order status to cancelled
      await _db.updateOrderStatus(order.id, 'cancelled');
      
      // Reload orders to reflect the change
      await _loadOrders();
      
      if (mounted) {
        Toast.info(context, 'Order cancelled successfully');
      }
    } catch (e) {
      if (mounted) {
        // Show error message
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: Text(
              'Error',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            content: Text(
              'Failed to cancel order: $e',
              style: GoogleFonts.poppins(),
            ),
            actions: [
              CupertinoDialogAction(
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          ),
        );
      }
    }
  }

  /// Repay an expired order by resetting its status and navigating to payment
  /// This will reset the timer by using current time instead of orderCreatedAt
  Future<void> _repayExpiredOrder(OrderRecord order) async {
    try {
      // Reset order status to pending so it can be paid again
      await _db.updateOrderStatus(order.id, 'pending');
      
      // Reload orders to reflect the change
      await _loadOrders();
      
      // Navigate to payment screen with resetTimer flag to reset the timer
      if (mounted) {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => PaymentConfirmationScreen(
              orderId: order.id,
              paymentAmount: _getPaymentAmount(order),
              paymentMethod: _getPaymentMethod(order),
              totalAmount: order.totalAmount,
              orderCreatedAt: order.createdAt,
              resetTimer: true, // Reset timer for repaid orders
            ),
          ),
        ).then((_) {
          // Reload orders after returning from payment screen
          _loadOrders();
        });
      }
    } catch (e) {
      if (mounted) {
        // Show error message
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: Text(
              'Error',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            content: Text(
              'Failed to reset order for repayment: $e',
              style: GoogleFonts.poppins(),
            ),
            actions: [
              CupertinoDialogAction(
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          ),
        );
      }
    }
  }

  /// Get available actions for an order based on its status
  List<PopupMenuItem<String>> _getOrderActions(OrderRecord order) {
    final status = order.status.toLowerCase();
    final paymentStatus = order.shippingAddress['paymentStatus'] as String?;
    final isExpired = status == 'expired';
    final needsPayment = (status == 'pending' || status == 'pending_payment_verification') &&
                         paymentStatus != 'confirmed' && paymentStatus != 'downpayment_paid';

    final List<PopupMenuItem<String>> items = [];

    // Items action - always available
    items.add(
      PopupMenuItem<String>(
        value: 'items',
        child: Row(
          children: [
            const Icon(CupertinoIcons.cube_box, size: 18, color: Color(0xFF8D6E63)),
            const SizedBox(width: 12),
            Text(
              'Items',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );

    // Expired orders: Cancel and Pay (Pay redirects to complete payment screen)
    if (isExpired) {
      items.add(
        PopupMenuItem<String>(
          value: 'cancel',
          child: Row(
            children: [
              const Icon(CupertinoIcons.xmark_circle, size: 18, color: CupertinoColors.systemRed),
              const SizedBox(width: 12),
              Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.systemRed,
                ),
              ),
            ],
          ),
        ),
      );
      items.add(
        PopupMenuItem<String>(
          value: 'repay', // Still uses 'repay' action but shows as 'Pay'
          child: Row(
            children: [
              const Icon(CupertinoIcons.creditcard, size: 18, color: Color(0xFFFF9800)),
              const SizedBox(width: 12),
              Text(
                'Pay', // Changed from 'Repay' to 'Pay'
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFF9800),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // To Pay orders: Pay and Cancel actions
    else if (needsPayment) {
      items.add(
        PopupMenuItem<String>(
          value: 'pay',
          child: Row(
            children: [
              const Icon(CupertinoIcons.creditcard, size: 18, color: Color(0xFFFF9800)),
              const SizedBox(width: 12),
              Text(
                'Pay',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFF9800),
                ),
              ),
            ],
          ),
        ),
      );
      items.add(
        PopupMenuItem<String>(
          value: 'cancel',
          child: Row(
            children: [
              const Icon(CupertinoIcons.xmark_circle, size: 18, color: CupertinoColors.systemRed),
              const SizedBox(width: 12),
              Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.systemRed,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return items;
  }

  /// Handle order action selection
  void _handleOrderAction(String action, OrderRecord order) {
    switch (action) {
      case 'items':
        _showItemsSheet(order);
        break;
      case 'cancel':
        // Cancel can be used for both expired and to_pay orders
        _cancelExpiredOrder(order);
        break;
      case 'repay':
        _repayExpiredOrder(order);
        break;
      case 'pay':
        _navigateToPayment(order);
        break;
    }
  }

  /// Show order items in a modal sheet
  void _showItemsSheet(OrderRecord order) {
    final products = order.productIds
        .map((id) => _productLookup[id])
        .whereType<Product>()
        .toList();

    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header with close button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: CupertinoColors.separator.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order Items',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: const Color(0xFF8D6E63), // Brown instead of black
                      decoration: TextDecoration.none,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
                    child: Text(
                      'Close',
                      style: GoogleFonts.poppins(
                        color: CupertinoColors.systemBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Items list
            Expanded(
              child: products.isEmpty
                  ? Center(
                      child: Text(
                        'No products found',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF5F5B56), // Dark grey instead of black54
                          fontSize: 16,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemGroupedBackground,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              // Product image
                              if (product.imageUrls.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    product.imageUrls.first,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 60,
                                      height: 60,
                                      color: CupertinoColors.systemGrey4,
                                      child: const Icon(
                                        CupertinoIcons.photo,
                                        size: 30,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemGrey4,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.cube_box,
                                    size: 30,
                                  ),
                                ),
                              const SizedBox(width: 12),
                              // Product details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.name,
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                        color: const Color(0xFF8D6E63), // Brown instead of black
                                        decoration: TextDecoration.none,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      product.description.isNotEmpty
                                          ? product.description
                                          : '${product.category} • ${product.style}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: const Color(0xFF5F5B56), // Dark grey instead of black54
                                        decoration: TextDecoration.none,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '₱${product.price.toStringAsFixed(2)}',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: CupertinoColors.label,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Get color for filter (matching admin panel style)
  Color _getFilterColor(String filterValue) {
    switch (filterValue) {
      case 'to_pay':
        return const Color(0xFFFF9800); // Orange
      case 'to_ship':
        return CupertinoColors.systemBlue;
      case 'to_deliver':
        return CupertinoColors.systemIndigo;
      case 'confirm':
        return CupertinoColors.systemTeal;
      case 'cancelled':
        return CupertinoColors.systemRed;
      case 'expired':
        return const Color(0xFFFF6B35); // Orange-red for expired
      default:
        return CupertinoColors.systemGrey;
    }
  }

  /// Get category name for current filter
  String _getCurrentCategory() {
    final option = _filterOptions.firstWhere(
      (opt) => opt['value'] == _selectedFilter,
      orElse: () => {'value': 'all', 'label': 'All'},
    );
    return option['label'] ?? 'All';
  }

  /// Build order card with modern design
  Widget _buildOrderCard(OrderRecord order, String category) {
    final productNames = order.productIds
        .map((id) => _productLookup[id]?.name ?? 'Product')
        .toList(growable: false);
    final previewName = productNames.isEmpty ? 'Custom order' : productNames.first;
    final extraCount = productNames.length > 1 ? productNames.length - 1 : 0;
    
    final shippingLine = [
      order.shippingAddress['line1'],
      order.shippingAddress['line2'],
      order.shippingAddress['city'],
      order.shippingAddress['postalCode'] ?? order.shippingAddress['country'],
    ]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(', ');

    // Get color and category based on current tab or actual order status
    // When filter is 'all', show the actual order status instead of 'All'
    final String displayCategory;
    final Color categoryColor;
    if (_selectedFilter == 'all') {
      // Show actual order status when in 'all' tab
      final status = order.status.toLowerCase();
      final paymentStatus = order.shippingAddress['paymentStatus'] as String?;
      
      // Determine the appropriate category label based on order status
      if (status == 'expired') {
        displayCategory = 'Expired';
        categoryColor = _getFilterColor('expired');
      } else if (status == 'cancelled') {
        displayCategory = 'Cancelled';
        categoryColor = _getFilterColor('cancelled');
      } else if (status == 'shipped') {
        displayCategory = 'To Deliver';
        categoryColor = _getFilterColor('to_deliver');
      } else if (status == 'confirmed' && 
                 (paymentStatus == 'confirmed' || paymentStatus == 'downpayment_paid')) {
        displayCategory = 'To Ship';
        categoryColor = _getFilterColor('to_ship');
      } else if (status == 'pending' || status == 'pending_payment_verification') {
        displayCategory = 'To Pay';
        categoryColor = _getFilterColor('to_pay');
      } else {
        displayCategory = 'Pending';
        categoryColor = _getFilterColor('to_pay');
      }
    } else {
      // Use the filter category when not in 'all' tab
      displayCategory = category;
      categoryColor = _getFilterColor(_selectedFilter);
    }
    
    final needsPayment = _selectedFilter == 'to_pay'; // To Pay filter

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: categoryColor.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with order ID and date
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order ${order.id.substring(0, 8).toUpperCase()}',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: const Color(0xFF8D6E63), // Brown instead of black
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Placed on ${_dateFormat.format(order.createdAt)}',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: const Color(0xFF5F5B56), // Dark grey instead of black54
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              // Category badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: categoryColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  displayCategory, // Use displayCategory instead of category
                  style: GoogleFonts.poppins(
                    color: categoryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Product preview
          Text(
            previewName + (extraCount > 0 ? ' +$extraCount more' : ''),
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF8D6E63), // Brown instead of black
              decoration: TextDecoration.none,
            ),
          ),
          // Shipping address if available
          if (shippingLine.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Shipping to: $shippingLine',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: const Color(0xFF5F5B56), // Dark grey instead of black87
                decoration: TextDecoration.none,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Total amount and action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Amount',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: const Color(0xFF5F5B56), // Dark grey instead of black54
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₱${order.totalAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF8D6E63), // Brown instead of black
                      decoration: TextDecoration.none,
                    ),
                  ),
                  // Show payment amount for "To Pay" orders
                  if (needsPayment) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Pay: ₱${_getPaymentAmount(order).toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: categoryColor,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
              // 3-dot menu button for order actions - using standard PopupMenuButton
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey6,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    CupertinoIcons.ellipsis,
                    size: 20,
                    color: Color(0xFF8D6E63),
                  ),
                ),
                itemBuilder: (context) => _getOrderActions(order),
                onSelected: (value) => _handleOrderAction(value, order),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build segmented control matching admin panel style
  /// Uses a scrollable row of segmented buttons similar to Material SegmentedButton
  Widget _buildTabNavigation() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _filterOptions.map((option) {
            final isSelected = _selectedFilter == option['value'];
            final filterColor = _getFilterColor(option['value']!);
            
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFilter = option['value']!;
                });
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? (option['value'] == 'all' 
                          ? const Color(0xFF8D6E63) // Brown for "All"
                          : filterColor.withValues(alpha: 0.15))
                      : CupertinoColors.systemGrey5,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected 
                        ? (option['value'] == 'all' 
                            ? const Color(0xFF8D6E63)
                            : filterColor.withValues(alpha: 0.5))
                        : CupertinoColors.systemGrey4,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  option['label']!,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected 
                        ? (option['value'] == 'all' 
                            ? Colors.white
                            : filterColor)
                        : const Color(0xFF5F5B56),
                  ),
                  overflow: TextOverflow.visible,
                  softWrap: false,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Build signed out state
  Widget _buildSignedOut() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            CupertinoIcons.lock_shield,
            size: 64,
            color: Color(0xFFBCAAA4),
          ),
          const SizedBox(height: 16),
          Text(
            'Sign in to track your orders',
            style: GoogleFonts.poppins(
              color: const Color(0xFF8D6E63), // Brown instead of black
              fontSize: 18,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'View and manage all your orders in one place',
            style: GoogleFonts.poppins(
              color: const Color(0xFF5F5B56), // Dark grey instead of black54
              fontSize: 14,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          CupertinoButton.filled(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (_) => const SignInScreen(),
                  fullscreenDialog: true,
                ),
              );
            },
            child: Text(
              'Sign In',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final filteredOrders = _getFilteredOrders();
    final currentCategory = _getCurrentCategory();

    // Build content based on state
    Widget content;
    if (_loading) {
      content = const Center(child: CupertinoActivityIndicator());
    } else if (user == null) {
      content = _buildSignedOut();
    } else if (_error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 64,
                color: CupertinoColors.systemGrey,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: GoogleFonts.poppins(
                  color: const Color(0xFF8D6E63), // Brown instead of black
                  fontSize: 16,
                  decoration: TextDecoration.none,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              CupertinoButton.filled(
                onPressed: _loadOrders,
                child: Text(
                  'Try Again',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_orders.isEmpty) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.cube_box,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'No orders yet',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8D6E63), // Brown instead of black
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your order history and tracking will appear here',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF5F5B56), // Dark grey instead of black54
                  decoration: TextDecoration.none,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else {
      // Always show navigation and build content with admin panel style
      // Build filtered orders list with admin panel style
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // Search bar at the top (above filters)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CupertinoTextField(
                  controller: _searchController,
                  placeholder: 'Search orders by ID or product name',
                  placeholderStyle: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF8D6E63).withValues(alpha: 0.6),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFBCAAA4).withValues(alpha: 0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(CupertinoIcons.search, color: Color(0xFF8D6E63), size: 18),
                  ),
                  suffix: _searchQuery.isNotEmpty
                      ? CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(24, 24),
                          onPressed: () {
                            _searchController.clear();
                          },
                          child: const Icon(
                            CupertinoIcons.clear_circled_solid,
                            size: 18,
                            color: Color(0xFF8D6E63),
                          ),
                        )
                      : null,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF5F5B56),
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${filteredOrders.length} ${filteredOrders.length == 1 ? 'order' : 'orders'}',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF8D6E63), // Brown instead of black
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Tab navigation matching admin panel style - always visible
          _buildTabNavigation(),
          // Orders list or empty state
          if (filteredOrders.isEmpty)
            // No orders in selected category
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.cube_box,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No $currentCategory orders',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8D6E63), // Brown instead of black
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Orders in this category will appear here',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: const Color(0xFF5F5B56), // Dark grey instead of black54
                        decoration: TextDecoration.none,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            // Orders list
            ...filteredOrders.map((order) => _buildOrderCard(order, currentCategory)),
        ],
      );
    }

    // Light brown color for navigation bar
    const lightBrown = Color(0xFFF4E6D4);
    const mediumBrown = Color(0xFF8D6E63);
    
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: lightBrown,
        border: Border(
          bottom: BorderSide(
            color: mediumBrown.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        middle: Text(
          'Orders',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: mediumBrown,
          ),
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          color: CupertinoColors.systemBlue,
          onRefresh: () => _loadOrders(showLoader: false),
          child: content,
        ),
      ),
    );
  }
}

