import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_brand_logo.dart';

/// Transitional loading after login, logout, sign-out, etc. Logo + optional message.
/// Not used on cold start (see `SplashScreen`). Same 3-second duration as before.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    super.key,
    this.onComplete,
    this.message,
    this.footerHelper,
    this.nextRoute,
    this.nextBuilder,
  });

  /// Callback when loading completes (after 3 seconds)
  final VoidCallback? onComplete;

  /// Optional line shown under the logo (e.g. "Signing out…") — not used on cold start.
  final String? message;

  /// Always shown at the bottom while this screen runs (cold start uses [SplashScreen] instead).
  final String? footerHelper;

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
    _controller.dispose();
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
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.message != null) ...[
                              Text(
                                widget.message!,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: kCaption.withValues(alpha: 0.75),
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            Text(
                              widget.footerHelper ??
                                  'Hang tight — we are finishing up in the background.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: kCaption.withValues(alpha: 0.55),
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                            ),
                          ],
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
