import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A simple, in-app guide explaining how ordering works.
///
/// This screen is intentionally written in straightforward language,
/// so users can quickly understand timelines and payment options.
class HowToOrderScreen extends StatelessWidget {
  const HowToOrderScreen({super.key});

  static const String route = '/how-to-order';

  @override
  Widget build(BuildContext context) {
    const mediumBrown = Color(0xFF8D6E63);
    const dividerColor = Color(0xFFE0D4C8);

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
        border: const Border(
          bottom: BorderSide(
            color: Color(0x338D6E63),
            width: 0.5,
          ),
        ),
        leading: CupertinoNavigationBarBackButton(
          color: mediumBrown,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        middle: Text(
          'How to Order',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: mediumBrown,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFFBF7), Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.3],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _sectionTitle('Step 1 – Browse & Choose'),
              const SizedBox(height: 6),
              _bodyText(
                'Browse our catalog of on‑hand and made‑to‑order pieces. '
                'Tap an item to view measurements, materials, finish options, and photos.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Step 2 – Customize (If Needed)'),
              const SizedBox(height: 6),
              _bodyText(
                'For made‑to‑order items, choose your size and finish options. '
                'If the app shows a notes field, add important details (special measurements, '
                'space constraints, matching existing furniture).',
              ),
              const SizedBox(height: 10),
              _bodyText(
                'Custom builds typically take 6–7 weeks. The timeline is broken down below so you know what to expect.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Step 3 – Pick a Payment Option'),
              const SizedBox(height: 6),
              _bodyText(
                'Choose the setup that fits your budget. All fees, interest, and delivery charges '
                'are shown before you confirm.',
              ),
              const SizedBox(height: 12),

              _label('1) Made to Order (Custom Items)'),
              _bullet('Down payment: ₱3,000 – ₱5,000 (non‑refundable).'),
              _bullet('Timeline: 6–7 weeks total.'),
              _bullet('Balance: payable upon delivery.'),

              const SizedBox(height: 10),
              _label('2) Installment / Lay‑Away Plan (3 Months)'),
              _bullet('Available for both on‑hand and made‑to‑order items.'),
              _bullet('Down payment: ₱3,000 – ₱5,000.'),
              _bullet('0% interest if fully paid within 3 months.'),
              _bullet('Requirement: 1 valid ID.'),
              _bullet('Delivery: item will be delivered once fully paid.'),
              _bullet('Late payment: if unpaid after 3 months, a warehouse fee of ₱100/day applies until fully paid.'),

              const SizedBox(height: 10),
              _label('3) On‑Hand Installment (Quick Delivery)'),
              _bullet('Down payment: 40% upfront.'),
              _bullet('Interest: 6% total interest.'),
              _bullet('Delivery: 10–12 days (delivery fees apply).'),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Step 4 – Confirm & Pay'),
              const SizedBox(height: 6),
              _bodyText(
                'Review your address and order details, then confirm your order. '
                'Once payment is confirmed, you’ll see your Order ID and status updates inside the app.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Production Timeline (Made to Order)'),
              const SizedBox(height: 6),
              _bullet('Week 1: wood treatment (anti‑pest / anti‑termite).'),
              _bullet('Weeks 2–6: item production.'),
              _bullet('Week 7: refurbishing and delivery scheduling.'),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Quality & Security Guarantee'),
              const SizedBox(height: 6),
              _bullet('Quality assurance: every item goes through a quality check before release.'),
              _bullet(
                'Secure transactions: you’re welcome to visit our shop for walk‑in viewing, '
                'or request a video call with our staff to inspect items before sending your down payment.',
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _sectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF8D6E63),
      ),
    );
  }

  static Widget _bodyText(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 14,
        color: Colors.black87,
        height: 1.4,
      ),
    );
  }

  static Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  static Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 14, height: 1.4)),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

