import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/faq.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/mysql_database_service.dart';
import '../widgets/admin_toolbar.dart';
import '../../../widgets/toast.dart';

/// Admin page for managing support chat FAQs.
///
/// Allows admins to create, edit, and delete FAQs that appear in the
/// support chat screen for users.
class FaqsAdminPage extends StatefulWidget {
  const FaqsAdminPage({super.key});

  @override
  State<FaqsAdminPage> createState() => _FaqsAdminPageState();
}

class _FaqsAdminPageState extends State<FaqsAdminPage> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AdminAuthService _adminAuth = AdminAuthService();

  List<Faq> _faqs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFaqs();
  }

  Future<void> _loadFaqs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _db.initialize();
      final faqs = await _db.getFaqs();
      if (!mounted) return;
      setState(() {
        _faqs = faqs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load FAQs: $e';
      });
    }
  }

  Future<void> _createFaq() async {
    final result = await showDialog<_FaqFormData>(
      context: context,
      builder: (_) => const _FaqFormDialog(isEdit: false),
    );
    if (result == null) return;

    final adminId = _adminAuth.currentAdminId;
    if (adminId == null) {
      Toast.error(context, 'Admin session expired. Please sign in again.');
      return;
    }

    try {
      await _db.createFaq(
        adminId: adminId,
        question: result.question,
        answer: result.answer,
        sortOrder: result.sortOrder,
      );
      if (!mounted) return;
      Toast.success(context, 'FAQ added');
      await _loadFaqs();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to add FAQ: $e');
    }
  }

  Future<void> _editFaq(Faq faq) async {
    final result = await showDialog<_FaqFormData>(
      context: context,
      builder: (_) => _FaqFormDialog(
        isEdit: true,
        initialQuestion: faq.question,
        initialAnswer: faq.answer,
        initialSortOrder: faq.sortOrder,
      ),
    );
    if (result == null) return;

    final adminId = _adminAuth.currentAdminId;
    if (adminId == null) {
      Toast.error(context, 'Admin session expired. Please sign in again.');
      return;
    }

    try {
      await _db.updateFaq(
        adminId: adminId,
        id: faq.id,
        question: result.question,
        answer: result.answer,
        sortOrder: result.sortOrder,
      );
      if (!mounted) return;
      Toast.success(context, 'FAQ updated');
      await _loadFaqs();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to update FAQ: $e');
    }
  }

  Future<void> _deleteFaq(Faq faq) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete FAQ'),
        content: Text(
          'Are you sure you want to delete this FAQ?\n\n"${faq.question}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final adminId = _adminAuth.currentAdminId;
    if (adminId == null) {
      Toast.error(context, 'Admin session expired. Please sign in again.');
      return;
    }

    try {
      await _db.deleteFaq(adminId: adminId, id: faq.id);
      if (!mounted) return;
      Toast.success(context, 'FAQ deleted');
      await _loadFaqs();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to delete FAQ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminToolbar(
          title: 'FAQs',
          actions: const [],
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _loadFaqs,
                tooltip: 'Refresh',
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _loading ? null : _createFaq,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add FAQ'),
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
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _faqs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.help_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No FAQs yet',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add FAQs to help users in the support chat',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _createFaq,
                            icon: const Icon(Icons.add),
                            label: const Text('Add first FAQ'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF8D6E63),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: _faqs.length,
                      itemBuilder: (context, index) {
                        final faq = _faqs[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: CupertinoColors.separator.withValues(alpha: 0.3),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            title: Text(
                              faq.question,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                faq.answer,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _editFaq(faq),
                                  tooltip: 'Edit',
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, size: 20, color: Colors.red[400]),
                                  onPressed: () => _deleteFaq(faq),
                                  tooltip: 'Delete',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _FaqFormData {
  final String question;
  final String answer;
  final int sortOrder;

  _FaqFormData({
    required this.question,
    required this.answer,
    required this.sortOrder,
  });
}

class _FaqFormDialog extends StatefulWidget {
  final bool isEdit;
  final String? initialQuestion;
  final String? initialAnswer;
  final int? initialSortOrder;

  const _FaqFormDialog({
    required this.isEdit,
    this.initialQuestion,
    this.initialAnswer,
    this.initialSortOrder,
  });

  @override
  State<_FaqFormDialog> createState() => _FaqFormDialogState();
}

class _FaqFormDialogState extends State<_FaqFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _questionController;
  late final TextEditingController _answerController;
  late final TextEditingController _sortOrderController;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.initialQuestion ?? '');
    _answerController = TextEditingController(text: widget.initialAnswer ?? '');
    _sortOrderController = TextEditingController(
      text: (widget.initialSortOrder ?? 0).toString(),
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEdit ? 'Edit FAQ' : 'Add FAQ'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _questionController,
                  decoration: const InputDecoration(
                    labelText: 'Question',
                    hintText: 'e.g. Where is my order?',
                  ),
                  maxLines: 2,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _answerController,
                  decoration: const InputDecoration(
                    labelText: 'Answer',
                    hintText: 'Response shown when user taps this FAQ',
                  ),
                  maxLines: 4,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Sort order:',
                      style: GoogleFonts.poppins(fontSize: 14),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        controller: _sortOrderController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '0',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final sortOrder = int.tryParse(_sortOrderController.text.trim()) ?? 0;
            Navigator.of(context).pop(_FaqFormData(
              question: _questionController.text.trim(),
              answer: _answerController.text.trim(),
              sortOrder: sortOrder,
            ));
          },
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8D6E63)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
