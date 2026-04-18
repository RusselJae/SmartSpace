import 'package:flutter/material.dart';

import 'package:smartspace_ar/services/admin_auth_service.dart';
import 'package:smartspace_ar/utils/admin_post_login_path.dart';
import 'package:smartspace_ar/widgets/toast.dart';

import '../admin_theme.dart';
import 'admin_password_reset_screen.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  static const String route = '/admin/login';

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();
  bool isLoading = false;
  bool _checkingSession = true;
  bool _showPasswordHelp = false;
  static const Color _kDeepWalnut = Color(0xFF3E2723);
  static const String _kRightPanelBgAsset = 'assets/images/bg3.jpg';

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final adminAuth = AdminAuthService();
    await adminAuth.initialize();
    if (!mounted) return;
    if (adminAuth.isAuthenticated) {
      // Resume the tab from `/#/admin/...` on web when the hash targets a panel.
      Navigator.of(context).pushReplacementNamed(adminPostLoginTargetPath());
    } else {
      setState(() {
        _checkingSession = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return Theme(
        data: buildAdminTheme(),
        child: Scaffold(
          backgroundColor: AdminPalette.sand,
          body: Center(
            child: CircularProgressIndicator(
              color: AdminPalette.brown,
            ),
          ),
        ),
      );
    }

    return Theme(
      data: buildAdminTheme(),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: AdminPalette.sand,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isWide = constraints.maxWidth >= 980;

                final Widget logoPanel = Container(
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(_kRightPanelBgAsset),
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                );

                final Widget formPanel = Container(
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 24, 24, isWide ? 24 : 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: _buildLoginCard(context),
                    ),
                  ),
                );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(flex: 7, child: formPanel),
                      Expanded(flex: 3, child: logoPanel),
                    ],
                  );
                }

                // Small screens: keep it simple and readable—logo on white, then form on walnut.
                return Column(
                  children: [
                    SizedBox(height: 220, child: logoPanel),
                    Expanded(child: formPanel),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard(BuildContext context) {
    // Reference-style: a clean "sheet" with crisp rectangular corners.
    // The left panel is already white, so we keep the sheet very subtle.
    return Center(
      child: SizedBox(
        width: 520,
        height: 640,
        child: Card(
          elevation: 0,
          shadowColor: Colors.transparent,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: Colors.black.withValues(alpha: 0.06), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  label: 'Brand logo',
                  child: _LogoMark(size: 140),
                ),
                const SizedBox(height: 26),
                Text(
                  'Sign in',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AdminPalette.textPrimary,
                        letterSpacing: -0.4,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Use your admin credentials.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: 420,
                  child: _InputField(
                    controller: email,
                    label: 'Email',
                    icon: Icons.email_outlined,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 420,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InputField(
                        controller: password,
                        label: 'Password',
                        obscureText: true,
                        icon: Icons.lock_outline,
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showPasswordHelp ? null : _showForgotPasswordDialog,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey[800],
                            textStyle: const TextStyle(fontWeight: FontWeight.w600),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: isLoading ? null : _login,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kDeepWalnut,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          elevation: 0,
                        ),
                        child: isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              )
                            : const Text(
                                'Login',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  'Admin access only.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'If you don’t have credentials, ask your administrator.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                        height: 1.3,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showForgotPasswordDialog() async {
    setState(() => _showPasswordHelp = true);
    try {
      final resetEmail = TextEditingController(text: email.text.trim());
      var sending = false;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Forgot your password?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Enter your admin email to receive a reset link.'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: resetEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: sending
                      ? null
                      : () async {
                          final targetEmail = resetEmail.text.trim();
                          if (targetEmail.isEmpty) {
                            Toast.warning(context, 'Please enter your email');
                            return;
                          }
                          setDialogState(() => sending = true);
                          try {
                            await AdminAuthService().requestPasswordReset(email: targetEmail);
                            if (!mounted || !context.mounted) return;
                            Navigator.of(context).pop();
                            Toast.success(this.context, 'If the account exists, a reset email is on the way.');
                            Navigator.of(this.context).pushNamed(AdminPasswordResetScreen.route);
                          } catch (e) {
                            if (!mounted) return;
                            Toast.error(this.context, e.toString().replaceFirst('Exception: ', ''));
                            setDialogState(() => sending = false);
                          }
                        },
                  child: sending
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send reset link'),
                ),
              ],
            ),
          );
        },
      );
      resetEmail.dispose();
    } finally {
      if (mounted) setState(() => _showPasswordHelp = false);
    }
  }

  Future<void> _login() async {
    final String emailText = email.text.trim();
    final String passwordText = password.text;

    if (emailText.isEmpty || passwordText.isEmpty) {
      Toast.warning(context, 'Please enter both email and password');
      return;
    }

    setState(() => isLoading = true);
    try {
      final adminAuth = AdminAuthService();
      final success = await adminAuth.signIn(email: emailText, password: passwordText);
      if (!mounted) return;
      if (!success) {
        Toast.error(context, 'Invalid admin credentials');
        setState(() => isLoading = false);
        return;
      }
      Navigator.of(context).pushReplacementNamed(adminPostLoginTargetPath());
    } catch (error) {
      if (!mounted) return;
      Toast.error(context, 'Failed to sign in: $error');
      setState(() => isLoading = false);
    }
  }
}

class _InputField extends StatefulWidget {
  const _InputField({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.icon,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final IconData? icon;

  @override
  State<_InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<_InputField> {
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: widget.obscureText && _obscureText,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: widget.icon != null
            ? Icon(widget.icon, color: AdminPalette.brown.withValues(alpha: 0.7))
            : null,
        suffixIcon: widget.obscureText
            ? IconButton(
                icon: Icon(
                  _obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: Colors.grey[600],
                ),
                onPressed: () {
                  setState(() {
                    _obscureText = !_obscureText;
                  });
                },
              )
            : null,
        labelStyle: TextStyle(
          color: Colors.grey[800],
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color: Colors.grey[400],
          fontWeight: FontWeight.normal,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(
            color: Colors.grey.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(
            color: Colors.grey.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(
            color: AdminPalette.brown,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    // Keep the brand mark simple: no extra copy, no gradients, no clutter.
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/images/logo.jpg',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: AdminPalette.brown,
              alignment: Alignment.center,
              child: Icon(
                Icons.storefront_rounded,
                color: Colors.white,
                size: size * 0.35,
              ),
            );
          },
        ),
      ),
    );
  }
}


