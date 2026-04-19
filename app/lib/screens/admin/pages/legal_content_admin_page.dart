import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/admin_auth_service.dart';
import '../../../services/mysql_database_service.dart';
import '../../../widgets/toast.dart';

/// Admin page for editing Terms & Conditions and Privacy Policy.
///
/// Markdown-style markup (`##`, `-`, `**`) with a compact formatting toolbar.
/// Prior versions are stored server-side when you publish changes.
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
  int _termsVersion = 1;
  int _privacyVersion = 1;

  static const String _defaultTermsContent = '''
## About SmartSpace
SmartSpace provides made-to-order and on-hand furniture for personal and commercial use.

## 1. Orders & Product Information
- Product details are provided as accurately as possible.
- Minor variations in handcrafted and wood products are normal.
- Orders are confirmed once required payment and approval are complete.

## 2. Payment Terms
- Down payments apply to custom orders and may be non-refundable once production starts.
- Remaining balance is typically payable on delivery.
- Installment availability depends on the selected plan.

## 3. Delivery & Acceptance
- Delivery schedules are coordinated based on location and availability.
- Customers should inspect items upon delivery.
- Additional handling fees may apply for difficult delivery access.

## 4. Returns & Warranty
- Custom orders are generally not returnable for change-of-mind.
- Manufacturing defects should be reported through support with photos.

## 5. Contact
- For support or disputes, contact SmartSpace through the in-app support page.
''';

  static const String _defaultPrivacyContent = '''
## 1. Scope
This Privacy Policy explains how SmartSpace collects, uses, and protects personal data.

## 2. Information We Collect
- Account details (name, email, username, phone).
- Order and checkout details.
- Delivery addresses and support messages.

## 3. How We Use Data
- To manage accounts, orders, payments, and delivery.
- To improve product and app experience.
- To prevent fraud and support security.

## 4. Sharing
- We do not sell personal data.
- Data may be shared only with service providers needed for operations.
- Legal disclosures may be made when required by law.

## 5. Retention & Security
- Data is retained only as long as necessary for operations and compliance.
- Reasonable safeguards are applied, but no system is 100% risk-free.

## 6. Contact
- For privacy concerns, contact SmartSpace using the in-app support page.
''';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() {});
      }
    });
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
      final termsPayload = await _db.getLegalContentPayload('terms');
      final privacyPayload = await _db.getLegalContentPayload('privacy');
      if (!mounted) return;
      final terms = termsPayload?.content;
      final privacy = privacyPayload?.content;
      _termsController.text = (terms != null && terms.trim().isNotEmpty) ? terms : _defaultTermsContent;
      _privacyController.text =
          (privacy != null && privacy.trim().isNotEmpty) ? privacy : _defaultPrivacyContent;
      _termsVersion = termsPayload?.version ?? 1;
      _privacyVersion = privacyPayload?.version ?? 1;
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
    if (_adminAuth.adminAccessToken == null || _adminAuth.adminAccessToken!.isEmpty) {
      Toast.error(context, 'Admin session expired. Please sign in again.');
      return;
    }

    setState(() => _saving = true);
    try {
      final key = _tabController.index == 0 ? 'terms' : 'privacy';
      final content = _tabController.index == 0 ? _termsController.text : _privacyController.text;

      await _db.updateLegalContent(key: key, content: content);
      if (!mounted) return;
      Toast.success(
        context,
        key == 'terms' ? 'Terms & Conditions saved' : 'Privacy Policy saved',
      );
      await _loadContent();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openVersionHistory() async {
    final key = _tabController.index == 0 ? 'terms' : 'privacy';
    final label = key == 'terms' ? 'Terms & Conditions' : 'Privacy Policy';
    try {
      final entries = await _db.getLegalContentHistory(key, limit: 50);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Text('Version history — $label', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 480,
            height: 360,
            child: entries.isEmpty
                ? Text(
                    'No snapshots yet. History is recorded when you save a new version over existing content.',
                    style: GoogleFonts.poppins(fontSize: 13, height: 1.4),
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final subtitle = e.createdAt?.toLocal().toString() ?? '';
                      return ListTile(
                        title: Text('Version ${e.version}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        subtitle: Text(subtitle, style: GoogleFonts.poppins(fontSize: 12)),
                        trailing: const Icon(Icons.visibility_outlined),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showSnapshotSheet(e.version, e.content ?? '', subtitle);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Could not load history: $e');
    }
  }

  void _showSnapshotSheet(int version, String content, String when) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scroll) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Version $version',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(when, style: GoogleFonts.poppins(fontSize: 12, color: Colors.black54)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Scrollbar(
                controller: scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: SelectableText(
                    content.isEmpty ? '(empty)' : content,
                    style: GoogleFonts.poppins(fontSize: 14, height: 1.55, color: const Color(0xFF1A1A1A)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verLabel = _tabController.index == 0 ? _termsVersion : _privacyVersion;
    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Content',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Write a unique legal page. Use the toolbar for quick formatting; published Terms bump the version and notify customers.',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            height: 1.45,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _openVersionHistory,
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Version history'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF5C4033),
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loading ? null : _loadContent,
                    tooltip: 'Refresh',
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: (_loading || _saving) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(_saving ? 'Saving…' : 'Save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8D6E63),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
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
                      child: Text(_error!, style: TextStyle(color: Colors.red[700])),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Current version: v$verLabel',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: TabBar(
              controller: _tabController,
              onTap: (_) => setState(() {}),
              labelColor: const Color(0xFF8D6E63),
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: const Color(0xFF8D6E63),
              tabs: const [
                Tab(text: 'Terms & Conditions'),
                Tab(text: 'Privacy Policy'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _LegalEditorPanel(
                        controller: _termsController,
                        hint: '## Section\nBody text\n\n- Bullet',
                        onChanged: () => setState(() {}),
                      ),
                      _LegalEditorPanel(
                        controller: _privacyController,
                        hint: '## Section\nBody text\n\n- Bullet',
                        onChanged: () => setState(() {}),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _LegalEditorPanel extends StatelessWidget {
  const _LegalEditorPanel({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;

  static void _wrap(TextEditingController c, String left, String right) {
    final sel = c.selection;
    if (!sel.isValid) return;
    final text = c.text;
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    final before = text.substring(0, start);
    final mid = text.substring(start, end);
    final after = text.substring(end);
    final next = '$before$left$mid$right$after';
    final off = start + left.length + mid.length + right.length;
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: off),
    );
  }

  static void _insert(TextEditingController c, String insertion) {
    final sel = c.selection;
    if (!sel.isValid) return;
    final text = c.text;
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    final before = text.substring(0, start);
    final after = text.substring(end);
    final next = '$before$insertion$after';
    final off = start + insertion.length;
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: off),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ToolChip(
                  icon: Icons.format_bold,
                  tooltip: 'Bold',
                  onPressed: () {
                    _wrap(controller, '**', '**');
                    onChanged();
                  },
                ),
                _ToolChip(
                  icon: Icons.format_italic,
                  tooltip: 'Italic',
                  onPressed: () {
                    _wrap(controller, '_', '_');
                    onChanged();
                  },
                ),
                _ToolChip(
                  icon: Icons.format_underlined,
                  tooltip: 'Underline (HTML)',
                  onPressed: () {
                    _wrap(controller, '<u>', '</u>');
                    onChanged();
                  },
                ),
                _ToolChip(
                  icon: Icons.format_list_bulleted,
                  tooltip: 'Bullet line',
                  onPressed: () {
                    _insert(controller, '- ');
                    onChanged();
                  },
                ),
                _ToolChip(
                  icon: Icons.format_list_numbered,
                  tooltip: 'Numbered line',
                  onPressed: () {
                    _insert(controller, '1. ');
                    onChanged();
                  },
                ),
                _ToolChip(
                  icon: Icons.title,
                  tooltip: 'Heading',
                  onPressed: () {
                    _insert(controller, '## ');
                    onChanged();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: controller,
                onChanged: (_) => onChanged(),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500], height: 1.5),
                  filled: true,
                  fillColor: Colors.white,
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  height: 1.55,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: const Color(0xFF424242)),
          ),
        ),
      ),
    );
  }
}
