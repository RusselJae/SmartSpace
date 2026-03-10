import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../widgets/toast.dart';
import 'sign_in.dart';

/// =============================================================
/// VerifyEmailScreen (Cupertino)
///
/// Screen that handles email verification when user clicks
/// the verification link in their email.
///
/// - Accepts token as query parameter
/// - Calls backend API to verify email
/// - Shows loading/success/error states
/// - Redirects to login screen after successful verification
/// =============================================================
class VerifyEmailScreen extends StatefulWidget {
  final String? token;

  const VerifyEmailScreen({
    super.key,
    this.token,
  });

  static const String route = '/verify-email';

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();
  bool _verifying = true;
  bool _verified = false;
  String? _errorMessage;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();

    // Extract token from widget or URL (for web deep linking)
    String? token = widget.token;
    
    // For web, also check URL query parameters
    if (kIsWeb && (token == null || token.isEmpty)) {
      final uri = Uri.base;
      token = uri.queryParameters['token'];
    }

    // Automatically verify email when screen loads if token is provided
    if (token != null && token.isNotEmpty) {
      _verifyEmail(token);
    } else {
      setState(() {
        _verifying = false;
        _errorMessage = 'Verification token is missing';
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Verifies the email using the provided token
  Future<void> _verifyEmail(String token) async {
    try {
      await _auth.verifyEmail(token);
      
      if (!mounted) return;
      
      setState(() {
        _verifying = false;
        _verified = true;
      });

      // Show success message
      Toast.success(context, 'Email verified successfully!');

      // Wait a moment to show success, then redirect to login
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      // Navigate to login screen
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        CupertinoPageRoute(
          builder: (_) => const SignInScreen(),
          fullscreenDialog: true,
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _verified = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
      Toast.error(context, _errorMessage ?? 'Failed to verify email');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Color palette matching the signup screen
    const Color kTextPrimary = Color(0xFF6D4C41);
    const Color kBrown = Color(0xFF8D6E63);
    const Color kLight = Color(0xFFF4E6D4);

    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      child: SafeArea(
        bottom: false,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ------------------------------
                // Icon
                // ------------------------------
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: kLight.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _verified
                        ? CupertinoIcons.check_mark_circled_solid
                        : _verifying
                            ? CupertinoIcons.mail
                            : CupertinoIcons.exclamationmark_circle,
                    size: 50,
                    color: _verified
                        ? CupertinoColors.systemGreen
                        : _verifying
                            ? kBrown
                            : CupertinoColors.systemRed,
                  ),
                ),
                const SizedBox(height: 32),

                // ------------------------------
                // Status Message
                // ------------------------------
                if (_verifying) ...[
                  Text(
                    'Verifying your email...',
                    style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: kTextPrimary,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const CupertinoActivityIndicator(radius: 20),
                ] else if (_verified) ...[
                  Text(
                    'Email verified!',
                    style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.systemGreen,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Redirecting to login...',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: CupertinoColors.secondaryLabel,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  Text(
                    'Verification failed',
                    style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.systemRed,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage ?? 'Invalid or expired verification token',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: CupertinoColors.secondaryLabel,
                      decoration: TextDecoration.none,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  // ------------------------------
                  // Retry / Go to Login button
                  // ------------------------------
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      borderRadius: BorderRadius.circular(16),
                      color: kBrown,
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true).pushReplacement(
                          CupertinoPageRoute(
                            builder: (_) => const SignInScreen(),
                            fullscreenDialog: true,
                          ),
                        );
                      },
                      child: Text(
                        'Go to Sign In',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}













