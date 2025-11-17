import 'package:flutter/material.dart';

import 'package:smartspace_ar/screens/admin/admin_shell.dart';

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
                constraints: const BoxConstraints(maxWidth: 460),
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
                          'Create admin account',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text('Provision a new Adminator profile.', textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        _InputField(controller: name, label: 'Full name'),
                        const SizedBox(height: 12),
                        _InputField(controller: email, label: 'Work email'),
                        const SizedBox(height: 12),
                        _InputField(controller: password, label: 'Password', obscureText: true),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: isLoading ? null : _signup,
                          child: isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Create account'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Back to login'),
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

  Future<void> _signup() async {
    setState(() => isLoading = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => isLoading = false);
    Navigator.of(context).pushReplacementNamed(AdminShell.route);
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


