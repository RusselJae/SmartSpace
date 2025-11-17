import 'package:flutter/cupertino.dart';

import '../shell/tab_shell.dart';

/// =============================================================
/// OnboardingFlow
///
/// A minimal, focused onboarding flow that introduces the app and
/// collects initial consent. For now, this is a single screen with
/// a primary call-to-action that advances into the main app shell.
///
/// Design notes (Apple HIG):
/// - Clear hierarchy with a bold title, supportive subtitle, and a
///   single prominent primary button.
/// - Generous spacing and contrast to keep content breathable.
/// - Motion kept subtle; navigation uses native transitions.
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
    final theme = CupertinoTheme.of(context);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Welcome'),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 32),
              Text(
                'Design your space in AR',
                style: theme.textTheme.navLargeTitleTextStyle,
                textAlign: TextAlign.left,
              ),
              const SizedBox(height: 12),
              Text(
                'Browse furniture, preview in your room, and check out in minutes.',
                style: theme.textTheme.textStyle.copyWith(
                  color: CupertinoColors.secondaryLabel,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 32),
              // Placeholder for profile preferences & budget range; when
              // implementing, present segmented controls and sliders here.
              Container(
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGroupedBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Profile setup placeholder'),
                    SizedBox(height: 8),
                    Text('Style preferences, budget range, and camera permissions.'),
                  ],
                ),
              ),
              const Spacer(),
              CupertinoButton.filled(
                onPressed: () => _goToApp(context),
                child: const Text('Get Started'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}


