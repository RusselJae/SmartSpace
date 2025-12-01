import 'package:flutter/cupertino.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  void _register() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Create Account')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Field(controller: _name, placeholder: 'Full name'),
            const SizedBox(height: 12),
            _Field(controller: _email, placeholder: 'Email'),
            const SizedBox(height: 12),
            _Field(controller: _password, placeholder: 'Password', obscureText: true),
            const SizedBox(height: 24),
            CupertinoButton.filled(onPressed: _register, child: const Text('Sign Up')),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.placeholder, this.obscureText = false});
  final TextEditingController controller;
  final String placeholder;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CupertinoColors.separator.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: CupertinoTextField(
        controller: controller,
        placeholder: placeholder,
        placeholderStyle: const TextStyle(color: CupertinoColors.placeholderText),
        style: const TextStyle(color: Color(0xFF6D4C41)),
        obscureText: obscureText,
        decoration: null,
      ),
    );
  }
}




















