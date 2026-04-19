import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../widgets/styled_text_field.dart';
import '../../widgets/toast.dart';
import '../../widgets/loading_screen.dart';
import '../shell/tab_shell.dart';
import 'sign_up.dart';
import 'password_reset_screen.dart';
import '../profile/terms_and_conditions_screen.dart';
import '../profile/privacy_policy_screen.dart';

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
  final AuthService _auth = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController(text: _emailController.text.trim());
    var sending = false;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return CupertinoAlertDialog(
              title: const Text('Forgot password?'),
              content: Column(
                children: [
                  const SizedBox(height: 8),
                  const Text('Enter your account email and we will send a reset link.'),
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    placeholder: 'you@example.com',
                  ),
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: sending ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                CupertinoDialogAction(
                  onPressed: sending
                      ? null
                      : () async {
                          final email = emailController.text.trim();
                          if (email.isEmpty) {
                            Toast.warning(context, 'Please enter your email');
                            return;
                          }
                          setStateDialog(() => sending = true);
                          try {
                            await _auth.requestPasswordReset(email: email);
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            Toast.success(this.context, 'If the account exists, a reset email is on the way.');
                            Navigator.of(this.context).pushNamed(PasswordResetScreen.route);
                          } catch (e) {
                            if (!mounted) return;
                            Toast.error(this.context, e.toString().replaceFirst('Exception: ', ''));
                            setStateDialog(() => sending = false);
                          }
                        },
                  child: sending
                      ? const CupertinoActivityIndicator()
                      : const Text('Send reset link'),
                ),
              ],
            );
          },
        );
      },
    );
    emailController.dispose();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      Toast.warning(context, 'Please fill in all fields');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await _auth.signIn(
        // AuthService now accepts username OR email in this field.
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      // Show loading screen before navigating to main app
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        CupertinoPageRoute(
          builder: (_) => LoadingScreen(
            message: 'Welcome back!',
            nextBuilder: (_) => const TabShell(),
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      Toast.error(context, 'Invalid username or password');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Updated color palette: removed dark brown, using medium brown and orange
    const Color kTextPrimary = Color(0xFF6D4C41); // Medium brown for text
    const Color kBrown = Color(0xFF8D6E63); // Primary brown
    const Color kLight = Color(0xFFF4E6D4);

    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
        leading: CupertinoNavigationBarBackButton(
          onPressed: () {
            // Pop the fullscreen dialog
            Navigator.of(context, rootNavigator: true).maybePop();
          },
          color: kBrown,
        ),
        middle: Text(
          'Sign In',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Calculate available height and adjust spacing dynamically
            final availableHeight = constraints.maxHeight;
            final isSmallScreen = availableHeight < 700;
            
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // ------------------------------
                  // App Logo
                  // ------------------------------
                  Container(
                    width: isSmallScreen ? 80 : 100,
                    height: isSmallScreen ? 80 : 100,
                    decoration: BoxDecoration(
                      color: kLight.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.jpg',
                        width: isSmallScreen ? 80 : 100,
                        height: isSmallScreen ? 80 : 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 6 : 8),
                  Text(
                    'Wood Home Furniture Trading',
                    style: GoogleFonts.poppins(
                      fontSize: isSmallScreen ? 18 : 22,
                      fontWeight: FontWeight.w700,
                      color: kTextPrimary,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: isSmallScreen ? 32 : 40),

                  // ------------------------------
                  // Email field
                  // ------------------------------
                  StyledTextField(
                    controller: _emailController,
                    label: 'Email or Username',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    placeholder: 'you@example.com or username',
                  ),
                  SizedBox(height: isSmallScreen ? 16 : 20),

                  // ------------------------------
                  // Password field
                  // ------------------------------
                  StyledTextField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    placeholder: '••••••••',
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _loading ? null : _showForgotPasswordDialog,
                      child: Text(
                        'Forgot password?',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kBrown,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 14 : 18),

                  // ------------------------------
                  // Primary CTA
                  // ------------------------------
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      // Primary button – solid fill (no gradient), clean and consistent.
                      decoration: BoxDecoration(
                        color: const Color(0xFF8D6E63),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8D6E63).withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        borderRadius: BorderRadius.circular(16),
                        disabledColor: kBrown.withValues(alpha: 0.5),
                        onPressed: _loading ? null : _handleSignIn,
                        child: _loading
                            ? const CupertinoActivityIndicator(color: Colors.white)
                            : Text(
                                'Sign In',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                      ),
                    ),
                  ),

                  SizedBox(height: isSmallScreen ? 12 : 14),

                  // ------------------------------
                  // Legal text: Terms & Privacy
                  // ------------------------------
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 4 : 8),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel,
                          height: 1.5,
                        ),
                        children: [
                          const TextSpan(text: 'By signing in, you agree to Wood Home\'s '),
                          TextSpan(
                            text: 'terms and conditions',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kBrown,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                Navigator.of(context, rootNavigator: true).push(
                                  CupertinoPageRoute(
                                    builder: (_) => const TermsAndConditionsScreen(),
                                  ),
                                );
                              },
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'privacy policy',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kBrown,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                Navigator.of(context, rootNavigator: true).push(
                                  CupertinoPageRoute(
                                    builder: (_) => const PrivacyPolicyScreen(),
                                  ),
                                );
                              },
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: isSmallScreen ? 24 : 32),

                  // ------------------------------
                  // Switch to Sign Up
                  // ------------------------------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Don\'t have an account? ',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: CupertinoColors.secondaryLabel,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _loading
                            ? null
                            : () {
                                Navigator.of(context, rootNavigator: true).push(
                                  CupertinoPageRoute(
                                    builder: (_) => const SignUpScreen(),
                                    fullscreenDialog: true,
                                  ),
                                );
                              },
                        child: Text(
                          'Sign Up',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: kBrown,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
          },
        ),
      ),
    );
  }
}








