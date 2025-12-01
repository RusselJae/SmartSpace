import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

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

  /// Channel name kept short + unique to avoid collisions with other plugins.
  static const MethodChannel _channel = MethodChannel('com.smartspace/ar_support');

  /// Public entry point used by the AR view.
  Future<ArCapabilityResult> resolveCapability() async {
    // --- Step 1: Early exit when we already know the platform cannot use ARCore.
    if (!Platform.isAndroid) {
      return const ArCapabilityResult.viewerOnly(
        headline: 'ARCore is Android-only',
        detail: 'We can still show the model in 3D, but iOS needs QuickLook/USDC assets.',
      );
    }

    // --- Step 2: Filter out Huawei/Honor devices that cannot install Google services.
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      final String manufacturer = androidInfo.manufacturer.toUpperCase();
      final String brand = androidInfo.brand.toUpperCase();
      final bool isHuaweiFamily = manufacturer.contains('HUAWEI') || brand.contains('HUAWEI') || brand.contains('HONOR');
      if (isHuaweiFamily) {
        return const ArCapabilityResult.webFallback(
          headline: 'Google services unavailable',
          detail: 'Huawei/Honor devices cannot install Play Services for AR, so we drop to WebXR.',
        );
      }
    } catch (_) {
      // If device_info fails we optimistically continue so users still get a shot at ARCore/WebXR.
    }

    // --- Step 3: Ask the Android host (MainActivity) for the official ARCore status.
    Map<String, dynamic> nativeReport = <String, dynamic>{};
    try {
      final Map<dynamic, dynamic>? raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('checkArAvailability');
      if (raw != null) {
        nativeReport = raw.map((key, value) => MapEntry(key.toString(), value));
      }
    } on PlatformException catch (_) {
      // Missing channel usually means the user is running on emulators/old builds.
      return const ArCapabilityResult.webFallback(
        headline: 'AR service unavailable',
        detail: 'Device failed to report ARCore status. We lean on WebXR instead.',
      );
    }

    // --- Step 4: Derive a friendly capability state from the native response.
    final bool isSupported = nativeReport['isSupported'] == true;
    final bool isInstalled = nativeReport['isInstalled'] == true;
    final bool needsInstall = nativeReport['needsInstall'] == true;
    final bool isUnavailable = nativeReport['isUnavailable'] == true;

    if (isSupported && isInstalled) {
      return const ArCapabilityResult.sceneViewer(
        headline: 'Full AR ready',
        detail: 'Scene Viewer can launch immediately with accurate motion tracking.',
      );
    }

    if (isSupported && needsInstall) {
      return const ArCapabilityResult.sceneViewer(
        headline: 'Install AR services',
        detail: 'Google will prompt the user to add Play Services for AR before launching the scene.',
      );
    }

    if (!isSupported && !isUnavailable) {
      return const ArCapabilityResult.webFallback(
        headline: 'WebXR fallback',
        detail: 'Device cannot guarantee ARCore, but Chrome-based WebXR usually still works.',
      );
    }

    return const ArCapabilityResult.viewerOnly(
      headline: '3D only',
      detail: 'Sensors or Google services are missing, so we keep users inside the 3D viewer.',
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

