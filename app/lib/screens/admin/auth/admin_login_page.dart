import 'package:flutter/material.dart';

import 'package:smartspace_ar/screens/admin/admin_shell.dart';

import '../admin_theme.dart';
import 'admin_signup_page.dart';

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

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAdminTheme(),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: AdminPalette.sand,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Adminator Login',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text('Sign in to manage SmartSpace.', textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        _InputField(controller: email, label: 'Email address'),
                        const SizedBox(height: 12),
                        _InputField(controller: password, label: 'Password', obscureText: true),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: isLoading ? null : _login,
                          child: isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Sign In'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _goToSignup,
                          child: const Text('Need an account? Sign up'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    setState(() => isLoading = true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => isLoading = false);
    Navigator.of(context).pushReplacementNamed(AdminShell.route);
  }

  void _goToSignup() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminSignupPage()));
  }
}

class _InputField extends StatelessWidget {
  const _InputField({required this.controller, required this.label, this.obscureText = false});

  final TextEditingController controller;
  final String label;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(labelText: label),
    );
  }
}


