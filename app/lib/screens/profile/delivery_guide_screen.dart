import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Delivery Guide – what to prepare, what happens on delivery day, and how to reschedule.
class DeliveryGuideScreen extends StatelessWidget {
  const DeliveryGuideScreen({super.key});

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
          'Delivery & Scheduling',
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
              _sectionTitle('Before delivery day'),
              const SizedBox(height: 6),
              _bullet('Confirm your address details and contact number.'),
              _bullet('Measure doors, hallways, stairs, and tight corners.'),
              _bullet('Clear a path (remove rugs, fragile decor, small tables).'),
              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('On delivery day'),
              const SizedBox(height: 6),
              _bullet('Keep your phone reachable—drivers may call for directions.'),
              _bullet('Check the item condition before final acceptance.'),
              _bullet('If something is wrong, take clear photos and message support immediately.'),
              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Rescheduling'),
              const SizedBox(height: 6),
              _bodyText(
                'Plans change. If you need to move the schedule, message support as early as possible '
                'and include your Order ID.',
              ),
              const SizedBox(height: 8),
              _bullet('Tell us the preferred new date/time window.'),
              _bullet('If access is tricky (gated community / narrow stairs), mention it.'),
              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Common questions'),
              const SizedBox(height: 6),
              _bullet('“Can you deliver upstairs?” — message us with floor level + stair width.'),
              _bullet('“Can you call before arriving?” — yes, just request it in chat.'),
              _bullet('“I entered the wrong address.” — send the corrected address ASAP.'),
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

