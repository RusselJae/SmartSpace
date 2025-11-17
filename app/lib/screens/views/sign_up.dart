import 'package:flutter/cupertino.dart';

import 'sign_in.dart';

/// =============================================================
/// SignUpScreen (Cupertino)
///
/// - Clean, modern layout with Apple HIG spacing and hierarchy.
/// - Name, Email, Password fields; single primary CTA.
/// - Icon-only social options for Facebook & Google (non-functional).
/// =============================================================
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  static const String route = '/auth/sign-up';

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // ------------------------------
  // Controllers for inputs
  // ------------------------------
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Sign Up'),
      ),
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ------------------------------
              // Title & subtitle
              // ------------------------------
              Text(
                'Create your account',
                style: theme.textTheme.navLargeTitleTextStyle,
              ),
              const SizedBox(height: 8),
              Text(
                'Start planning rooms with AR in minutes.',
                style: theme.textTheme.textStyle.copyWith(
                  color: CupertinoColors.secondaryLabel,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),

              // ------------------------------
              // Name
              // ------------------------------
              const Text('Full name'),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _nameController,
                placeholder: 'Alex Johnson',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              // ------------------------------
              // Email
              // ------------------------------
              const Text('Email'),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _emailController,
                placeholder: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              // ------------------------------
              // Password
              // ------------------------------
              const Text('Password'),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _passwordController,
                placeholder: '••••••••',
                obscureText: true,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 20),

              // ------------------------------
              // Primary CTA (non-functional placeholder)
              // ------------------------------
              CupertinoButton.filled(
                onPressed: () {},
                child: const Text('Create Account'),
              ),

              const SizedBox(height: 16),

              // ------------------------------
              // Social icon-only buttons (non-functional)
              // ------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Facebook icon-only button
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {},
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1877F2),
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'f',
                        style: TextStyle(
                          inherit: true,
                          color: CupertinoColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Google icon-only button
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {},
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: CupertinoColors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                        boxShadow: const [
                          BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'G',
                        style: TextStyle(
                          inherit: true,
                          color: Color(0xFF4285F4),
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ------------------------------
              // Switch to Sign In
              // ------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already have an account?', style: theme.textTheme.textStyle.copyWith(color: CupertinoColors.secondaryLabel)),
                  const SizedBox(width: 6),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      Navigator.of(context).push(
                        CupertinoPageRoute(builder: (_) => const SignInScreen()),
                      );
                    },
                    child: const Text('Sign In'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}








