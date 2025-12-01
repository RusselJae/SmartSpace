import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../widgets/styled_text_field.dart';
import '../shell/tab_shell.dart';
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
  final AuthService _auth = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      // Close the fullscreen dialog and navigate to main app
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        CupertinoPageRoute(
          builder: (_) => const TabShell(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Invalid username or password';
        _loading = false;
      });
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.signInWithGoogle();
      if (!mounted) return;
      // Close the fullscreen dialog and navigate to main app
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        CupertinoPageRoute(
          builder: (_) => const TabShell(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Google Sign In is not yet available';
        _loading = false;
      });
    }
  }

  Future<void> _handleFacebookSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.signInWithFacebook();
      if (!mounted) return;
      // Close the fullscreen dialog and navigate to main app
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        CupertinoPageRoute(
          builder: (_) => const TabShell(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Facebook Sign In is not yet available';
        _loading = false;
      });
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
                    child: Icon(
                      CupertinoIcons.cube_box_fill,
                      size: isSmallScreen ? 40 : 50,
                      color: kBrown,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 6 : 8),
                  Text(
                    'SmartSpace',
                    style: GoogleFonts.poppins(
                      fontSize: isSmallScreen ? 20 : 24,
                      fontWeight: FontWeight.w700,
                      color: kTextPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 32 : 40),

                  // Error message
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.exclamationmark_circle, color: Colors.black, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: GoogleFonts.poppins(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 12 : 16),
                  ],

                  // ------------------------------
                  // Email field
                  // ------------------------------
                  StyledTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    placeholder: 'you@example.com',
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
                  SizedBox(height: isSmallScreen ? 20 : 24),

                  // ------------------------------
                  // Primary CTA
                  // ------------------------------
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      // Enhanced button with gradient and improved shadow
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8D6E63), Color(0xFFFF9800)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.3),
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

                  SizedBox(height: isSmallScreen ? 20 : 24),

                  // Divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: CupertinoColors.separator.withValues(alpha: 0.3))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'or continue with',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: CupertinoColors.secondaryLabel,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: CupertinoColors.separator.withValues(alpha: 0.3))),
                    ],
                  ),

                  SizedBox(height: isSmallScreen ? 20 : 24),

                  // ------------------------------
                  // Social login buttons
                  // ------------------------------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Google button
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _loading ? null : _handleGoogleSignIn,
                        child: Container(
                          width: isSmallScreen ? 50 : 56,
                          height: isSmallScreen ? 50 : 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'G',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF4285F4),
                              fontWeight: FontWeight.w700,
                              fontSize: isSmallScreen ? 20 : 24,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isSmallScreen ? 16 : 20),
                      // Facebook button
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _loading ? null : _handleFacebookSignIn,
                        child: Container(
                          width: isSmallScreen ? 50 : 56,
                          height: isSmallScreen ? 50 : 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1877F2),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'f',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: isSmallScreen ? 22 : 26,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ],
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








