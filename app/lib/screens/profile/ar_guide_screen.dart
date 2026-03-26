import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AR Guide – practical, step-by-step instructions for placing models in space.
///
/// Notes:
/// - We keep this screen purely informational (no deep links) so it won’t break
///   if AR entry points evolve later.
/// - The tone stays confident and direct: short steps, no fluff.
class ArGuideScreen extends StatelessWidget {
  const ArGuideScreen({super.key});

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
          'AR Preview Guide',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: mediumBrown,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: DecoratedBox(
          // Subtle top highlight keeps the page feeling “lifted” like iOS cards.
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
              _sectionTitle('Before you start'),
              const SizedBox(height: 6),
              _bodyText(
                'Use AR in a bright room, point your camera at the floor, and move slowly. '
                'AR needs texture and light to “lock” the surface.',
              ),
              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Place the model'),
              const SizedBox(height: 6),
              _bullet('Open a product that supports AR.'),
              _bullet('Tap the AR / “View in your space” button.'),
              _bullet('Move your phone left-right to scan until the placement indicator appears.'),
              _bullet('Tap to drop the furniture on the floor.'),
              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Adjust it (gestures)'),
              const SizedBox(height: 6),
              _bullet('Two fingers: rotate the model.'),
              _bullet('Pinch: resize (keep it realistic—don’t “cheat” the size).'),
              _bullet('Drag: reposition if it lands too close/far.'),
              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('Pro tips (fit check)'),
              const SizedBox(height: 6),
              _bullet('Walk around it. Check doors, drawers, and walking paths.'),
              _bullet('Compare height with nearby furniture (tables, counters, headboards).'),
              _bullet('Leave space for outlets, curtains, and wall trim.'),
              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('If AR looks wrong'),
              const SizedBox(height: 6),
              _bullet('Too jumpy? Add more light and avoid shiny floors.'),
              _bullet('Model floating? Scan longer and keep the phone steady.'),
              _bullet('Scale feels off? Re-place the model, then resize carefully.'),
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

