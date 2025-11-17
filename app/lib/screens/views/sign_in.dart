import 'package:flutter/cupertino.dart';

import 'sign_up.dart';

/// =============================================================
/// SignInScreen (Cupertino)
///
/// - Minimal, elegant auth screen following Apple HIG:
///   Clear hierarchy, high-contrast labels, generous spacing.
/// - Primary email + password fields with a single CTA.
/// - Social auth options as icon-only circular buttons (non-functional):
///   Facebook (blue circle with 'f') and Google (light surface with 'G').
/// - Motion kept subtle; native transitions.
/// =============================================================
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  static const String route = '/auth/sign-in';

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  // ------------------------------
  // Controllers for form inputs
  // ------------------------------
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Sign In'),
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
                'Welcome back',
                style: theme.textTheme.navLargeTitleTextStyle,
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to continue designing your space.',
                style: theme.textTheme.textStyle.copyWith(
                  color: CupertinoColors.secondaryLabel,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),

              // ------------------------------
              // Email field
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
              // Password field
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
                child: const Text('Sign In'),
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
                        color: const Color(0xFF1877F2), // Facebook blue
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
                          color: Color(0xFF4285F4), // Google blue
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
              // Switch to Sign Up
              // ------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Don\'t have an account?', style: theme.textTheme.textStyle.copyWith(color: CupertinoColors.secondaryLabel)),
                  const SizedBox(width: 6),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      Navigator.of(context).push(
                        CupertinoPageRoute(builder: (_) => const SignUpScreen()),
                      );
                    },
                    child: const Text('Sign Up'),
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








