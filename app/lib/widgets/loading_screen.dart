import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Minimal, typography-first loading screen.
/// Keeps the same 3-second duration + navigation/callback behavior.
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
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Subtle motion only: fade + gentle slide.
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _controller.forward();

    // Wait 3 seconds then navigate or call onComplete
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      
      if (widget.nextRoute != null) {
        // Navigate to route
        Navigator.of(context, rootNavigator: true)
            .pushReplacementNamed(widget.nextRoute!);
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
    const Color kBrownDark = Color(0xFF6D4C41);
    const Color kSurface = Color(0xFFFFFBF7);

    return Scaffold(
      backgroundColor: kSurface,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: child,
              ),
            );
          },
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WOOD HOME',
                    textAlign: TextAlign.left,
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 0.8,
                      color: kBrownDark,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'FURNITURE',
                    textAlign: TextAlign.left,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      height: .5,
                      color: kBrownDark.withValues(alpha: 0.78),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'TRADING',
                    textAlign: TextAlign.left,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      height: .5,
                      color: kBrownDark.withValues(alpha: 0.78),
                      letterSpacing: 1.5,
                    ),
                  ),
                  if (widget.message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      widget.message!,
                      textAlign: TextAlign.left,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                        color: kBrownDark.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

