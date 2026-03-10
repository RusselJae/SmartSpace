import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Beautiful loading screen with brown theme, graphics, and app branding
/// Displays for 3 seconds before transitioning to the next screen
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    super.key,
    this.onComplete,
    this.message,
    this.nextRoute,
    this.nextBuilder,
  });

  /// Callback when loading completes (after 3 seconds)
  final VoidCallback? onComplete;

  /// Optional message to display below the app name
  final String? message;

  /// Optional route name to navigate to after loading
  final String? nextRoute;

  /// Optional widget builder for next screen
  final WidgetBuilder? nextBuilder;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    
    // Animation controller for smooth transitions
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Fade in animation
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Scale animation for logo
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.elasticOut),
      ),
    );

    // Rotation animation for decorative elements
    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.linear,
      ),
    );

    // Start animations
    _controller.forward();

    // Wait 3 seconds then navigate or call onComplete
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      
      if (widget.nextRoute != null) {
        // Navigate to route
        Navigator.of(context, rootNavigator: true).pushReplacementNamed(widget.nextRoute!);
      } else if (widget.nextBuilder != null) {
        // Navigate to widget - use CupertinoPageRoute for Cupertino-style navigation
        Navigator.of(context, rootNavigator: true).pushReplacement(
          CupertinoPageRoute(builder: widget.nextBuilder!),
        );
      } else if (widget.onComplete != null) {
        // Call callback
        widget.onComplete!();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Brown color palette matching the app theme
    const Color kBrown = Color(0xFF8D6E63);
    const Color kBrownLight = Color(0xFFBCAAA4);
    const Color kBrownDark = Color(0xFF6D4C41);
    const Color kSurface = Color(0xFFFFFBF7);

    return Scaffold(
      backgroundColor: kSurface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kSurface,
              const Color(0xFFFFF8F0),
              kSurface,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Decorative circles in background
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer rotating circle
                          Transform.rotate(
                            angle: _rotationAnimation.value * 2 * 3.14159,
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: kBrownLight.withValues(alpha: 0.2),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          // Middle circle
                          Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: kBrown.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                          ),
                          // Main logo container with scale animation
                          Transform.scale(
                            scale: _scaleAnimation.value,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    kBrown,
                                    kBrownDark,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: kBrown.withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      CupertinoIcons.home,
                                      size: 60,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      // App name with elegant typography
                      Text(
                        'Wood Home',
                        style: GoogleFonts.poppins(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: kBrownDark,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Furniture Trading',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: kBrown,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (widget.message != null) ...[
                        const SizedBox(height: 24),
                        Text(
                          widget.message!,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: kBrownLight,
                          ),
                        ),
                      ],
                      const SizedBox(height: 48),
                      // Loading indicator
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(kBrown),
                          backgroundColor: kBrownLight.withValues(alpha: 0.2),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Decorative dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          3,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kBrown.withValues(
                                alpha: 0.3 + (index * 0.2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

