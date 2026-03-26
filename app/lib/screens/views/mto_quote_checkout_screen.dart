import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/app_settings.dart';
import '../../models/made_to_order_request.dart';
import '../../services/app_settings_service.dart';
import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../../widgets/toast.dart';

/// After admin quotes, customer confirms shipping and creates the PayMongo order.
class MtoQuoteCheckoutScreen extends StatefulWidget {
  const MtoQuoteCheckoutScreen({super.key, required this.request});

  final MadeToOrderRequest request;

  @override
  State<MtoQuoteCheckoutScreen> createState() => _MtoQuoteCheckoutScreenState();
}

class _MtoQuoteCheckoutScreenState extends State<MtoQuoteCheckoutScreen> {
  static const Color _kWalnut = Color(0xFF5C4033);
  static const Color _kWalnutDeep = Color(0xFF3E2723);
  static const Color _kWalnutSoftBg = Color(0xFFEFE8E3);

  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AuthService _auth = AuthService();
  final AppSettingsService _settingsService = AppSettingsService();
  AppSettings? _settings;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _line1 = TextEditingController();
  final _city = TextEditingController();
  final _postal = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _line1.dispose();
    _city.dispose();
    _postal.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final u = _auth.currentUser;
    if (u != null) {
      _name.text = u.fullName;
    }
    _primeSettings();
    _city.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _primeSettings() async {
    try {
      final settings = await _settingsService.loadSettings();
      if (!mounted) return;
      setState(() => _settings = settings);
    } catch (_) {
      // Non-fatal: fallback to defaults.
    }
  }

  double _calculateShippingFee() {
    final settings = _settings ?? const AppSettings();

    // For made-to-order checkout we treat this as a single shipped item.
    const productCount = 1;
    if (productCount >= settings.freeShippingProductCount) {
      return 0.0;
    }

    final city = _city.text.trim().toLowerCase();
    for (final freeCity in settings.freeShippingCities) {
      if (city.contains(freeCity.toLowerCase())) {
        return 0.0;
      }
    }

    for (final entry in settings.specialShippingCities.entries) {
      if (city.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }

    final baseFee = settings.defaultShippingFeeBase;
    final maxFee = settings.defaultShippingFeeMax;
    final distanceMultiplier = (city.length / 10).clamp(0.0, 1.0);
    final additionalFee = distanceMultiplier * (maxFee - baseFee);
    return (baseFee + additionalFee).clamp(baseFee, maxFee);
  }

  Future<void> _submit() async {
    final user = _auth.currentUser;
    if (user == null) {
      Toast.error(context, 'Please sign in');
      return;
    }
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final line1 = _line1.text.trim();
    final city = _city.text.trim();
    final postal = _postal.text.trim();
    final ship = _calculateShippingFee();

    if (name.isEmpty || phone.isEmpty || line1.isEmpty || city.isEmpty) {
      Toast.error(context, 'Fill in name, phone, address line, and city');
      return;
    }

    final q = widget.request;
    final total = q.quotedTotal;
    final dp = q.quotedDownpayment;
    final remaining = q.quotedRemaining ??
        (total != null && dp != null
            ? double.parse((total - dp).toStringAsFixed(2))
            : null);
    if (total == null || dp == null || remaining == null) {
      Toast.error(context, 'This quote is incomplete. Contact support.');
      return;
    }
    if (total - ship < -0.01) {
      Toast.error(context, 'Shipping fee cannot exceed quoted total.');
      return;
    }

    setState(() => _loading = true);
    try {
      final shippingAddress = <String, dynamic>{
        'name': name,
        'phone': phone,
        'line1': line1,
        'line2': '',
        'city': city,
        'postalCode': postal,
        'label': 'Home',
        'shippingFee': ship,
        'paymentMethod': 'paymongo',
        'paymentPlan': 'downpayment',
        'orderOption': 'layaway',
        'downpayment': dp,
        'remainingBalance': remaining,
        'merchandiseSubtotal': total - ship,
      };

      final order = await _db.createOrderFromQuotedMadeToOrderRequest(
        requestId: q.id,
        userId: user.id,
        shippingAddress: shippingAddress,
      );

      final updatedOrders = [...user.orderIds];
      if (!updatedOrders.contains(order.id)) {
        updatedOrders.add(order.id);
      }
      await _auth.updateCurrentUser(user.copyWith(orderIds: updatedOrders));

      if (!mounted) return;
      Toast.success(context, 'Opening PayMongo checkout');

      final checkoutUrl = await _db.createPaymongoCheckoutSession(
        orderId: order.id,
        userId: user.id,
      );
      if (!mounted) return;
      final uri = Uri.parse(checkoutUrl);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (opened) {
        Navigator.of(context).pop();
      } else {
        Toast.warning(context, 'Could not open browser');
      }
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(String label, TextEditingController c, {TextInputType? keyboard}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: _kWalnutDeep),
        ),
        const SizedBox(height: 6),
        CupertinoTextField(
          controller: c,
          keyboardType: keyboard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
          placeholder: label,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kWalnut.withValues(alpha: 0.22)),
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kWalnut.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: _kWalnutDeep,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
              color: _kWalnutDeep,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.request;
    final remaining = q.quotedRemaining ??
        (q.quotedTotal != null && q.quotedDownpayment != null
            ? double.parse((q.quotedTotal! - q.quotedDownpayment!).toStringAsFixed(2))
            : null);
    final ship = _calculateShippingFee();
    final total = q.quotedTotal;
    final dp = q.quotedDownpayment;
    final merch = (total != null) ? (total - ship) : null;
    return CupertinoPageScaffold(
      backgroundColor: _kWalnutSoftBg,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: _kWalnut,
        ),
        middle: Text(
          'Checkout',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: _kWalnutDeep),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionCard(
              title: 'CUSTOM REQUEST',
              children: [
                Text(
                  q.itemName,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _kWalnutDeep,
                  ),
                ),
                const SizedBox(height: 10),
                if (total != null && dp != null && remaining != null) ...[
                  _summaryRow('Merchandise', merch == null ? '—' : '₱${merch.toStringAsFixed(2)}'),
                  _summaryRow('Shipping fee', '₱${ship.toStringAsFixed(2)}'),
                  const Divider(height: 18),
                  _summaryRow('Total', '₱${total.toStringAsFixed(2)}', strong: true),
                  _summaryRow('Pay now (downpayment)', '₱${dp.toStringAsFixed(2)}', strong: true),
                  _summaryRow('Later', '₱${remaining.toStringAsFixed(2)}'),
                  const SizedBox(height: 4),
                  Text(
                    ship == 0 ? 'Shipping is free for your location.' : 'Shipping fee is calculated from your city.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      height: 1.35,
                      color: Colors.grey[600],
                    ),
                  ),
                ] else ...[
                  Text(
                    'Quote totals are missing. Please contact support.',
                    style: GoogleFonts.poppins(fontSize: 13, color: CupertinoColors.systemRed),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _sectionCard(
              title: 'DELIVERY ADDRESS',
              children: [
                _field('Full name', _name),
                const SizedBox(height: 10),
                _field('Phone', _phone, keyboard: TextInputType.phone),
                const SizedBox(height: 10),
                _field('Address line (block, street, barangay)', _line1),
                const SizedBox(height: 10),
                _field('City / region', _city),
                const SizedBox(height: 10),
                _field('Postal code', _postal),
              ],
            ),
            const SizedBox(height: 16),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _loading ? null : _submit,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: _loading ? CupertinoColors.systemGrey : _kWalnut,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _loading ? 'Working…' : 'Create order & pay deposit',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Tip: pick the correct city — it changes the shipping fee.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
