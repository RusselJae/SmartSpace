import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../support/support_chat_screen.dart';
import 'ar_guide_screen.dart';
import 'delivery_guide_screen.dart';
import 'how_to_order_screen.dart';
import 'payments_guide_screen.dart';

/// Help Center screen – support + guides.
///
/// Intent:
/// - Keep “contact support” one tap away.
/// - Provide short, task-based guides (AR preview, payments, delivery) as full screens
///   so the flow feels consistent with the rest of the app’s navigation.
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const lightBrown = Color(0xFFF4E6D4);
    const mediumBrown = Color(0xFF8D6E63);

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: lightBrown,
        border: Border(
          bottom: BorderSide(
            color: mediumBrown.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: mediumBrown,
        ),
        middle: Text(
          'Help Center',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: mediumBrown,
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Text(
                'Support',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 4),
            _HelpTile(
              icon: CupertinoIcons.headphones,
              title: 'Chat with Support',
              onTap: () {
                Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute(
                    builder: (_) => const SupportChatScreen(),
                  ),
                );
              },
              subtitle: 'Get quick help from the team.',
            ),
            _HelpTile(
              icon: CupertinoIcons.book,
              title: 'How Ordering Works',
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => const HowToOrderScreen(),
                  ),
                );
              },
              subtitle: 'Step‑by‑step guide from cart to delivery.',
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Text(
                'Guides & Tips',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 4),
            _HelpTile(
              icon: CupertinoIcons.cube_box,
              title: 'Using AR to Preview Furniture',
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => const ArGuideScreen(),
                  ),
                );
              },
              subtitle: 'See how pieces fit in your actual space.',
            ),
            _HelpTile(
              icon: CupertinoIcons.creditcard,
              title: 'Payments & Reservations',
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => const PaymentsGuideScreen(),
                  ),
                );
              },
              subtitle: 'How payments, proof, and confirmations work.',
            ),
            _HelpTile(
              icon: CupertinoIcons.car_detailed,
              title: 'Delivery & Scheduling',
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => const DeliveryGuideScreen(),
                  ),
                );
              },
              subtitle: 'What to prepare before your order arrives.',
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Help Center list tile, styled to mirror the Settings screen tiles so the
/// experience feels consistent across Account / Legal / Help sections.
class _HelpTile extends StatelessWidget {
  const _HelpTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFBCAAA4).withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onPressed: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF8D6E63).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: const Color(0xFF8D6E63)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_forward,
              size: 14,
              color: Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}

