import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/order_record.dart';
import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../checkout/models.dart';
import '../checkout/payment_confirmation_screen.dart';

/// Screen showing orders that need payment confirmation
class PendingPaymentOrdersScreen extends StatefulWidget {
  const PendingPaymentOrdersScreen({super.key});

  @override
  State<PendingPaymentOrdersScreen> createState() => _PendingPaymentOrdersScreenState();
}

class _PendingPaymentOrdersScreenState extends State<PendingPaymentOrdersScreen> {
  final AuthService _auth = AuthService();
  final MySQLDatabaseService _db = MySQLDatabaseService();
  
  List<OrderRecord> _pendingOrders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPendingOrders();
  }

  Future<void> _loadPendingOrders() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _pendingOrders = [];
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final allOrders = await _db.getAllOrders();
      
      // Filter orders that need payment:
      // 1. Status is 'pending' or 'pending_payment_verification'
      // 2. Belongs to current user
      // 3. Payment status is not 'confirmed' or 'downpayment_paid'
      final pending = allOrders.where((order) {
        if (order.userId != user.id) return false;
        if (order.status == 'cancelled' || order.status == 'confirmed') return false;
        
        final paymentStatus = order.shippingAddress['paymentStatus'] as String?;
        if (paymentStatus == 'confirmed' || paymentStatus == 'downpayment_paid') return false;
        
        return true;
      }).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _pendingOrders = pending;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      developer.log('Error loading pending orders: $e', name: 'PendingPaymentOrders');
      setState(() {
        _error = 'Failed to load pending orders: $e';
        _loading = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: const Color(0xFF8D6E63),
        ),
        middle: Text(
          'Complete Payment',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _error != null
                ? Center(
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
                              fontSize: 16,
                              color: Colors.black,
                              decoration: TextDecoration.none,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          CupertinoButton.filled(
                            onPressed: _loadPendingOrders,
                            child: Text(
                              'Retry',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _pendingOrders.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                CupertinoIcons.check_mark_circled_solid,
                                size: 64,
                                color: CupertinoColors.activeGreen,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Pending Payments',
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                  decoration: TextDecoration.none,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'All your orders are paid or confirmed.',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: CupertinoColors.systemGrey,
                                  decoration: TextDecoration.none,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(
                            'Complete payment for these orders:',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ..._pendingOrders.map((order) => Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: CupertinoColors.secondarySystemGroupedBackground,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Order #${order.id.substring(0, 8).toUpperCase()}',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.black,
                                                  decoration: TextDecoration.none,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Amount: ₱${_getPaymentAmount(order).toStringAsFixed(2)}',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  color: const Color(0xFFFF9800),
                                                  decoration: TextDecoration.none,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF3E0),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            _getPaymentMethod(order) == PaymentMethod.cod
                                                ? 'COD (20%)'
                                                : 'GCash (Full)',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFFE65100),
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    CupertinoButton.filled(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      onPressed: () {
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
                                          // Reload pending orders after returning
                                          _loadPendingOrders();
                                        });
                                      },
                                      child: Text(
                                        'Complete Payment',
                                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
      ),
    );
  }
}

