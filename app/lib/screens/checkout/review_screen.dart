import 'package:flutter/cupertino.dart';

import 'models.dart';
import 'success_screen.dart';

/// Order review summary
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({
    super.key,
    required this.address,
    required this.delivery,
    required this.payment,
  });

  final AddressData address;
  final DeliveryData delivery;
  final PaymentData payment;

  void _placeOrder(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      CupertinoPageRoute(builder: (_) => const SuccessScreen()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final paymentLabel = () {
      switch (payment.method) {
        case PaymentMethod.card:
          return 'Card ${payment.cardNumberMasked ?? ''}'.trim();
        case PaymentMethod.paypal:
          return 'PayPal';
        case PaymentMethod.cod:
          return 'Cash on Delivery';
      }
    }();

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Review Order')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Items (placeholder)'),
            const SizedBox(height: 12),
            Text('Deliver to: ${address.fullName}, ${address.addressLine1}, ${address.city} ${address.postalCode}'),
            const SizedBox(height: 6),
            Text('Delivery: ${delivery.dateLabel} ${delivery.slotLabel}'),
            const SizedBox(height: 6),
            Text('Payment: $paymentLabel'),
            const SizedBox(height: 24),
            const Text('Order Summary (placeholder):'),
            const SizedBox(height: 6),
            const Text('Subtotal: \$899'),
            const Text('Shipping: \$20'),
            const Text('Total: \$919'),
            const SizedBox(height: 24),
            CupertinoButton.filled(onPressed: () => _placeOrder(context), child: const Text('Place Order')),
          ],
        ),
      ),
    );
  }
}


