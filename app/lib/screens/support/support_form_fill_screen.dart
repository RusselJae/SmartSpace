import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/support_form_request.dart';
import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../../support/support_form_catalog.dart';
import '../../widgets/toast.dart';

/// Customer fills a linked or self-started support form request.
class SupportFormFillScreen extends StatefulWidget {
  const SupportFormFillScreen({
    super.key,
    required this.formType,
    required this.requestId,
  });

  static const String route = '/support/form/fill';

  final String formType;
  final String requestId;

  @override
  State<SupportFormFillScreen> createState() => _SupportFormFillScreenState();
}

class _SupportFormFillScreenState extends State<SupportFormFillScreen> {
  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AuthService _auth = AuthService();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _selectValues = {};

  SupportFormDef? _def;
  SupportFormRequest? _request;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    _def = supportFormDefForType(widget.formType);
    if (_def == null) {
      setState(() {
        _loading = false;
        _error = 'Unknown form type';
      });
      return;
    }
    for (final field in _def!.fields) {
      _controllers[field.key] = TextEditingController();
      if (field.type == 'select' && field.options.isNotEmpty) {
        _selectValues[field.key] = field.options.first;
      }
    }

    try {
      await _db.initialize();
      final user = _auth.currentUser;
      final request = await _db.getSupportFormRequest(
        widget.requestId,
        userId: user?.id,
        email: user?.email,
      );
      if (!mounted) return;
      if (request.isSubmitted) {
        for (final entry in (request.payload ?? {}).entries) {
          _controllers[entry.key]?.text = entry.value;
        }
      }
      setState(() {
        _request = request;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _submit() async {
    if (_def == null || _request == null || _request!.isSubmitted) return;
    final user = _auth.currentUser;
    if (user == null) {
      Toast.info(context, 'Sign in to submit this form');
      return;
    }

    final payload = <String, String>{};
    for (final field in _def!.fields) {
      if (field.type == 'select') {
        payload[field.key] = _selectValues[field.key] ?? '';
      } else {
        payload[field.key] = _controllers[field.key]?.text.trim() ?? '';
      }
      if (field.required && (payload[field.key] ?? '').isEmpty) {
        Toast.info(context, '${field.label} is required');
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      await _db.submitSupportFormRequest(
        requestId: widget.requestId,
        userId: user.id,
        email: user.email,
        payload: payload,
      );
      if (!mounted) return;
      Toast.success(context, 'Form submitted — check Support chat for updates');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Submit failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
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
          _def?.title ?? 'Support form',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: mediumBrown),
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                : Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          children: [
                            if (_request!.isSubmitted)
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Already submitted. Start a new form from Help Center if you need to send more info.',
                                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.green.shade800),
                                ),
                              )
                            else
                              Text(
                                _def!.description,
                                style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54, height: 1.4),
                              ),
                            const SizedBox(height: 12),
                            ..._def!.fields.map(_buildField),
                          ],
                        ),
                      ),
                      if (!_request!.isSubmitted)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: CupertinoButton.filled(
                              color: mediumBrown,
                              onPressed: _submitting ? null : _submit,
                              child: _submitting
                                  ? const CupertinoActivityIndicator(color: Colors.white)
                                  : const Text('Submit form'),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildField(SupportFormFieldDef field) {
    if (field.type == 'select') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectValues[field.key],
                  isExpanded: true,
                  items: field.options
                      .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: _request!.isSubmitted
                      ? null
                      : (v) => setState(() => _selectValues[field.key] = v),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final controller = _controllers[field.key]!;
    final maxLines = field.type == 'textarea' ? 4 : 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.required ? '${field.label} *' : field.label,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          CupertinoTextField(
            controller: controller,
            maxLines: maxLines,
            placeholder: field.placeholder,
            readOnly: _request!.isSubmitted,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
          ),
        ],
      ),
    );
  }
}
