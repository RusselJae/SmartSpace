import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/order_record.dart';
import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../../widgets/toast.dart';
import '../../widgets/order_installment_balance_callout.dart';
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
        if (paymentStatus == 'confirmed' ||
            paymentStatus == 'completed' ||
            paymentStatus == 'downpayment_paid') {
          return false;
        }
        
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

    final remRaw = order.shippingAddress['remainingBalance'];
    double? remaining;
    if (remRaw is num) {
      remaining = remRaw.toDouble();
    } else if (remRaw is String) {
      remaining = double.tryParse(remRaw);
    }

    if (paymentMethod == 'cod') {
      return downpayment ?? (totalAmount * 0.20);
    }
    if (paymentMethod == 'paymongo') {
      final ps = order.shippingAddress['paymentStatus']?.toString();
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

  /// PayMongo opens hosted checkout; COD/GCash use manual proof screen.
  Future<void> _openPaymentForOrder(OrderRecord order) async {
    final pm = order.shippingAddress['paymentMethod']?.toString();
    if (pm == 'paymongo') {
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted) Toast.error(context, 'Please sign in');
        return;
      }
      try {
        final maxPayable = _getPaymentAmount(order);
        final selectedAmount = await _promptForPaymongoAmount(maxPesos: maxPayable);
        if (selectedAmount == null) {
          if (mounted) Toast.info(context, 'Payment cancelled');
          return;
        }
        final url = await _db.createPaymongoCheckoutSession(
          orderId: order.id,
          userId: user.id,
          amountPesos: selectedAmount,
        );
        if (!mounted) return;
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (mounted) Toast.info(context, 'Complete payment in the browser');
      } catch (e) {
        if (mounted) Toast.error(context, 'PayMongo: $e');
      }
      await _loadPendingOrders();
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
    await _loadPendingOrders();
  }

  /// Let users choose a custom amount during pay-again.
  /// This keeps the amount between 0 and the currently payable ceiling.
  Future<double?> _promptForPaymongoAmount({required double maxPesos}) async {
    final safeMax = maxPesos > 0.01 ? maxPesos : 1.0;
    final controller = TextEditingController(text: safeMax.toStringAsFixed(2));

    final result = await showCupertinoDialog<double>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(
          'Enter amount to pay',
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
                border: Border.all(
                  color: const Color(0xFF8D6E63).withValues(alpha: 0.30),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Max: ₱${safeMax.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8D6E63),
              ),
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
              final clamped = parsed > safeMax ? safeMax : parsed;
              Navigator.pop(ctx, clamped);
            },
            child: Text(
              'Continue',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF8D6E63),
              ),
            ),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
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
                                                'Pay next: ₱${_getPaymentAmount(order).toStringAsFixed(2)}',
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
                                                : _getPaymentMethod(order) == PaymentMethod.paymongo
                                                    ? 'PayMongo'
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
                                    OrderInstallmentBalanceCallout(
                                      order: order,
                                      accentColor: const Color(0xFF5C4033),
                                    ),
                                    const SizedBox(height: 12),
                                    CupertinoButton.filled(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      onPressed: () => _openPaymentForOrder(order),
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

