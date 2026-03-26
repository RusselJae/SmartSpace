import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/order_record.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../views/sign_in.dart';
import '../../widgets/order_installment_balance_callout.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final AuthService _auth = AuthService();
  final MySQLDatabaseService _db = MySQLDatabaseService();

  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  List<OrderRecord> _orders = [];
  Map<String, Product> _productLookup = {};
  bool _loading = true;
  String? _error;

  static const List<String> _kStatusSteps = ['pending', 'confirmed', 'shipped', 'delivered'];

  @override
  void initState() {
    super.initState();
    _primeAndLoad();
  }

  Future<void> _primeAndLoad() async {
    // This screen can be opened from multiple places. Restore session first so
    // we don't incorrectly render an empty order history.
    await _auth.initializeSession();
    if (!mounted) return;
    await _loadOrders();
  }

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
      final ordersFuture = _db.getAllOrders();
      final productsFuture = _db.getAllProducts();
      final allOrders = await ordersFuture;
      developer.log('📦 Loaded ${allOrders.length} total orders from database');
      developer.log('👤 Current user ID: ${user.id}');
      final orders = allOrders
          .where((order) {
            final matches = order.userId == user.id;
            if (!matches) {
              developer.log('⚠️ Order ${order.id} belongs to user ${order.userId}, not ${user.id}');
            }
            return matches;
          })
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: CupertinoColors.separator.withValues(alpha: 0.3)),
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
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
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
            Expanded(
              child: products.isEmpty
                  ? Center(
                      child: Text(
                        'No products found',
                        style: GoogleFonts.poppins(
                          color: Colors.black54,
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
                                        fontSize: 16,
                                        color: Colors.black,
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
                                        color: Colors.black54,
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

  /// Clean, light color palette for order status
  /// Following Apple HIG with system colors
  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return CupertinoColors.systemBlue;
      case 'shipped':
        return CupertinoColors.systemTeal;
      case 'delivered':
        return CupertinoColors.systemGreen;
      case 'cancelled':
        return CupertinoColors.systemRed;
      default:
        return CupertinoColors.systemOrange;
    }
  }

  Widget _buildStatusChip(String status) {
    final color = _statusColor(status);
    final safeStatus = status.isEmpty ? 'status' : status;
    final label = safeStatus[0].toUpperCase() + safeStatus.substring(1);
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
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Widget _buildTimeline(String status) {
    final normalized = status.toLowerCase();
    final currentIndex = _kStatusSteps.indexOf(normalized);

    return Row(
      children: List.generate(_kStatusSteps.length, (index) {
        final step = _kStatusSteps[index];
        final isComplete = currentIndex == -1 ? false : index <= currentIndex;
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  if (index != 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: index <= currentIndex
                            ? CupertinoColors.systemBlue
                            : CupertinoColors.systemGrey4,
                      ),
                    ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isComplete ? CupertinoColors.systemBlue : Colors.white,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: isComplete
                            ? CupertinoColors.systemBlue
                            : CupertinoColors.systemGrey3,
                        width: 2,
                      ),
                    ),
                    child: isComplete
                        ? const Icon(CupertinoIcons.check_mark, size: 12, color: Colors.white)
                        : null,
                  ),
                  if (index != _kStatusSteps.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: index < currentIndex
                            ? CupertinoColors.systemBlue
                            : CupertinoColors.systemGrey4,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                step[0].toUpperCase() + step.substring(1),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isComplete ? Colors.black : Colors.black54,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildOrderCard(OrderRecord order) {
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order ${order.id}',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Placed on ${_dateFormat.format(order.createdAt)}',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.black54,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusChip(order.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            previewName + (extraCount > 0 ? ' +$extraCount more' : ''),
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.black,
              decoration: TextDecoration.none,
            ),
          ),
          if (shippingLine.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Shipping to: $shippingLine',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.black87,
                decoration: TextDecoration.none,
              ),
            ),
          ],
          const SizedBox(height: 12),
          OrderInstallmentBalanceCallout(order: order),
          const SizedBox(height: 16),
          _buildTimeline(order.status),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Paid',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.black54,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    '₱${order.totalAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
              CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                borderRadius: BorderRadius.circular(10),
                onPressed: () => _showItemsSheet(order),
                child: Text(
                  'View items',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignedOut() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.lock_shield, size: 48, color: Color(0xFFBCAAA4)),
          const SizedBox(height: 16),
          Text(
            'Sign in to track your orders.',
            style: GoogleFonts.poppins(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
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

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        if (_loading)
          const Center(child: CupertinoActivityIndicator())
        else if (user == null)
          _buildSignedOut()
        else if (_error != null)
          Column(
            children: [
              Text(
                _error!,
                style: GoogleFonts.poppins(color: Colors.black, fontSize: 16),
              ),
              const SizedBox(height: 12),
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
          )
        else if (_orders.isEmpty)
          Column(
            children: [
              const SizedBox(height: 60),
              Icon(CupertinoIcons.cube_box, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'No orders yet',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  // Explicitly clear decorations so Android's linkifier
                  // stops drawing that yellow underline.
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your order history and tracking will appear here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.black87,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          )
        else
          ..._orders.map(_buildOrderCard),
      ],
    );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: const Color(0xFF8D6E63),
        ),
        middle: Text('Orders & Tracking', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          color: CupertinoColors.systemBlue,
          onRefresh: () => _loadOrders(showLoader: false),
          child: list,
        ),
      ),
    );
  }
}




















