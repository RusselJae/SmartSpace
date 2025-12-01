import 'package:flutter/cupertino.dart';

import 'sign_up.dart';
import '../shell/tab_shell.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  void _signIn() {
    // Placeholder: authenticate; on success, go to app shell.
    Navigator.of(context).pushAndRemoveUntil(
      CupertinoPageRoute(builder: (_) => const TabShell()),
      (route) => route.isFirst,
    );
  }

  void _goToSignUp() {
    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const SignUpScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Sign In')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Field(controller: _email, placeholder: 'Email'),
            const SizedBox(height: 12),
            _Field(controller: _password, placeholder: 'Password', obscureText: true),
            const SizedBox(height: 24),
            CupertinoButton.filled(onPressed: _signIn, child: const Text('Sign In')),
            const SizedBox(height: 12),
            CupertinoButton(onPressed: _goToSignUp, child: const Text('Create account')),
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




















