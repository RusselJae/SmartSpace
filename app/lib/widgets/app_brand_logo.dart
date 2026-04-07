import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Centered app mark for [SplashScreen] and [LoadingScreen] (same decode quality).
class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({
    super.key,
    required this.layoutShortestSide,
  });

  /// `min(maxWidth, maxHeight)` from the surrounding [LayoutBuilder] / constraints.
  final double layoutShortestSide;

  @override
  Widget build(BuildContext context) {
    final maxSide = math.max(1.0, layoutShortestSide);
    final logoSide = maxSide * 0.58;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    const supersample = 1.35;
    final decodeEdge =
        (logoSide * dpr * supersample).round().clamp(1, 4096);

    return SizedBox(
      width: logoSide,
      height: logoSide,
      child: Image.asset(
        'assets/images/logo.jpg',
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        cacheWidth: decodeEdge,
        cacheHeight: decodeEdge,
        semanticLabel: 'Wood Home Furniture Trading logo',
      ),
    );
  }
}
