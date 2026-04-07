import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';

/// Change Password UI backed by `AuthService.changePassword()`.
///
/// Notes:
/// - Uses a simple current/new/confirm flow.
/// - Keeps the UI Cupertino-style to match the rest of your profile area.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  static const String route = '/change-password';

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentController.text;
    final next = _newController.text;
    final confirm = _confirmController.text;

    setState(() {
      _error = null;
    });

    if (current.trim().isEmpty || next.trim().isEmpty || confirm.trim().isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (next.trim().length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'New password and confirmation do not match.');
      return;
    }
    if (current == next) {
      setState(() => _error = 'New password must be different from your current password.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await AuthService().changePassword(
        currentPassword: current,
        newPassword: next,
      );

      if (!mounted) return;
      await showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: Text(
            'Password Updated',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Your password has been updated successfully.',
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

      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', '').trim());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
            Text(
              '*',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: CupertinoColors.systemRed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CupertinoTextField(
          controller: controller,
          obscureText: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          placeholder: label,
          placeholderStyle: GoogleFonts.poppins(color: Colors.black38),
          style: GoogleFonts.poppins(color: Colors.black87),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBCAAA4).withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
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
          bottom: BorderSide(color: mediumBrown.withValues(alpha: 0.2), width: 0.5),
        ),
        leading: CupertinoNavigationBarBackButton(
          color: mediumBrown,
          onPressed: _submitting ? null : () => Navigator.of(context).maybePop(),
        ),
        middle: Text(
          'Change Password',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: mediumBrown),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          children: [
            _field(label: 'Current Password', controller: _currentController),
            const SizedBox(height: 14),
            _field(label: 'New Password', controller: _newController),
            const SizedBox(height: 14),
            _field(label: 'Confirm New Password', controller: _confirmController),
            const SizedBox(height: 14),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CupertinoColors.systemRed.withValues(alpha: 0.25)),
                ),
                child: Text(
                  _error!,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: CupertinoColors.systemRed,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            CupertinoButton.filled(
              onPressed: _submitting ? null : _submit,
              borderRadius: BorderRadius.circular(14),
              child: _submitting
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : Text(
                      'Update Password',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

