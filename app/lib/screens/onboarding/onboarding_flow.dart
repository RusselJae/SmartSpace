import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/onboarding_storage.dart';
import '../shell/tab_shell.dart';

/// =============================================================
/// OnboardingFlow
///
/// Full-bleed [onboarding_background.png] with a light veil so copy stays legible.
/// Typography-forward, left-aligned Poppins + walnut primary. Three pages, dots,
/// Next / Get started at the bottom.
/// =============================================================
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const Color _kBrownDark = Color(0xFF6D4C41);
  static const Color _kWalnut = Color(0xFF5C4033);
  static const int _pageCount = 3;

  late final PageController _pageController;
  int _pageIndex = 0;

  Future<void> _goToApp(BuildContext context) async {
    await OnboardingStorage.markComplete();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacementNamed(TabShell.route);
  }

  void _handleNext() {
    if (_pageIndex < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      unawaited(_goToApp(context));
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <({String title, String body})>[
      (
        title: 'Design your space in AR',
        body: 'Drop full‑scale furniture into your room and see how it fits.'
      ),
      (
        title: 'Real furniture. Real materials.',
        body: 'Browse solid wood pieces that look the same in AR and in real life.'
      ),
      (
        title: 'Save favorites. Checkout fast.',
        body: 'Save what you love, compare options, and check out in a few taps.'
      ),
    ];

    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Hero photo fills the screen; bottom-weighted so furniture reads well.
          const Positioned.fill(
            child: Image(
              image: AssetImage('assets/images/onboarding_background.png'),
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.high,
            ),
          ),
          // Thin white wash so brown text stays readable on busy wood tones.
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  // Text & dots float over the background image
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (index) {
                        setState(() {
                          _pageIndex = index;
                        });
                      },
                      itemCount: pages.length,
                      itemBuilder: (context, index) {
                        final item = pages[index];
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 340),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  textAlign: TextAlign.left,
                                  style: GoogleFonts.poppins(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    height: 1.15,
                                    color: _kBrownDark,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  item.body,
                                  textAlign: TextAlign.left,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    height: 1.4,
                                    color:
                                        _kBrownDark.withValues(alpha: 0.78),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Three dots directly under paragraph
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children:
                                      List.generate(_pageCount, (dotIndex) {
                                    final bool isActive =
                                        dotIndex == _pageIndex;
                                    return AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      curve: Curves.easeOutCubic,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isActive
                                            ? _kBrownDark
                                            : _kBrownDark.withValues(
                                                alpha: 0.24),
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Bottom primary button: Next / Get started
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      // ~20% shorter than before (16 -> ~13)
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      borderRadius: BorderRadius.circular(16),
                      color: _kWalnut,
                      onPressed: _handleNext,
                      child: Text(
                        _pageIndex < 2 ? 'Next' : 'Get started',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}



