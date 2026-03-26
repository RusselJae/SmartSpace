import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import 'change_password_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_and_conditions_screen.dart';

/// A hub screen that groups security and privacy actions.
///
/// Some items are actionable today (Change Password, policies).
/// Others are intentionally "planned" and can be implemented later without changing the layout.
class SecurityPrivacyScreen extends StatelessWidget {
  const SecurityPrivacyScreen({super.key});

  static const String route = '/security-privacy';

  void _showPlanned(BuildContext context, String title) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            'This option is planned. If you want it prioritized, tell us what you need and we’ll build it.',
            style: GoogleFonts.poppins(),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
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
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ),
            const Icon(CupertinoIcons.chevron_forward, size: 14, color: Colors.black38),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const lightBrown = Color(0xFFF4E6D4);
    const mediumBrown = Color(0xFF8D6E63);

    final auth = AuthService();
    final signedIn = auth.isAuthenticated;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: lightBrown,
        border: Border(
          bottom: BorderSide(color: mediumBrown.withValues(alpha: 0.2), width: 0.5),
        ),
        leading: CupertinoNavigationBarBackButton(
          color: mediumBrown,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        middle: Text(
          'Security & Privacy',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: mediumBrown),
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Text(
                'Security',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 4),
            _tile(
              context: context,
              icon: CupertinoIcons.lock_rotation,
              title: 'Change Password',
              onTap: () {
                if (!signedIn) {
                  _showPlanned(context, 'Sign in required');
                  return;
                }
                Navigator.of(context).push(
                  CupertinoPageRoute(builder: (_) => const ChangePasswordScreen()),
                );
              },
            ),
            _tile(
              context: context,
              icon: CupertinoIcons.shield,
              title: 'Sign out of all devices (planned)',
              onTap: () => _showPlanned(context, 'Sign out of all devices'),
            ),
            _tile(
              context: context,
              icon: CupertinoIcons.bell,
              title: 'Login alerts (planned)',
              onTap: () => _showPlanned(context, 'Login alerts'),
            ),

            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Text(
                'Privacy',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 4),
            _tile(
              context: context,
              icon: CupertinoIcons.hand_raised,
              title: 'Privacy Policy',
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute(builder: (_) => const PrivacyPolicyScreen()),
              ),
            ),
            _tile(
              context: context,
              icon: CupertinoIcons.doc_text,
              title: 'Terms & Conditions',
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute(builder: (_) => const TermsAndConditionsScreen()),
              ),
            ),
            _tile(
              context: context,
              icon: CupertinoIcons.trash,
              title: 'Delete account (planned)',
              onTap: () => _showPlanned(context, 'Delete account'),
            ),
          ],
        ),
      ),
    );
  }
}

