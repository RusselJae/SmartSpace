import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/mysql_database_service.dart';
import '../../widgets/legal_content_renderer.dart';

/// Privacy Policy screen (separate from Terms & Conditions).
///
/// Loads content from the backend when available. Falls back to built-in
/// default when no custom content is set.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  static const String route = '/privacy-policy';

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  String? _customContent;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      await _db.initialize();
      final content = await _db.getLegalContent('privacy');
      if (!mounted) return;
      setState(() {
        _customContent = (content != null && content.trim().isNotEmpty) ? content : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

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
          'Privacy Policy',
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
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _customContent != null
                  ? LegalContentRenderer(
                      content: _customContent!,
                      dividerColor: dividerColor,
                    )
                  : ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _sectionTitle('1. Scope'),
              const SizedBox(height: 6),
              _bodyText(
                'This Privacy Policy explains how SmartSpace collects, uses, stores, and shares personal information '
                'when you use the SmartSpace app and related services (collectively, the “Service”).',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('2. Information We Collect'),
              const SizedBox(height: 6),
              _bullet('Account details such as full name, email address, username, and phone number (if provided).'),
              _bullet('Profile information such as avatar and preferences you submit in the app.'),
              _bullet('Order, cart, and wishlist activity (items, quantities, pricing, timestamps).'),
              _bullet('Delivery information such as address details you save for checkout.'),
              _bullet('Support messages you send through in‑app support (if enabled).'),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('3. How We Use Your Information'),
              const SizedBox(height: 6),
              _bullet('To create and manage your account, verify your email, and maintain your session.'),
              _bullet('To process orders, manage payments, schedule deliveries, and provide order updates.'),
              _bullet('To provide customer support and resolve disputes or issues.'),
              _bullet('To improve product listings, app performance, and user experience.'),
              _bullet('To help detect, prevent, and respond to fraud, abuse, or security incidents.'),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('4. Sharing of Information'),
              const SizedBox(height: 6),
              _bodyText(
                'We do not sell your personal information. We may share limited information only when necessary to provide the Service, including:',
              ),
              const SizedBox(height: 6),
              _bullet('Logistics and delivery providers, strictly for delivery coordination.'),
              _bullet('Payment processors or proof‑of‑payment handling, where applicable.'),
              _bullet('Service providers that support app infrastructure (hosting, storage), subject to confidentiality obligations.'),
              _bullet('Legal and regulatory authorities when required by law, court order, or to protect rights and safety.'),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('5. Data Retention'),
              const SizedBox(height: 6),
              _bodyText(
                'We retain personal information only as long as necessary for the purposes described in this Policy, including to comply with legal obligations, '
                'resolve disputes, and enforce agreements. Retention periods may vary based on record type and operational requirements.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('6. Security'),
              const SizedBox(height: 6),
              _bodyText(
                'We implement reasonable administrative, technical, and organizational safeguards designed to protect personal information. '
                'However, no method of transmission or storage is completely secure. You are responsible for keeping your account credentials confidential.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('7. Your Choices'),
              const SizedBox(height: 6),
              _bullet('You may update your profile details within the app.'),
              _bullet('You may change your password from Settings.'),
              _bullet('You may request support for account‑related questions through the app’s support channels.'),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('8. Changes to This Policy'),
              const SizedBox(height: 6),
              _bodyText(
                'We may update this Privacy Policy from time to time. Any updates will be posted in the app. '
                'Your continued use of the Service after changes become effective means you accept the updated Policy.',
              ),

              const SizedBox(height: 18),
              const Divider(color: dividerColor, height: 24),

              _sectionTitle('9. Contact'),
              const SizedBox(height: 6),
              _bodyText(
                'If you have questions about this Privacy Policy or how your information is handled, contact SmartSpace through the in‑app support page.',
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
