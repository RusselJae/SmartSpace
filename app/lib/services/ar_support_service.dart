import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// ###########################################################################
/// ## ARSupportService                                                       ##
/// ###########################################################################
/// Even though `model_viewer_plus` gives us a convenient AR button, the heavy
/// lifting still relies on Google Play Services for AR (a.k.a ARCore). The
/// helper below centralizes all capability checks so we can gracefully decide
/// whether we should:
///   1. Launch Scene Viewer (full ARCore pipeline).
///   2. Offer a WebXR fallback when ARCore is missing or outdated.
///   3. Fall back to a plain 3D viewer when neither path is viable.
/// The extra verbosity and comments are intentional so future refactors can
/// immediately see *why* each branch exists.
class ArSupportService {
  ArSupportService._();
  static final ArSupportService instance = ArSupportService._();

  /// Public entry point used by the AR view.
  Future<ArCapabilityResult> resolveCapability() async {
    // --- Step 1: For web platforms, always enable WebXR
    if (kIsWeb) {
      return const ArCapabilityResult.webFallback(
        headline: 'WebXR available',
        detail: 'WebXR is available for AR previews in supported browsers.',
      );
    }

    // --- Step 2: On Android, optimistically prefer Scene Viewer / ARCore.
    //
    // Some OEMs (like Infinix) are not on Google's official ARCore list even
    // though users can still install Play Services for AR and successfully
    // launch Scene Viewer. The previous, strict ARCore check was blocking AR
    // on these devices, even when the native experience actually worked.
    //
    // To restore the previous behavior (and match what you saw before), we
    // now *always* attempt Scene Viewer on Android and let Google handle any
    // fallback or error UI. This keeps the AR button available and hands off
    // to ARCore whenever the device can handle it.
    if (Platform.isAndroid) {
      return const ArCapabilityResult.sceneViewer(
        headline: 'AR available',
        detail: 'Attempting to launch Scene Viewer / ARCore when supported.',
      );
    }

    // --- Step 3: Non‑Android native platforms fall back to WebXR / 3D only.
    return const ArCapabilityResult.webFallback(
      headline: 'WebXR fallback',
      detail: 'ARCore is Android-only, so we lean on WebXR or 3D preview here.',
    );
  }
}

/// Small immutable DTO so the widget layer can focus on presentation logic.
class ArCapabilityResult {
  const ArCapabilityResult._({
    required this.enableAr,
    required this.arModes,
    required this.headline,
    required this.detail,
    required this.usesWebFallback,
  });

  const ArCapabilityResult.sceneViewer({
    required String headline,
    required String detail,
  }) : this._(
          enableAr: true,
          arModes: const <String>['scene-viewer', 'webxr'],
          headline: headline,
          detail: detail,
          usesWebFallback: false,
        );

  const ArCapabilityResult.webFallback({
    required String headline,
    required String detail,
  }) : this._(
          enableAr: true,
          arModes: const <String>['webxr'],
          headline: headline,
          detail: detail,
          usesWebFallback: true,
        );

  const ArCapabilityResult.viewerOnly({
    required String headline,
    required String detail,
  }) : this._(
          enableAr: false,
          arModes: const <String>[],
          headline: headline,
          detail: detail,
          usesWebFallback: false,
        );

  final bool enableAr;
  final List<String> arModes;
  final String headline;
  final String detail;
  final bool usesWebFallback;

  bool get supportsSceneViewer => arModes.contains('scene-viewer');
  bool get supportsWebXr => arModes.contains('webxr');
  bool get hasAnyArMode => supportsSceneViewer || supportsWebXr;
}

