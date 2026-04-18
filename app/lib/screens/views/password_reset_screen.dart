import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../utils/password_policy.dart';
import '../../widgets/styled_text_field.dart';
import '../../widgets/toast.dart';
import 'sign_in.dart';

/// Deep-link target: `/#/auth/reset-password?token=...` (see backend email).
class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key, this.token});

  final String? token;

  static const String route = '/auth/reset-password';

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final AuthService _auth = AuthService();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;

  String? get _tokenFromRoute {
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
    final token = _tokenFromRoute;
    if (token == null || token.isEmpty) {
      Toast.warning(context, 'Reset link is missing. Open the link from your email.');
      return;
    }
    final p = _password.text;
    final c = _confirm.text;
    final err = PasswordPolicy.validateStrongPassword(p);
    if (err != null) {
      Toast.warning(context, err);
      return;
    }
    if (p != c) {
      Toast.warning(context, 'Passwords do not match');
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth.resetPassword(token: token, newPassword: p);
      if (!mounted) return;
      Toast.success(context, 'Password updated. Sign in with your new password.');
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        CupertinoPageRoute(
          builder: (_) => const SignInScreen(),
          fullscreenDialog: true,
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, e.toString().replaceFirst('Exception: ', ''));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const kBrown = Color(0xFF8D6E63);
    const kTextPrimary = Color(0xFF6D4C41);

    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
        middle: Text('New password', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        leading: CupertinoNavigationBarBackButton(
          color: kBrown,
          onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose a strong password',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                PasswordPolicy.strongPasswordMessage,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              StyledTextField(
                controller: _password,
                label: 'New password',
                icon: Icons.lock_outline,
                obscureText: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              StyledTextField(
                controller: _confirm,
                label: 'Confirm password',
                icon: Icons.lock_outline,
                obscureText: true,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: kBrown,
                  borderRadius: BorderRadius.circular(16),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Text(
                          'Update password',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
