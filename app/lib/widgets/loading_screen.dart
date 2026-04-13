import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_brand_logo.dart';

/// Shown after login, logout, or admin sign-out: logo + one short line (or animated “Loading…”).
/// No extra footer copy — cold start uses [SplashScreen] instead.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    super.key,
    this.onComplete,
    this.message,
    this.nextRoute,
    this.nextBuilder,
  });

  final VoidCallback? onComplete;

  /// e.g. “Welcome back!”, “Signing out…” — when null, shows animated Loading…
  final String? message;

  final String? nextRoute;
  final WidgetBuilder? nextBuilder;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _introController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _captionPulseController;
  late Animation<double> _captionOpacity;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutCubic),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutCubic),
    );

    _captionPulseController = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat(reverse: true);
    _captionOpacity = Tween<double>(begin: 0.52, end: 1.0).animate(
      CurvedAnimation(parent: _captionPulseController, curve: Curves.easeInOut),
    );

    _introController.forward();

    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      if (widget.nextRoute != null) {
        Navigator.of(context, rootNavigator: true)
            .pushReplacementNamed(widget.nextRoute!);
      } else if (widget.nextBuilder != null) {
        Navigator.of(context, rootNavigator: true).pushReplacement(
          CupertinoPageRoute(builder: widget.nextBuilder!),
        );
      } else if (widget.onComplete != null) {
        widget.onComplete!();
      }
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    _captionPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color kCaption = Color(0xFF6D4C41);

    return Scaffold(
      backgroundColor: Colors.white,
      body: ColoredBox(
        color: Colors.white,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final shortest = (constraints.maxWidth < constraints.maxHeight)
                  ? constraints.maxWidth
                  : constraints.maxHeight;

              return AnimatedBuilder(
                animation: _introController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: child,
                    ),
                  );
                },
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: AppBrandLogo(layoutShortestSide: shortest),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                        child: AnimatedBuilder(
                          animation: _captionPulseController,
                          builder: (context, child) => Opacity(
                            opacity: _captionOpacity.value,
                            child: child,
                          ),
                          child: widget.message != null
                              ? Text(
                                  widget.message!,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: kCaption.withValues(alpha: 0.88),
                                    height: 1.35,
                                  ),
                                )
                              : _AnimatedLoadingCaption(
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: kCaption.withValues(alpha: 0.88),
                                    height: 1.35,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// “Loading” with animated ellipsis (wait state when [LoadingScreen.message] is null).
class _AnimatedLoadingCaption extends StatefulWidget {
  const _AnimatedLoadingCaption({required this.style});

  final TextStyle style;

  @override
  State<_AnimatedLoadingCaption> createState() => _AnimatedLoadingCaptionState();
}

class _AnimatedLoadingCaptionState extends State<_AnimatedLoadingCaption> {
  static const _frames = ['Loading', 'Loading.', 'Loading..', 'Loading...'];
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % _frames.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _frames[_i],
      textAlign: TextAlign.center,
      style: widget.style,
    );
  }
}
