import 'package:flutter/services.dart';

import '../models/product.dart';

/// ###########################################################################
/// ## NativeArEditorService                                                  ##
/// ###########################################################################
///
/// Thin Dart façade over the Kotlin-based AR editor.
///
/// Responsibilities:
/// - Keep the `MethodChannel` name (`com.smartspace/ar_editor`) in one place.
/// - Expose a single, high-level method that knows how to translate a
///   `Product` into the argument map expected on the native side.
/// - Fail silently if the native editor is unavailable so the primary AR
///   flow (Scene Viewer / WebXR) remains unaffected.
class NativeArEditorService {
  NativeArEditorService._();

  static const MethodChannel _channel = MethodChannel('com.smartspace/ar_editor');

  /// Launches the native AR editor for the given [product].
  ///
  /// This method mirrors the parameters that `ArEditorActivity` expects:
  /// - `modelSrc`: GLB path or URL.
  /// - `altText`: Friendly name for the model.
  /// - `realWidthMeters` / `realHeightMeters` / `realDepthMeters`: optional
  ///   real-world dimensions used for true-to-scale correction.
  /// - `modelBaseScale`: base scale factor applied before any user edits.
  static Future<void> openForProduct(Product product) async {
    try {
      await _channel.invokeMethod<void>('openEditor', <String, dynamic>{
        'modelSrc': product.modelPath,
        'altText': product.name,
        'realWidthMeters': product.realWidthMeters,
        'realHeightMeters': product.realHeightMeters,
        'realDepthMeters': product.realDepthMeters,
        'modelBaseScale': product.modelBaseScale,
      });
    } on PlatformException {
      // We intentionally swallow errors here; if the native editor is missing
      // or misconfigured, we don't want to crash the shopping experience.
      // In a later iteration we can surface a soft warning via Toast/snackbar.
    }
  }
}

