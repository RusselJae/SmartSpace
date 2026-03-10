import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Simple settings screen placeholder for user account actions.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showComingSoon(BuildContext context, String title) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(
          title,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            'This feature will be available soon.',
            style: GoogleFonts.poppins(),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
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
          color: mediumBrown,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        middle: Text(
          'Settings',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: mediumBrown,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Text(
                'Account',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 4),
            _buildTile(
              icon: CupertinoIcons.lock,
              title: 'Change Password',
              onTap: () => _showComingSoon(context, 'Change Password'),
            ),
            _buildTile(
              icon: CupertinoIcons.person_crop_circle_badge_checkmark,
              title: 'Security & Privacy',
              onTap: () => _showComingSoon(context, 'Security & Privacy'),
            ),
          ],
        ),
      ),
    );
  }
}







