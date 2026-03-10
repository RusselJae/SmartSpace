import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/auth_service.dart';
import '../../widgets/styled_text_field.dart';
import '../../widgets/toast.dart';
import 'sign_in.dart';
import 'email_verification_screen.dart';

/// =============================================================
/// SignUpScreen (Cupertino) - 4-Step Process
///
/// Step 1: Email
/// Step 2: First Name & Last Name
/// Step 3: Birthday
/// Step 4: Username & Password
///
/// - Clean, modern layout following Apple HIG
/// - Optimized for phone screens without scrolling
/// - Smooth step transitions with spring animations
/// =============================================================
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  static const String route = '/auth/sign-up';

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();
  
  // Color constants - moved to class level for use in methods
  static const Color kTextPrimary = Color(0xFF6D4C41); // Medium brown for text
  static const Color kBrown = Color(0xFF8D6E63); // Primary brown
  static const Color kLight = Color(0xFFF4E6D4);
  
  // Step management
  int _currentStep = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  // Form controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  DateTime? _selectedBirthday;
  
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Navigate to next step with animation
  void _nextStep() {
    if (_currentStep < 3) {
      setState(() {
        _currentStep++;
      });
      _animationController.reset();
      _animationController.forward();
    }
  }

  // Navigate to previous step
  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _animationController.reset();
      _animationController.forward();
    }
  }

  // Validate and proceed to next step
  void _validateAndProceed() {
    switch (_currentStep) {
      case 0: // Email step
        if (_emailController.text.trim().isEmpty) {
          Toast.warning(context, 'Please enter your email');
          return;
        }
        // Basic email validation
        final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
        if (!emailRegex.hasMatch(_emailController.text.trim())) {
          Toast.warning(context, 'Please enter a valid email address');
          return;
        }
        _nextStep();
        break;
        
      case 1: // First Name & Last Name step
        if (_firstNameController.text.trim().isEmpty) {
          Toast.warning(context, 'Please enter your first name');
          return;
        }
        if (_lastNameController.text.trim().isEmpty) {
          Toast.warning(context, 'Please enter your last name');
          return;
        }
        _nextStep();
        break;
        
      case 2: // Birthday step
        if (_selectedBirthday == null) {
          Toast.warning(context, 'Please select your birthday');
          return;
        }
        // Check if user is at least 13 years old
        final now = DateTime.now();
        final age = now.year - _selectedBirthday!.year;
        if (age < 13 || (age == 13 && now.month < _selectedBirthday!.month) ||
            (age == 13 && now.month == _selectedBirthday!.month && now.day < _selectedBirthday!.day)) {
          Toast.warning(context, 'You must be at least 13 years old');
          return;
        }
        _nextStep();
        break;
        
      case 3: // Username & Password step
        _handleSignUp();
        break;
    }
  }

  // Final sign up submission
  Future<void> _handleSignUp() async {
    if (_usernameController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      Toast.warning(context, 'Please fill in all fields');
      return;
    }

    if (_passwordController.text.length < 6) {
      Toast.warning(context, 'Password must be at least 6 characters');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // Combine first name and last name for fullName
      final fullName = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}';
      final email = _emailController.text.trim();
      
      await _auth.signUp(
        email: email,
        fullName: fullName,
        password: _passwordController.text,
      );
      if (!mounted) return;
      
      // Navigate to email verification screen instead of welcome screen
      // Users must verify their email before they can login
      Navigator.of(context, rootNavigator: true).pushReplacement(
        CupertinoPageRoute(
          builder: (_) => EmailVerificationScreen(
            email: email,
            userName: fullName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      
      // Extract error message and provide user-friendly feedback
      String errorMessage = e.toString().replaceFirst('Exception: ', '');
      
      // Log detailed error for debugging
      debugPrint('❌ Sign up error: $e');
      debugPrint('   Error type: ${e.runtimeType}');
      if (e is TypeError) {
        debugPrint('   TypeError details: $e');
      }
      
      // Show user-friendly error message
      Toast.error(context, errorMessage);
    }
  }

  // Show date picker for birthday
  Future<void> _showDatePicker() async {
    final now = DateTime.now();
    final initialDate = _selectedBirthday ?? DateTime(now.year - 18, 1, 1);
    final firstDate = DateTime(now.year - 100);
    final lastDate = DateTime(now.year - 13);
    
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: kBrown,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: kTextPrimary,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: kBrown,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _selectedBirthday = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

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
          onPressed: _currentStep > 0
              ? _previousStep
              : () => Navigator.of(context).maybePop(),
          color: kBrown,
        ),
        middle: Text(
          'Sign Up',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight;
            final isSmallScreen = availableHeight < 700;
            
            return FadeTransition(
              opacity: _fadeAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ------------------------------
                    // Progress indicator
                    // ------------------------------
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: index == _currentStep ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: index <= _currentStep ? kBrown : CupertinoColors.systemGrey4,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    SizedBox(height: isSmallScreen ? 24 : 32),

                    // ------------------------------
                    // App Logo (only on first step)
                    // ------------------------------
                    if (_currentStep == 0) ...[
                      Container(
                        width: isSmallScreen ? 70 : 90,
                        height: isSmallScreen ? 70 : 90,
                        decoration: BoxDecoration(
                          color: kLight.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/logo.jpg',
                            width: isSmallScreen ? 70 : 90,
                            height: isSmallScreen ? 70 : 90,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      SizedBox(height: isSmallScreen ? 6 : 8),
                      Text(
                        'Wood Home Furniture Trading',
                        style: GoogleFonts.poppins(
                          fontSize: isSmallScreen ? 16 : 20,
                          fontWeight: FontWeight.w700,
                          color: kTextPrimary,
                          decoration: TextDecoration.none,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: isSmallScreen ? 28 : 36),
                    ],

                    // ------------------------------
                    // Step content
                    // ------------------------------
                    _buildStepContent(isSmallScreen, kTextPrimary, kBrown, kLight),

                    SizedBox(height: isSmallScreen ? 20 : 24),

                    // ------------------------------
                    // Continue/Submit button
                    // ------------------------------
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton.filled(
                        borderRadius: BorderRadius.circular(16),
                        color: kBrown,
                        disabledColor: kBrown.withValues(alpha: 0.5),
                        onPressed: _loading ? null : _validateAndProceed,
                        child: _loading
                            ? const CupertinoActivityIndicator(color: Colors.white)
                            : Text(
                                _currentStep == 3 ? 'Create Account' : 'Continue',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                      ),
                    ),

                    SizedBox(height: isSmallScreen ? 20 : 24),

                    // ------------------------------
                    // Switch to Sign In
                    // ------------------------------
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
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
                                    builder: (_) => const SignInScreen(),
                                    fullscreenDialog: true,
                                  ),
                                );
                              },
                          child: Text(
                            'Sign In',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: kBrown,
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

  // Build content for current step
  Widget _buildStepContent(bool isSmallScreen, Color kTextPrimary, Color kBrown, Color kLight) {
    switch (_currentStep) {
      case 0:
        return _buildEmailStep(isSmallScreen, kTextPrimary);
        case 1:
        return _buildFirstNameLastNameStep(isSmallScreen, kTextPrimary);
        case 2:
        return _buildBirthdayStep(isSmallScreen, kTextPrimary);
        case 3:
        return _buildUsernamePasswordStep(isSmallScreen, kTextPrimary);
      default:
        return const SizedBox.shrink();
    }
  }

  // Step 1: Email
  Widget _buildEmailStep(bool isSmallScreen, Color kTextPrimary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What\'s your email?',
          style: GoogleFonts.poppins(
            fontSize: isSmallScreen ? 22 : 26,
            fontWeight: FontWeight.w700,
            color: kTextPrimary,
            decoration: TextDecoration.none,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        Text(
          'We\'ll use this to keep your account secure',
          style: GoogleFonts.poppins(
            color: CupertinoColors.secondaryLabel,
            fontSize: isSmallScreen ? 14 : 16,
            decoration: TextDecoration.none,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isSmallScreen ? 28 : 36),
        StyledTextField(
          controller: _emailController,
          label: 'Email',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _validateAndProceed(),
          placeholder: 'you@example.com',
        ),
      ],
    );
  }

  // Step 2: First Name & Last Name
  Widget _buildFirstNameLastNameStep(bool isSmallScreen, Color kTextPrimary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tell us more about you',
          style: GoogleFonts.poppins(
            fontSize: isSmallScreen ? 22 : 26,
            fontWeight: FontWeight.w700,
            color: kTextPrimary,
            decoration: TextDecoration.none,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        Text(
          'Enter your first and last name',
          style: GoogleFonts.poppins(
            color: CupertinoColors.secondaryLabel,
            fontSize: isSmallScreen ? 14 : 16,
            decoration: TextDecoration.none,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isSmallScreen ? 28 : 36),
        StyledTextField(
          controller: _firstNameController,
          label: 'First Name',
          icon: Icons.person_outline,
          textInputAction: TextInputAction.next,
          placeholder: 'First name',
        ),
        SizedBox(height: isSmallScreen ? 16 : 20),
        StyledTextField(
          controller: _lastNameController,
          label: 'Last Name',
          icon: Icons.person_outline,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _validateAndProceed(),
          placeholder: 'Last name',
        ),
      ],
    );
  }

  // Step 2: Birthday
  Widget _buildBirthdayStep(bool isSmallScreen, Color kTextPrimary) {
    final dateFormat = DateFormat('MMMM d, yyyy');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'When\'s your birthday?',
          style: GoogleFonts.poppins(
            fontSize: isSmallScreen ? 22 : 26,
            fontWeight: FontWeight.w700,
            color: kTextPrimary,
            decoration: TextDecoration.none,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        Text(
          'You must be at least 13 years old',
          style: GoogleFonts.poppins(
            color: CupertinoColors.secondaryLabel,
            fontSize: isSmallScreen ? 14 : 16,
            decoration: TextDecoration.none,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isSmallScreen ? 28 : 36),
        GestureDetector(
          onTap: _showDatePicker,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: CupertinoColors.separator.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: isSmallScreen ? 12 : 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedBirthday != null
                        ? dateFormat.format(_selectedBirthday!)
                        : 'Select your birthday',
                    style: GoogleFonts.poppins(
                      color: _selectedBirthday != null
                          ? kTextPrimary
                          : CupertinoColors.placeholderText,
                      fontSize: 15,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Icon(
                  CupertinoIcons.calendar,
                  color: CupertinoColors.systemGrey,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Step 3: Username & Password
  Widget _buildUsernamePasswordStep(bool isSmallScreen, Color kTextPrimary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Create your account',
          style: GoogleFonts.poppins(
            fontSize: isSmallScreen ? 22 : 26,
            fontWeight: FontWeight.w700,
            color: kTextPrimary,
            decoration: TextDecoration.none,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        Text(
          'Choose a username and password',
          style: GoogleFonts.poppins(
            color: CupertinoColors.secondaryLabel,
            fontSize: isSmallScreen ? 14 : 16,
            decoration: TextDecoration.none,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isSmallScreen ? 28 : 36),
        StyledTextField(
          controller: _usernameController,
          label: 'Username',
          icon: Icons.alternate_email,
          textInputAction: TextInputAction.next,
          placeholder: 'Choose a username',
        ),
        SizedBox(height: isSmallScreen ? 16 : 20),
        StyledTextField(
          controller: _passwordController,
          label: 'Password',
          icon: Icons.lock_outline,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _validateAndProceed(),
          placeholder: '••••••••',
        ),
      ],
    );
  }
}
