import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Payments Guide – what to check before paying and what happens after.
///
/// Why a dedicated screen:
/// - This avoids modal “walls of text”.
/// - It keeps the Help Center as a clean menu, with details living one level deeper.
class PaymentsGuideScreen extends StatelessWidget {
  const PaymentsGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const mediumBrown = Color(0xFF8D6E63);
    const dividerColor = Color(0xFFE0D4C8);

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFFF4E6D4),
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
          'Payments & Reservations',
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
              _sectionTitle('Before you pay'),
              const SizedBox(height: 6),
              _bullet('Double-check your delivery address and contact number.'),
              _bullet('Review the order summary (item, quantity, total, fees).'),
              _bullet('If something looks off, message support before sending payment.'),
              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Reservations / down payments'),
              const SizedBox(height: 6),
              _bodyText(
                'If an item is made-to-order or has limited stock, you may be asked for a down payment to reserve it.',
              ),
              const SizedBox(height: 8),
              _bullet('A reservation confirms the build/hold for your order.'),
              _bullet('Keep your receipt or proof of payment ready.'),
              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('After payment'),
              const SizedBox(height: 6),
              _bullet('You’ll see your Order ID and status in the app once confirmed.'),
              _bullet('We may contact you to confirm details (address, schedule, special notes).'),
              _bullet('For updates, use Support Chat—fastest route to the team.'),
              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Quick fixes'),
              const SizedBox(height: 6),
              _bullet('No confirmation yet? Check your connection, then refresh later.'),
              _bullet('Wrong details? Send a message with your Order ID and what to change.'),
              _bullet('Need to cancel? Contact support as soon as possible.'),
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

