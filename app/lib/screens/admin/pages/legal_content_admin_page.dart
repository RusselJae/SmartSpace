import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/admin_auth_service.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';
import '../../../widgets/toast.dart';

/// Admin page for editing Terms & Conditions and Privacy Policy.
///
/// Content uses a simple format:
/// - `## Section Title` – section header
/// - `**Label**` – bold sublabel
/// - `- Bullet point` – bullet item
/// - Plain text – body paragraph
///
/// When no custom content is saved, the app shows its built-in default.
class LegalContentAdminPage extends StatefulWidget {
  const LegalContentAdminPage({super.key});

  @override
  State<LegalContentAdminPage> createState() => _LegalContentAdminPageState();
}

class _LegalContentAdminPageState extends State<LegalContentAdminPage>
    with SingleTickerProviderStateMixin {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AdminAuthService _adminAuth = AdminAuthService();

  late TabController _tabController;
  final TextEditingController _termsController = TextEditingController();
  final TextEditingController _privacyController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadContent();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _termsController.dispose();
    _privacyController.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _db.initialize();
      final terms = await _db.getLegalContent('terms');
      final privacy = await _db.getLegalContent('privacy');
      if (!mounted) return;
      _termsController.text = terms ?? '';
      _privacyController.text = privacy ?? '';
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load: $e';
      });
    }
  }

  Future<void> _save() async {
    final adminId = _adminAuth.currentAdminId;
    if (adminId == null) {
      Toast.error(context, 'Admin session expired. Please sign in again.');
      return;
    }

    setState(() => _saving = true);
    try {
      final key = _tabController.index == 0 ? 'terms' : 'privacy';
      final content =
          _tabController.index == 0
              ? _termsController.text
              : _privacyController.text;

      await _db.updateLegalContent(
        adminId: adminId,
        key: key,
        content: content,
      );
      if (!mounted) return;
      Toast.success(
        context,
        key == 'terms'
            ? 'Terms & Conditions saved'
            : 'Privacy Policy saved',
      );
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToolbar(
          title: 'Legal Content',
          actions: const [],
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _loadContent,
                tooltip: 'Refresh',
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: (_loading || _saving) ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(_saving ? 'Saving...' : 'Save'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8D6E63),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF8D6E63),
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: const Color(0xFF8D6E63),
          tabs: const [
            Tab(text: 'Terms & Conditions'),
            Tab(text: 'Privacy Policy'),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _EditorPanel(
                      controller: _termsController,
                      hint:
                          'Use ## for section titles, - for bullets, **text** for labels.\n\n'
                          'Example:\n'
                          '## 1. Scope\n'
                          'This policy explains...\n\n'
                          '- First bullet\n'
                          '- Second bullet',
                    ),
                    _EditorPanel(
                      controller: _privacyController,
                      hint:
                          'Use ## for section titles, - for bullets, **text** for labels.',
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EditorPanel extends StatelessWidget {
  const _EditorPanel({
    required this.controller,
    required this.hint,
  });

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: TextField(
        controller: controller,
        maxLines: null,
        minLines: 20,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.poppins(
            fontSize: 13,
            color: Colors.grey[500],
          ),
          filled: true,
          fillColor: const Color(0xFFFAFAFA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF8D6E63), width: 2),
          ),
          contentPadding: const EdgeInsets.all(16),
          alignLabelWithHint: true,
        ),
        style: GoogleFonts.poppins(
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }
}
