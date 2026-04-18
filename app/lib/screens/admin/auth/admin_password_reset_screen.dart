import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../services/admin_auth_service.dart';
import '../../../utils/password_policy.dart';
import '../../../widgets/toast.dart';
import '../admin_theme.dart';
import 'admin_login_page.dart';

/// Deep-link target: `/#/admin/reset-password?token=...`
class AdminPasswordResetScreen extends StatefulWidget {
  const AdminPasswordResetScreen({super.key, this.token});

  final String? token;

  static const String route = '/admin/reset-password';

  @override
  State<AdminPasswordResetScreen> createState() => _AdminPasswordResetScreenState();
}

class _AdminPasswordResetScreenState extends State<AdminPasswordResetScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  String? get _token {
    if (widget.token != null && widget.token!.trim().isNotEmpty) {
      return widget.token!.trim();
    }
    if (kIsWeb) {
      return Uri.base.queryParameters['token']?.trim();
    }
    return null;
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      Toast.warning(context, 'Reset link is missing. Use the link from your email.');
      return;
    }
    final p = _password.text;
    final err = PasswordPolicy.validateStrongPassword(p);
    if (err != null) {
      Toast.warning(context, err);
      return;
    }
    if (p != _confirm.text) {
      Toast.warning(context, 'Passwords do not match');
      return;
    }
    setState(() => _busy = true);
    try {
      await AdminAuthService().resetPassword(token: token, newPassword: p);
      if (!mounted) return;
      Toast.success(context, 'Password updated. Sign in with your new password.');
      Navigator.of(context).pushNamedAndRemoveUntil(AdminLoginPage.route, (route) => false);
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, e.toString().replaceFirst('Exception: ', ''));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAdminTheme(),
      child: Scaffold(
        backgroundColor: AdminPalette.sand,
        appBar: AppBar(
          title: const Text('Reset admin password'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Choose a new password',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AdminPalette.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      PasswordPolicy.strongPasswordMessage,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[700],
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirm,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminPalette.brown,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Update password'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
