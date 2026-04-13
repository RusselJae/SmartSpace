import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../services/catalog_model_prefetch.dart';
import '../../widgets/splash_screen.dart';
import '../shell/tab_shell.dart';

/// Shown once after the user finishes onboarding: same branded splash while
/// storefront models fill the disk cache, then [TabShell] opens with tiles
/// ready to resolve from cache.
class PostOnboardingWarmupScreen extends StatefulWidget {
  const PostOnboardingWarmupScreen({super.key});

  @override
  State<PostOnboardingWarmupScreen> createState() =>
      _PostOnboardingWarmupScreenState();
}

class _PostOnboardingWarmupScreenState extends State<PostOnboardingWarmupScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final sw = Stopwatch()..start();
    final prefetchSw = Stopwatch()..start();
    try {
      await CatalogModelPrefetch.warmCacheForStorefront()
          .timeout(const Duration(seconds: 90));
    } catch (_) {}
    prefetchSw.stop();

    // Same idea as cold start: long first pull, snappy when the cache already has GLBs.
    final minBrand = prefetchSw.elapsedMilliseconds < 500
        ? const Duration(milliseconds: 900)
        : const Duration(milliseconds: 1800);
    final rem = minBrand - sw.elapsed;
    if (rem > Duration.zero) {
      await Future.delayed(rem);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(TabShell.route);
  }

  @override
  Widget build(BuildContext context) => const SplashScreen(
        footerHint: 'Caching 3D previews so the home screen opens smoothly…',
      );
}
