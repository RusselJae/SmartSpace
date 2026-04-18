import 'package:flutter/material.dart';

import '../../../../models/admin.dart';
import '../../../../services/admin_auth_service.dart';
import '../../../../services/mysql_database_service.dart';
import '../../../../utils/password_policy.dart';
import '../../../../widgets/toast.dart';

import '../admin_theme.dart';

class AdminSignupPage extends StatefulWidget {
  const AdminSignupPage({super.key});

  static const String route = '/admin/signup';

  @override
  State<AdminSignupPage> createState() => _AdminSignupPageState();
}

class _AdminSignupPageState extends State<AdminSignupPage> {
  final TextEditingController name = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();
  bool isLoading = false;

  Future<void> _showVerificationDialog(Admin admin) async {
    final codeController = TextEditingController();
    var verifying = false;
    var resending = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Verify admin email'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('We sent a verification code to ${admin.email}.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: resending
                      ? null
                      : () async {
                          setDialogState(() => resending = true);
                          try {
                            await MySQLDatabaseService().resendAdminVerification(adminId: admin.id);
                            if (!mounted) return;
                            Toast.success(this.context, 'Verification email sent');
                          } catch (e) {
                            if (!mounted) return;
                            Toast.error(this.context, e.toString().replaceFirst('Exception: ', ''));
                          } finally {
                            if (mounted) setDialogState(() => resending = false);
                          }
                        },
                  child: resending ? const Text('Sending...') : const Text('Resend email'),
                ),
                FilledButton(
                  onPressed: verifying
                      ? null
                      : () async {
                          final code = codeController.text.trim();
                          if (code.isEmpty) {
                            Toast.warning(context, 'Please enter the verification code');
                            return;
                          }
                          setDialogState(() => verifying = true);
                          try {
                            await AdminAuthService().verifyEmailWithCode(code);
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            Toast.success(this.context, 'Email verified. You can now sign in.');
                          } catch (e) {
                            if (!mounted) return;
                            Toast.error(this.context, e.toString().replaceFirst('Exception: ', ''));
                            setDialogState(() => verifying = false);
                          }
                        },
                  child: verifying ? const Text('Verifying...') : const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );
    codeController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAdminTheme(),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: AdminPalette.sand,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: AdminPalette.brown.withValues(alpha: 0.22),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/logo.jpg',
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: AdminPalette.brown,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.storefront_rounded,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Wood Home Furniture Trading',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AdminPalette.textPrimary,
                              letterSpacing: -0.5,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create Admin Account',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      // Sign up card
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Get started',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AdminPalette.textPrimary,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Create a new administrator account',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              _InputField(
                                controller: name,
                                label: 'Full name',
                                icon: Icons.person_outline,
                              ),
                              const SizedBox(height: 16),
                              _InputField(
                                controller: email,
                                label: 'Work email',
                                icon: Icons.email_outlined,
                              ),
                              const SizedBox(height: 16),
                              _InputField(
                                controller: password,
                                label: 'Password',
                                obscureText: true,
                                icon: Icons.lock_outline,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: Colors.blue[700],
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        PasswordPolicy.strongPasswordMessage,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue[900],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: isLoading ? null : _signup,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AdminPalette.brown,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Create account',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Back to login link
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: RichText(
                          text: TextSpan(
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                            children: [
                              const TextSpan(text: 'Already have an account? '),
                              TextSpan(
                                text: 'Sign in',
                                style: TextStyle(
                                  color: AdminPalette.brown,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signup() async {
    final emailText = email.text.trim();
    final passwordText = password.text;
    final nameText = name.text.trim();

    if (emailText.isEmpty || passwordText.isEmpty || nameText.isEmpty) {
      Toast.warning(context, 'Please fill in all fields');
      return;
    }

    final policyError = PasswordPolicy.validateStrongPassword(passwordText);
    if (policyError != null) {
      Toast.warning(context, policyError);
      return;
    }

    setState(() => isLoading = true);
    try {
      final db = MySQLDatabaseService();
      final admin = await db.createAdmin(
        email: emailText,
        password: passwordText,
        fullName: nameText,
      );
      if (!mounted) return;
      Toast.success(context, 'Admin account created. Verify email before first login.');
      await _showVerificationDialog(admin);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/admin/login');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to create admin: $e');
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
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.grey.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.grey.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
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


