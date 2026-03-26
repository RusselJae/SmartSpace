import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
        case PaymentMethod.gcash:
          return 'GCash (Online)';
        case PaymentMethod.cod:
          return 'Cash on Delivery (COD)';
        case PaymentMethod.paymongo:
          return 'PayMongo (Test)';
      }
    }();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('Review Order', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Items (placeholder)', style: GoogleFonts.poppins(fontSize: 16)),
            const SizedBox(height: 12),
            Text(
              'Deliver to: ${address.fullName}, ${address.addressLine1}, ${address.city} ${address.postalCode}',
              style: GoogleFonts.poppins(fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Delivery: ${delivery.dateLabel} ${delivery.slotLabel}',
              style: GoogleFonts.poppins(fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Payment: $paymentLabel',
              style: GoogleFonts.poppins(fontSize: 15),
            ),
            const SizedBox(height: 24),
            Text(
              'Order Summary (placeholder):',
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Subtotal: ₱899',
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
            Text(
              'Shipping: ₱20',
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
            Text(
              'Total: ₱919',
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: () => _placeOrder(context),
              child: Text('Place Order', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}


