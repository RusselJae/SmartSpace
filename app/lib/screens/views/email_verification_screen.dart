import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import '../../widgets/toast.dart';
import 'sign_in.dart';

/// =============================================================
/// EmailVerificationScreen (Cupertino)
///
/// Screen shown after signup to inform users they need to verify
/// their email address before they can login.
///
/// - Clean, modern layout following Apple HIG
/// - Shows instructions and email address
/// - Option to resend verification email
/// - Link to sign in page (after verification)
/// =============================================================
class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String userName;

  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.userName,
  });

  static const String route = '/auth/email-verification';

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();
  final List<TextEditingController> _codeControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _resending = false;
  bool _verifying = false;
  String? _userId;
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
    
    // Set up code input boxes - auto-advance and format
    for (int i = 0; i < 6; i++) {
      _codeControllers[i].addListener(() {
        _handleCodeInput(i);
      });
    }
    
    // Try to find user ID by email to enable resend functionality
    _fetchUserId();
  }

  /// Handles input for individual code boxes
  /// Auto-advances to next box, converts to uppercase, filters invalid chars
  void _handleCodeInput(int index) {
    final controller = _codeControllers[index];
    final text = controller.text;
    
    if (text.isEmpty) return;
    
    // Get only the first character, uppercase, alphanumeric only
    final char = text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').substring(0, 1);
    
    if (text != char) {
      controller.value = TextEditingValue(
        text: char,
        selection: const TextSelection.collapsed(offset: 1),
      );
    }
    
    // Auto-advance to next box if character entered
    if (char.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    
    // Auto-verify when all 6 characters are entered
    if (index == 5 && char.isNotEmpty) {
      final fullCode = _codeControllers.map((c) => c.text).join();
      if (fullCode.length == 6) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _verifyWithCode();
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    for (var controller in _codeControllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  /// Verifies email using the entered code
  Future<void> _verifyWithCode() async {
    final code = _codeControllers.map((c) => c.text).join().toUpperCase();
    
    if (code.isEmpty || code.length != 6) {
      Toast.warning(context, 'Please enter a valid 6-character code');
      return;
    }

    setState(() {
      _verifying = true;
    });

    try {
      await _auth.verifyEmailByCode(code);
      
      if (!mounted) return;
      
      Toast.success(context, 'Email verified successfully!');
      
      // Wait a moment, then redirect to login
      await Future.delayed(const Duration(seconds: 1));
      
      if (!mounted) return;
      
      Navigator.of(context, rootNavigator: true).pushReplacement(
        CupertinoPageRoute(
          builder: (_) => const SignInScreen(),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
      });
      Toast.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Fetches the user ID by email so we can resend verification emails
  Future<void> _fetchUserId() async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/users');
      final response = await http.get(uri).timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          final usersList = decoded['data'] as List;
          final user = usersList.firstWhere(
            (u) => (u['email'] as String).toLowerCase() == widget.email.toLowerCase(),
            orElse: () => null,
          );
          
          if (user != null) {
            setState(() {
              _userId = user['id'] as String;
            });
          }
        }
      }
    } catch (e) {
      // Silently fail - resend will just show an error if needed
      debugPrint('Failed to fetch user ID: $e');
    }
  }

  /// Resends the verification email to the user
  Future<void> _resendVerificationEmail() async {
    if (_userId == null) {
      Toast.warning(context, 'Unable to resend email. Please try signing up again.');
      return;
    }

    setState(() {
      _resending = true;
    });

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/users/$_userId/resend-verification');
      final response = await http.post(uri).timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (!mounted) return;
        if (decoded['success'] == true) {
          Toast.success(context, 'Verification email sent! Check your inbox.');
        } else {
          Toast.error(context, decoded['message'] as String? ?? 'Failed to resend email');
        }
      } else {
        if (!mounted) return;
        Toast.error(context, 'Failed to resend verification email');
      }
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to resend verification email. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _resending = false;
        });
      }
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
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: kBrown,
        ),
        middle: Text(
          'Verify Email',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ------------------------------
                // Icon
                // ------------------------------
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: kLight.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.mail,
                    size: 30,
                    color: kBrown,
                  ),
                ),
                const SizedBox(height: 16),

                // ------------------------------
                // Title
                // ------------------------------
                Text(
                  'Check your email',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),

                // ------------------------------
                // Description
                // ------------------------------
                Text(
                  'We\'ve sent a verification code to',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),

                // ------------------------------
                // Email address
                // ------------------------------
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: kLight.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: kBrown.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    widget.email,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kBrown,
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),

                // ------------------------------
                // Instructions
                // ------------------------------
                Text(
                  'Enter the 6-digit code from your email',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // ------------------------------
                // Verification Code Input - 6 Boxes
                // ------------------------------
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (index) {
                    return Container(
                      margin: EdgeInsets.only(right: index < 5 ? 8 : 0),
                      width: 45,
                      height: 50,
                      child: TextField(
                        controller: _codeControllers[index],
                        focusNode: _focusNodes[index],
                        keyboardType: TextInputType.text,
                        textInputAction: index < 5 ? TextInputAction.next : TextInputAction.done,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 1,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: kBrown,
                          decoration: TextDecoration.none,
                        ),
                        onSubmitted: (value) {
                          if (value.isNotEmpty && index < 5) {
                            _focusNodes[index + 1].requestFocus();
                          } else if (index == 5 && value.isNotEmpty) {
                            _verifyWithCode();
                          }
                        },
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: kLight.withValues(alpha: 0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: kBrown.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: kBrown.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: kBrown,
                              width: 2,
                            ),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),

                // ------------------------------
                // Verify Code Button
                // ------------------------------
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    borderRadius: BorderRadius.circular(12),
                    color: kBrown,
                    disabledColor: kBrown.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: _verifying ? null : _verifyWithCode,
                    child: _verifying
                        ? const CupertinoActivityIndicator(color: Colors.white, radius: 10)
                        : Text(
                            'Verify Code',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              decoration: TextDecoration.none,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // ------------------------------
                // Divider
                // ------------------------------
                Row(
                  children: [
                    Expanded(child: Divider(color: CupertinoColors.separator.withValues(alpha: 0.3), height: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: CupertinoColors.separator.withValues(alpha: 0.3), height: 1)),
                  ],
                ),
                const SizedBox(height: 12),

                // ------------------------------
                // Resend button
                // ------------------------------
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    borderRadius: BorderRadius.circular(12),
                    color: kBrown.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: _resending ? null : _resendVerificationEmail,
                    child: _resending
                        ? const CupertinoActivityIndicator(color: kBrown, radius: 10)
                        : Text(
                            'Resend Email',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: kBrown,
                              decoration: TextDecoration.none,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),

                // ------------------------------
                // Already verified link
                // ------------------------------
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).pushReplacement(
                      CupertinoPageRoute(
                        builder: (_) => const SignInScreen(),
                        fullscreenDialog: true,
                      ),
                    );
                  },
                  child: Text(
                    'Already verified? Sign in',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kBrown,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}






