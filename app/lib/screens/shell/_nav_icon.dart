import 'package:flutter/cupertino.dart';

/// Small helper widget for bottom navigation icons with an optional
/// circular active background to keep the bar feeling more tactile.
class NavIcon extends StatelessWidget {
  const NavIcon({
    required this.icon,
    required this.active,
  });

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // Walnut + white combo:
    // - Active: pure white circle, walnut icon (high contrast, crisp).
    // - Inactive: soft off-white icon on transparent background.
    const walnut = Color(0xFF5C4033);
    final Color iconColor = active ? walnut : const Color(0xFFE8DED9);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: active
          ? const BoxDecoration(
              color: Color(0xFFFFFFFF),
              shape: BoxShape.circle,
            )
          : const BoxDecoration(),
      child: Icon(
        icon,
        size: 18,
        color: iconColor,
      ),
    );
  }
}

