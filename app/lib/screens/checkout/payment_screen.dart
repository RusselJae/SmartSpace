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
  PaymentMethod _method = PaymentMethod.card;

  final TextEditingController _cardHolder = TextEditingController();
  final TextEditingController _cardNumber = TextEditingController();

  void _next() {
    final masked = _cardNumber.text.isEmpty
        ? null
        : '**** **** **** ${_cardNumber.text.substring(_cardNumber.text.length - 4)}';
    final payment = PaymentData(
      method: _method,
      cardHolder: _cardHolder.text.isEmpty ? null : _cardHolder.text,
      cardNumberMasked: masked,
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
              label: 'Credit/Debit Card',
              selected: _method == PaymentMethod.card,
              onTap: () => setState(() => _method = PaymentMethod.card),
            ),
            const SizedBox(height: 8),
            _PaymentPill(
              label: 'PayPal',
              selected: _method == PaymentMethod.paypal,
              onTap: () => setState(() => _method = PaymentMethod.paypal),
            ),
            const SizedBox(height: 8),
            _PaymentPill(
              label: 'Cash on Delivery',
              selected: _method == PaymentMethod.cod,
              onTap: () => setState(() => _method = PaymentMethod.cod),
            ),
            const SizedBox(height: 16),
            if (_method == PaymentMethod.card) ...[
              _CupertinoField(controller: _cardHolder, placeholder: 'Cardholder name'),
              const SizedBox(height: 12),
              _CupertinoField(controller: _cardNumber, placeholder: 'Card number'),
              const SizedBox(height: 12),
            ],
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
      color: selected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey5,
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

class _CupertinoField extends StatelessWidget {
  const _CupertinoField({required this.controller, required this.placeholder});
  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: CupertinoTextField(
        controller: controller,
        placeholder: placeholder,
        decoration: null,
      ),
    );
  }
}


