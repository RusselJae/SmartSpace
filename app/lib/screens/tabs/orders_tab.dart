import 'dart:async';
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
import '../../widgets/underline_filter_bar.dart';
import '../../utils/order_payment_balance.dart';
import '../checkout/order_invoice_screen.dart';
import '../views/sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

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
/// Follows Apple HIG: clear hierarchy, springy micro-interactions, walnut brand accent.
/// =============================================================

/// Deep walnut — primary brand accent (replaces older medium brown on this screen).
const Color _kWalnut = Color(0xFF5C4033);

/// Soft wash behind the nav bar; keeps contrast with walnut title text.
const Color _kWalnutWash = Color(0xFFF5EFEA);

class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> with WidgetsBindingObserver {
  final AuthService _auth = AuthService();
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final TextEditingController _searchController = TextEditingController();

  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  List<OrderRecord> _orders = [];
  Map<String, Product> _productLookup = {};
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  final List<Timer> _postResumeRefreshTimers = <Timer>[];

  Future<void> _openOrderInvoice({
    required String orderId,
    required String userId,
    required bool download,
  }) async {
    // Open above any modal/sheet so the invoice always appears "on top of all screens"
    // (same behavior as download).
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    await Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (_) => OrderInvoiceScreen(
          orderId: orderId,
          userId: userId,
          autoDownload: download,
        ),
      ),
    );
  }
  
  // Selected filter value matching admin panel style.
  // 'all', 'to_pay', 'to_ship', 'to_deliver', 'confirm', 'cancelled'
  String _selectedFilter = 'all';
  
  // Filter options matching admin panel style
  static const List<Map<String, String>> _filterOptions = [
    {'value': 'all', 'label': 'All'},
    {'value': 'to_pay', 'label': 'To Pay'},
    {'value': 'to_ship', 'label': 'To Ship'},
    {'value': 'to_deliver', 'label': 'To Deliver'},
    {'value': 'confirm', 'label': 'Confirmed'},
    {'value': 'cancelled', 'label': 'Cancelled'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _primeAndLoad();
  }

  Future<void> _primeAndLoad() async {
    // Orders depend on an active user session. Ensure it is restored before querying.
    await _auth.initializeSession();
    if (!mounted) return;
    await _loadOrders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _postResumeRefreshTimers) {
      timer.cancel();
    }
    _postResumeRefreshTimers.clear();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user returns from external PayMongo browser, refresh orders so
    // webhook-updated payment statuses/remaining balance are reflected quickly.
    if (state == AppLifecycleState.resumed && mounted) {
      _loadOrders(showLoader: false);
      _schedulePostResumeRefreshes();
    }
  }

  void _schedulePostResumeRefreshes() {
    for (final timer in _postResumeRefreshTimers) {
      timer.cancel();
    }
    _postResumeRefreshTimers.clear();

    for (final seconds in const <int>[2, 5, 10]) {
      _postResumeRefreshTimers.add(
        Timer(Duration(seconds: seconds), () {
          if (!mounted) return;
          _loadOrders(showLoader: false);
        }),
      );
    }
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
      final ordersFuture = _db.getAllOrders(forUserId: user.id);
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
          // Orders that need payment.
          if (status == 'cancelled') return false;
          if (status == 'confirmed' && 
              (paymentStatus == 'completed' || paymentStatus == 'downpayment_received')) {
            return false;
          }
          return true;
          
        case 'to_ship':
          // Confirmed orders that are ready to ship (not yet shipped)
          if (status == 'cancelled') return false;
          if (status == 'confirmed' && 
              (paymentStatus == 'completed' || paymentStatus == 'downpayment_received')) {
            return true;
          }
          return false;
          
        case 'to_deliver':
          // Shipped orders awaiting delivery
          return status == 'shipped';
          
        case 'confirm':
          // Confirmed orders (general confirmed status)
          if (status == 'cancelled') return false;
          return status == 'confirmed' || 
                 paymentStatus == 'completed' || 
                 paymentStatus == 'downpayment_received';
          
        case 'cancelled':
          return status == 'cancelled';
          
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

    final remRaw = order.shippingAddress['remainingBalance'];
    double? remaining;
    if (remRaw is num) {
      remaining = remRaw.toDouble();
    } else if (remRaw is String) {
      remaining = double.tryParse(remRaw);
    }

    if (paymentMethod == 'cod') {
      // COD: 20% downpayment (fallback if downpayment missing)
      return downpayment ?? (totalAmount * 0.20);
    }
    if (paymentMethod == 'paymongo') {
      final ps = order.shippingAddress['paymentStatus']?.toString();
      // After first PayMongo charge on a down-payment plan, user pays remaining balance next.
      if (ps == 'downpayment_received' && (remaining ?? 0) > 0.01) {
        return remaining ?? totalAmount;
      }
      if ((remaining ?? 0) > 0.01 && (downpayment ?? 0) > 0) {
        return downpayment ?? totalAmount;
      }
    }
    return totalAmount;
  }

  /// Get payment method enum
  PaymentMethod _getPaymentMethod(OrderRecord order) {
    final paymentMethod = order.shippingAddress['paymentMethod'] as String?;
    switch (paymentMethod) {
      case 'gcash':
        return PaymentMethod.gcash;
      case 'paymongo':
        return PaymentMethod.paymongo;
      case 'cod':
      default:
        return PaymentMethod.cod;
    }
  }

  /// Opens manual GCash proof flow or PayMongo hosted checkout.
  Future<double?> _promptForPaymongoAmount({required double maxPesos}) async {
    final initial = (maxPesos > 0.01) ? maxPesos : 1.0;
    final controller = TextEditingController(text: initial.toStringAsFixed(2));

    final result = await showCupertinoDialog<double>(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: Text(
            'Choose amount to pay',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoTextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                placeholder: '0.00',
                style: GoogleFonts.poppins(),
                decoration: BoxDecoration(
                  border: Border.all(color: _kWalnut.withValues(alpha: 0.25), width: 1),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Max: ₱${maxPesos.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: _kWalnut,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                final raw = controller.text.trim();
                final cleaned = raw.replaceAll(',', '');
                final parsed = double.tryParse(cleaned);
                if (parsed == null || parsed <= 0.01) {
                  Navigator.pop(ctx, null);
                  return;
                }
                final clamped = parsed > maxPesos ? maxPesos : parsed;
                Navigator.pop(ctx, clamped);
              },
              child: Text(
                'Pay',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: _kWalnut),
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }

  /// Opens manual GCash proof flow or PayMongo hosted checkout.
  Future<void> _navigateToPayment(
    OrderRecord order, {
    bool allowCustomAmount = false,
  }) async {
    final pm = order.shippingAddress['paymentMethod']?.toString();
    if (pm == 'paymongo') {
      if (!mounted) return;
      // Root navigator so the payment page covers the whole app (tabs hidden).
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => _OrderPaymentScreen(
            order: order,
            productsById: _productLookup,
            allowCustomAmount: allowCustomAmount,
            auth: _auth,
            db: _db,
          ),
        ),
      );
      await _loadOrders();
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => PaymentConfirmationScreen(
          orderId: order.id,
          paymentAmount: _getPaymentAmount(order),
          paymentMethod: _getPaymentMethod(order),
          totalAmount: order.totalAmount,
          orderCreatedAt: order.createdAt,
        ),
      ),
    );
    await _loadOrders();
  }

  /// Confirms cancellation — **no refunds** (including after a down payment).
  Future<void> _confirmCancelOrder(OrderRecord order) async {
    final go = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(
          'Cancel this order?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Payments are non-refundable. If you already paid a down payment, it is not returned. '
          'Continue with cancellation?',
          style: GoogleFonts.poppins(fontSize: 14, height: 1.35),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep order', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel order', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await _cancelExpiredOrder(order);
    }
  }

  /// Cancel an order
  Future<void> _cancelExpiredOrder(OrderRecord order) async {
    try {
      // Set order status to cancelled
      await _db.updateOrderStatus(order.id, 'cancelled', customerUserId: order.userId);
      
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

  /// Get available actions for an order based on its status
  List<PopupMenuItem<String>> _getOrderActions(OrderRecord order) {
    final status = order.status.toLowerCase();
    final paymentStatus = order.shippingAddress['paymentStatus'] as String?;
    final paymentMethod = order.shippingAddress['paymentMethod']?.toString();
    final remainingBalance = parseShippingDouble(order.shippingAddress, 'remainingBalance') ?? 0;

    final hasPaymongoOutstandingBalance = paymentMethod == 'paymongo' &&
        status != 'cancelled' &&
        remainingBalance > 0.01;

    final isPaymongoAwaitingFirstCharge = paymentMethod == 'paymongo' &&
        (status == 'pending' || status == 'pending_payment_verification') &&
        (paymentStatus == null || paymentStatus == 'pending');

    final List<PopupMenuItem<String>> items = [];

    // Details action - always available
    items.add(
      PopupMenuItem<String>(
        value: 'details',
        child: Row(
          children: [
            Icon(CupertinoIcons.doc_text, size: 18, color: _kWalnut.withValues(alpha: 0.85)),
            const SizedBox(width: 12),
            Text(
              'Details',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );

    // Keep Pay action visible for PayMongo orders while there is any remaining balance.
    // - First tranche: fixed charge handled by backend.
    // - Subsequent payments: user can pick amount.
    if (hasPaymongoOutstandingBalance) {
      items.add(
        PopupMenuItem<String>(
          value: isPaymongoAwaitingFirstCharge ? 'pay' : 'pay_again',
          child: Row(
            children: [
              const Icon(CupertinoIcons.creditcard, size: 18, color: Color(0xFFFF9800)),
              const SizedBox(width: 12),
              Text(
                isPaymongoAwaitingFirstCharge ? 'Pay' : 'Pay again',
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

      // Only allow cancelling while the order is still awaiting fulfillment.
      final isStillPreFulfillment = status == 'pending' ||
          status == 'pending_payment_verification' ||
          (status == 'confirmed' && remainingBalance > 0.01);
      if (isStillPreFulfillment) {
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
    }

    return items;
  }

  /// Handle order action selection
  void _handleOrderAction(String action, OrderRecord order) {
    switch (action) {
      case 'details':
        _showDetailsSheet(order);
        break;
      case 'cancel':
        // Cancel is available for pre-fulfillment payment states.
        _confirmCancelOrder(order);
        break;
      case 'pay':
        _navigateToPayment(order, allowCustomAmount: false);
        break;
      case 'pay_again':
        _navigateToPayment(order, allowCustomAmount: true);
        break;
    }
  }

  /// Show order details in a modal sheet.
  void _showDetailsSheet(OrderRecord order) {
    final products = order.productIds
        .map((id) => _productLookup[id])
        .whereType<Product>()
        .toList();
    final remainingBalance =
        parseShippingDouble(order.shippingAddress, 'remainingBalance') ?? 0;
    final downpayment =
        parseShippingDouble(order.shippingAddress, 'downpayment') ?? 0;
    final paymentStatus =
        order.shippingAddress['paymentStatus']?.toString() ?? 'pending';
    final currentUser = _auth.currentUser;

    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.82,
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
                    'Order Details',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: _kWalnut,
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
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildDetailCard(
                    title: 'Summary',
                    child: Column(
                      children: [
                        _buildDetailRow('Order ID', '#${order.id.substring(0, 8).toUpperCase()}'),
                        _buildDetailRow('Status', _labelForStatus(order.status)),
                        _buildDetailRow('Payment status', _labelForStatus(paymentStatus)),
                        _buildDetailRow('Order total', '₱${order.totalAmount.toStringAsFixed(2)}'),
                        if (downpayment > 0)
                          _buildDetailRow('Down payment', '₱${downpayment.toStringAsFixed(2)}'),
                        if (remainingBalance > 0)
                          _buildDetailRow('Remaining balance', '₱${remainingBalance.toStringAsFixed(2)}'),
                        _buildDetailRow('Created', _dateFormat.format(order.createdAt)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailCard(
                    title: 'Delivery',
                    child: Column(
                      children: [
                        _buildDetailRow('Name', order.shippingAddress['name']?.toString() ?? '—'),
                        _buildDetailRow('Phone', order.shippingAddress['phone']?.toString() ?? '—'),
                        _buildDetailRow(
                          'Address',
                          [
                            order.shippingAddress['line1']?.toString() ?? '',
                            order.shippingAddress['line2']?.toString() ?? '',
                            order.shippingAddress['city']?.toString() ?? '',
                            order.shippingAddress['postalCode']?.toString() ?? '',
                          ].where((s) => s.trim().isNotEmpty).join(', '),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailCard(
                    title: 'Invoice',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Open the latest invoice for this order. It updates after each payment and late-fee change.',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: const Color(0xFF5F5B56),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: currentUser == null
                                    ? null
                                    : () async {
                                        await _openOrderInvoice(
                                          orderId: order.id,
                                          userId: currentUser.id,
                                          download: false,
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kWalnut,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      CupertinoIcons.doc_text_fill,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'View invoice',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: currentUser == null
                                    ? null
                                    : () async {
                                        await _openOrderInvoice(
                                          orderId: order.id,
                                          userId: currentUser.id,
                                          download: true,
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: _kWalnut,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                    side: BorderSide(
                                      color: _kWalnut.withValues(alpha: 0.25),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      CupertinoIcons.arrow_down_doc,
                                      size: 18,
                                      color: _kWalnut.withValues(alpha: 0.9),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Download',
                                      style: GoogleFonts.poppins(
                                        color: _kWalnut.withValues(alpha: 0.9),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailCard(
                    title: 'Products',
                    child: products.isEmpty
                        ? Text(
                            'No products found',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF5F5B56),
                              fontSize: 14,
                            ),
                          )
                        : Column(
                            children: List.generate(products.length, (index) {
                              final product = products[index];
                              return Padding(
                                padding: EdgeInsets.only(bottom: index == products.length - 1 ? 0 : 12),
                                child: Row(
                                  children: [
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
                                            child: const Icon(CupertinoIcons.photo, size: 30),
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
                                        child: const Icon(CupertinoIcons.cube_box, size: 30),
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            product.name,
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                              color: _kWalnut,
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
                                              fontSize: 12,
                                              color: const Color(0xFF5F5B56),
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '₱${product.price.toStringAsFixed(2)}',
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: _kWalnut,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: const Color(0xFF5F5B56),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '—' : value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: CupertinoColors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _labelForStatus(String raw) {
    if (raw.trim().isEmpty) return '—';
    final words = raw.split('_').where((w) => w.isNotEmpty);
    return words
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
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

  /// One row per distinct product id with aggregated quantity (duplicate ids in cart).
  Map<String, int> _aggregateLineQuantities(OrderRecord order) {
    final m = <String, int>{};
    for (final id in order.productIds) {
      m[id] = (m[id] ?? 0) + 1;
    }
    return m;
  }

  Widget _orderLineThumbnail(Product? product, int qty) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: product != null && product.imageUrls.isNotEmpty
              ? Image.network(
                  product.imageUrls.first,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 56,
                    height: 56,
                    color: CupertinoColors.systemGrey5,
                    alignment: Alignment.center,
                    child: Icon(CupertinoIcons.photo, color: _kWalnut.withValues(alpha: 0.45)),
                  ),
                )
              : Container(
                  width: 56,
                  height: 56,
                  color: CupertinoColors.systemGrey5,
                  alignment: Alignment.center,
                  child: Icon(CupertinoIcons.cube_box, color: _kWalnut.withValues(alpha: 0.45)),
                ),
        ),
        Positioned(
          right: -5,
          bottom: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _kWalnut,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              '×$qty',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Build order card with modern design
  Widget _buildOrderCard(OrderRecord order, String category) {
    final lines = _aggregateLineQuantities(order);
    final remBal = parseShippingDouble(order.shippingAddress, 'remainingBalance');

    // Get color and category based on current tab or actual order status
    // When filter is 'all', show the actual order status instead of 'All'
    final String displayCategory;
    final Color categoryColor;
    if (_selectedFilter == 'all') {
      // Show actual order status when in 'all' tab
      final status = order.status.toLowerCase();
      final paymentStatus = order.shippingAddress['paymentStatus'] as String?;
      
      // Determine the appropriate category label based on order status
      if (status == 'cancelled') {
        displayCategory = 'Cancelled';
        categoryColor = _getFilterColor('cancelled');
      } else if (paymentStatus == 'failed') {
        displayCategory = 'Payment failed';
        categoryColor = _getFilterColor('to_pay');
      } else if (status == 'shipped') {
        displayCategory = 'Delivered';
        categoryColor = _getFilterColor('to_deliver');
      } else if (status == 'confirmed' && 
                 (paymentStatus == 'completed' || paymentStatus == 'downpayment_received')) {
        displayCategory = 'Shipped';
        categoryColor = _getFilterColor('to_ship');
      } else if (status == 'pending' || status == 'pending_payment_verification') {
        displayCategory = 'Pay';
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white, // pure white background behind the word
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _kWalnut.withValues(alpha: 0.16), width: 1),
                          ),
                          child: Text(
                            'Order',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: _kWalnut,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            order.id.substring(0, 8).toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: _kWalnut,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
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
          const SizedBox(height: 14),
          // Line items: image + qty badge, name (ellipsis), unit price.
          if (lines.isEmpty)
            Text(
              'No line items',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: const Color(0xFF5F5B56),
                decoration: TextDecoration.none,
              ),
            )
          else
            ...lines.entries.map((e) {
              final product = _productLookup[e.key];
              final name = product?.name ?? 'Product';
              final unit = product?.price ?? 0.0;
              final q = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _orderLineThumbnail(product, q),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _kWalnut,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Unit ₱${unit.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: const Color(0xFF5F5B56),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 4),
          // Balance + total on the right side.
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (remBal != null && remBal > 0.01)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Remaining balance: ',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500, // not bold the label word
                            color: _kWalnut,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        TextSpan(
                          text: formatRemainingBalancePesos(order),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _kWalnut,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (remBal != null && remBal > 0.01) const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Total: ',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w500, // not bold the label word
                          color: _kWalnut,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      TextSpan(
                        text: '₱${order.totalAmount.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _kWalnut,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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
                    color: _kWalnut,
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

  /// Underline-style filters: black default, walnut active/hover, bottom rule when selected.
  Widget _buildFilterBar() {
    return UnderlineFilterBar(
      entries: _filterOptions
          .map(
            (o) => UnderlineFilterEntry(
              key: o['value']!,
              label: o['label']!,
            ),
          )
          .toList(),
      selectedKey: _selectedFilter,
      onSelect: (key) => setState(() => _selectedFilter = key),
      walnut: _kWalnut,
    );
  }

  /// Build signed out state
  Widget _buildSignedOut() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.lock_shield,
            size: 64,
            color: _kWalnut.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            'Sign in to track your orders',
            style: GoogleFonts.poppins(
              color: _kWalnut,
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
                  color: _kWalnut,
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
                    color: _kWalnut.withValues(alpha: 0.45),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _kWalnut.withValues(alpha: 0.2),
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
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(CupertinoIcons.search, color: _kWalnut.withValues(alpha: 0.75), size: 18),
                  ),
                  suffix: _searchQuery.isNotEmpty
                      ? CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(24, 24),
                          onPressed: () {
                            _searchController.clear();
                          },
                          child: Icon(
                            CupertinoIcons.clear_circled_solid,
                            size: 18,
                            color: _kWalnut.withValues(alpha: 0.75),
                          ),
                        )
                      : null,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF5F5B56),
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 12),
                // Filters sit directly under search — horizontal one-liner, walnut when active.
                _buildFilterBar(),
              ],
            ),
          ),
          const SizedBox(height: 8),
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
                        color: _kWalnut,
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

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: _kWalnut.withValues(alpha: 0.18),
            width: 0.5,
          ),
        ),
        middle: Text(
          'Orders',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: _kWalnut,
          ),
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          color: _kWalnut,
          onRefresh: () => _loadOrders(showLoader: false),
          child: content,
        ),
      ),
    );
  }
}

/// Dedicated payment page for PayMongo order payments.
/// This is intentionally Material-styled (non-Apple look) per Orders flow request.
class _OrderPaymentScreen extends StatefulWidget {
  const _OrderPaymentScreen({
    required this.order,
    required this.productsById,
    required this.allowCustomAmount,
    required this.auth,
    required this.db,
  });

  final OrderRecord order;
  final Map<String, Product> productsById;
  final bool allowCustomAmount;
  final AuthService auth;
  final MySQLDatabaseService db;

  @override
  State<_OrderPaymentScreen> createState() => _OrderPaymentScreenState();
}

class _OrderPaymentScreenState extends State<_OrderPaymentScreen> {
  final TextEditingController _amountController = TextEditingController();
  bool _submitting = false;

  String get _paymentStatus {
    return widget.order.shippingAddress['paymentStatus']?.toString() ?? 'pending';
  }

  double get _downpaymentAmount {
    return parseShippingDouble(widget.order.shippingAddress, 'downpayment') ?? 0;
  }

  bool get _isFirstDownpaymentCharge {
    final plan = widget.order.shippingAddress['paymentPlan']?.toString();
    return plan == 'downpayment' && _paymentStatus == 'pending';
  }

  double get _remainingBalance {
    return parseShippingDouble(widget.order.shippingAddress, 'remainingBalance') ??
        widget.order.totalAmount;
  }

  double get _initialChargeAmount {
    if (_isFirstDownpaymentCharge && _downpaymentAmount > 0.01) {
      return _downpaymentAmount;
    }
    return _remainingBalance;
  }

  @override
  void initState() {
    super.initState();
    _amountController.text = _initialChargeAmount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _payNow() async {
    final user = widget.auth.currentUser;
    if (user == null) {
      Toast.error(context, 'Please sign in');
      return;
    }

    final parsed = double.tryParse(_amountController.text.replaceAll(',', '').trim());
    final amountToPay = widget.allowCustomAmount
        ? (() {
            if (parsed == null || parsed <= 0) return 0.0;
            return parsed > _remainingBalance ? _remainingBalance : parsed;
          })()
        : _initialChargeAmount;
    if (amountToPay <= 0.01) {
      Toast.warning(context, 'Enter a valid amount to pay');
      return;
    }
    setState(() => _submitting = true);
    try {
      final url = await widget.db.createPaymongoCheckoutSession(
        orderId: widget.order.id,
        userId: user.id,
          // Always send an amount. When custom is disabled we still want to charge
          // the exact remaining balance (instead of letting the server default).
          amountPesos: amountToPay,
      );
      if (!mounted) return;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      Toast.info(context, 'Complete payment in the browser');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'PayMongo: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _requiredLabel(String text) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF3E2723),
            ),
          ),
        ),
        Text(
          '*',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: CupertinoColors.systemRed,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final qtyById = <String, int>{};
    for (final id in widget.order.productIds) {
      qtyById[id] = (qtyById[id] ?? 0) + 1;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Order Payment',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: const Color(0xFF3E2723),
          ),
        ),
        backgroundColor: _kWalnutWash,
        foregroundColor: _kWalnut,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF5C4033).withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order #${widget.order.id.substring(0, 8).toUpperCase()}',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  'Products',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...qtyById.entries.map((entry) {
                  final product = widget.productsById[entry.key];
                  final qty = entry.value;
                  final unitPrice = product?.price ?? 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            product?.name ?? 'Product',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontSize: 13),
                          ),
                        ),
                        Text(
                          'x$qty',
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '₱${(unitPrice * qty).toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF5C4033).withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment Summary',
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                _PaySummaryRow(
                  label: 'Order total',
                  value: '₱${widget.order.totalAmount.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 6),
                _PaySummaryRow(
                  label: 'Remaining balance',
                  value: '₱${_remainingBalance.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 10),
                _requiredLabel('Amount'),
                const SizedBox(height: 6),
                TextField(
                  controller: _amountController,
                  readOnly: !widget.allowCustomAmount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    prefixText: '₱ ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFBCAAA4)),
                    ),
                  ),
                ),
                if (widget.allowCustomAmount) ...[
                  const SizedBox(height: 6),
                  Text(
                    'You can pay any amount up to the remaining balance.',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(
                    _isFirstDownpaymentCharge
                        ? 'Initial down payment is fixed by your selected plan.'
                        : 'Amount is fixed for this payment step.',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _payNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5C4033),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Proceed to Pay',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaySummaryRow extends StatelessWidget {
  const _PaySummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 13)),
        Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

