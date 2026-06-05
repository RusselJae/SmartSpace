import 'package:flutter/cupertino.dart';

import 'models.dart';
import 'review_screen.dart';

/// Payment method selection
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.address, required this.delivery});
  final AddressData address;
  final DeliveryData delivery;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  PaymentMethod _method = PaymentMethod.gcash;

  void _next() {
    final payment = PaymentData(
      method: _method,
      cardHolder: null,
      cardNumberMasked: null,
    );
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ReviewScreen(
          address: widget.address,
          delivery: widget.delivery,
          payment: payment,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Payment')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Select a payment method'),
            const SizedBox(height: 8),
            _PaymentPill(
              label: 'GCash (Online)',
              selected: _method == PaymentMethod.gcash,
              onTap: () => setState(() => _method = PaymentMethod.gcash),
            ),
            const SizedBox(height: 8),
            _PaymentPill(
              label: 'Cash on Delivery (COD)',
              selected: _method == PaymentMethod.cod,
              onTap: () => setState(() => _method = PaymentMethod.cod),
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 8),
            CupertinoButton.filled(onPressed: _next, child: const Text('Review Order')),
          ],
        ),
      ),
    );
  }
}

class _PaymentPill extends StatelessWidget {
  const _PaymentPill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      // Light brown when inactive, normal brown when active
      color: selected ? const Color(0xFF8D6E63) : const Color(0xFFBCAAA4),
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (selected) const Icon(CupertinoIcons.check_mark)
        ],
      ),
    );
  }
}

