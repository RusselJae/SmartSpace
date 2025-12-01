import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../shell/tab_shell.dart';

/// =============================================================
/// OnboardingFlow
///
/// A modern, clean onboarding flow with centered content and
/// an illustration at the top. Introduces the app and guides
/// users to get started.
/// =============================================================
class OnboardingFlow extends StatelessWidget {
  const OnboardingFlow({super.key});

  void _goToApp(BuildContext context) {
    // Replace onboarding with the main tab shell. In a real app, we
    // would persist completion so onboarding isn't shown next launch.
    Navigator.of(context).pushReplacementNamed(TabShell.route);
  }

  @override
  Widget build(BuildContext context) {
    const Color kBrown = Color(0xFF8D6E63);
    const Color kLight = Color(0xFFF4E6D4);

    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // Illustration/Image at the top
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: kLight.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // AR/3D Icon Illustration
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kBrown.withValues(alpha: 0.1),
                            kBrown.withValues(alpha: 0.2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Icon(
                        CupertinoIcons.cube_box_fill,
                        size: 70,
                        color: kBrown,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // Centered Title
              Text(
                'Design your space\nin AR',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  height: 1.2,
                  decoration: TextDecoration.none,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Centered Subtitle
              Text(
                'Browse furniture and preview in your room',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.black,
                  height: 1.4,
                  decoration: TextDecoration.none,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              // Get Started Button
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  borderRadius: BorderRadius.circular(16),
                  color: kBrown,
                  onPressed: () => _goToApp(context),
                  child: Text(
                    'Get Started',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



