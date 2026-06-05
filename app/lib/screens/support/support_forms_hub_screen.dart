import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../../support/support_form_catalog.dart';
import '../../widgets/toast.dart';
import 'support_form_fill_screen.dart';

/// Lists intake forms customers can fill (self-serve or via staff link).
class SupportFormsHubScreen extends StatefulWidget {
  const SupportFormsHubScreen({super.key});

  static const String route = '/support/forms';

  @override
  State<SupportFormsHubScreen> createState() => _SupportFormsHubScreenState();
}

class _SupportFormsHubScreenState extends State<SupportFormsHubScreen> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AuthService _auth = AuthService();
  bool _starting = false;

  Future<void> _openForm(SupportFormDef def) async {
    if (!_auth.isAuthenticated) {
      Toast.info(context, 'Sign in to submit a support form');
      return;
    }
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _starting = true);
    try {
      await _db.initialize();
      final request = await _db.createSupportFormRequest(
        userId: user.id,
        email: user.email,
        formType: def.type,
      );
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute<void>(
          builder: (_) => SupportFormFillScreen(
            formType: def.type,
            requestId: request.id,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Could not open form: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const mediumBrown = Color(0xFF8D6E63);

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFFF4E6D4),
        middle: Text(
          'Support Forms',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: mediumBrown),
        ),
      ),
      child: SafeArea(
        child: _starting
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text(
                    'Structured requests help our team respond faster. Pick a form — you can still chat anytime.',
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  ...kSupportFormCatalog.map(
                    (def) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _openForm(def),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: mediumBrown.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(CupertinoIcons.doc_text, color: mediumBrown),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        def.title,
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        def.description,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Colors.black54,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(CupertinoIcons.chevron_right, color: Colors.black38, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
