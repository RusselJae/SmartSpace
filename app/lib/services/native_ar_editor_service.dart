import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_nav.dart';
import '../models/product.dart';
import '../screens/views/product_detail.dart';
import '../utils/model_path_helper.dart';
import 'mysql_database_service.dart';

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

  static bool _nativeInboundRegistered = false;

  /// Handles calls from Kotlin ([ArEditorActivity]) on the same channel used for [openEditor].
  static void registerNativeCallbacks() {
    if (_nativeInboundRegistered) return;
    _nativeInboundRegistered = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openProductDetail') return;
      final args = call.arguments;
      final productId = args is Map ? args['productId'] as String? : null;
      if (productId == null || productId.isEmpty) return;

      final nav = appNavigatorKey.currentState;
      if (nav == null) {
        debugPrint('openProductDetail: no navigator yet');
        return;
      }

      final db = MySQLDatabaseService();
      await db.initialize();
      Product? match;
      try {
        final all = await db.getAllProducts();
        for (final p in all) {
          if (p.id == productId) {
            match = p;
            break;
          }
        }
      } catch (e) {
        debugPrint('openProductDetail: load products failed: $e');
        return;
      }

      if (match == null) {
        debugPrint('openProductDetail: unknown productId=$productId');
        return;
      }

      final product = match;
      nav.push(
        CupertinoPageRoute<void>(
          builder: (_) => ProductDetailScreen(product: product),
        ),
      );
    });
  }

  // Canonical matcher so "Dining Chairs", " dining-chairs ", etc. can still
  // resolve to the same category bucket for variants.
  static String _normalizeCategory(String raw) {
    return raw.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static double? _finiteOrNull(double? value) {
    if (value == null) return null;
    return value.isFinite ? value : null;
  }

  static Map<String, dynamic> _variantToJson(Product p) {
    return <String, dynamic>{
      'productId': p.id,
      'name': p.name,
      'modelSrc': ModelPathHelper.normalize(p.modelPath),
      // First catalog image for circular thumbnails in native AR carousel.
      'thumbnailUrl': p.imageUrls.isNotEmpty ? p.imageUrls.first : '',
      'realWidthMeters': _finiteOrNull(p.realWidthMeters),
      'realHeightMeters': _finiteOrNull(p.realHeightMeters),
      'realDepthMeters': _finiteOrNull(p.realDepthMeters),
      'modelBaseScale': p.modelBaseScale.isFinite ? p.modelBaseScale : 1.0,
    };
  }

  /// Launches the native AR editor for the given [product].
  ///
  /// This method mirrors the parameters that `ArEditorActivity` expects:
  /// - `modelSrc`: GLB path or URL.
  /// - `altText`: Friendly name for the model.
  /// - `realWidthMeters` / `realHeightMeters` / `realDepthMeters`: optional
  ///   real-world dimensions used for true-to-scale correction.
  /// - `modelBaseScale`: base scale factor applied before any user edits.
  static Future<void> openForProduct(Product product) async {
    // Normalise the model path so native Android always receives either a
    // bundled asset path (assets/...) or a fully-qualified URL.
    final normalizedSrc = ModelPathHelper.normalize(product.modelPath);

    // Option A: build a same-category variant list. If this fails (DB not
    // ready, network error, etc.), we fall back to just the current product
    // so the AR editor still opens.
    String variantsJson;
    try {
      final db = MySQLDatabaseService();
      // Ensure API/mock mode is resolved before fetching variants.
      await db.initialize();
      List<Product> allProducts;
      try {
        allProducts = await db.getAllProducts();
      } catch (e) {
        // Retry once through the service's fallback path (API -> mock).
        debugPrint('AR variants fetch failed, retrying via fallback: $e');
        await db.retryConnection();
        allProducts = await db.getAllProducts();
      }

      // Keep only products that can actually be loaded as variants.
      final loadable = allProducts.where((p) {
        final src = ModelPathHelper.normalize(p.modelPath).trim();
        return !p.isArchived && src.isNotEmpty;
      }).toList();

      final targetCategory = _normalizeCategory(product.category);
      var variants = loadable
          .where((p) {
            final sameCategory = _normalizeCategory(p.category) == targetCategory;
            return sameCategory;
          })
          .toList();
      // Safety net: if category data is inconsistent and we only got the
      // current product, surface other non-archived products instead of
      // showing an almost-empty carousel.
      if (variants.length <= 1) {
        variants = List<Product>.from(loadable);
      }
      if (!variants.any((p) => p.id == product.id)) {
        variants.add(product);
      }
      variants.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      debugPrint(
        'AR variants prepared: all=${allProducts.length}, '
        'loadable=${loadable.length}, selected=${variants.length}, '
        'category="${product.category}"',
      );

      // Keep enough options for the vertical native carousel.
      final cappedVariants = variants.take(30).toList();
      final safeVariantPayload = <Map<String, dynamic>>[];
      for (final p in cappedVariants) {
        try {
          safeVariantPayload.add(_variantToJson(p));
        } catch (e) {
          // Skip bad records instead of collapsing the whole carousel.
          debugPrint('Skipping malformed AR variant ${p.id}: $e');
        }
      }
      if (safeVariantPayload.isEmpty) {
        safeVariantPayload.add(_variantToJson(product));
      }
      variantsJson = jsonEncode(
        safeVariantPayload,
      );
    } catch (e) {
      debugPrint('AR variants build failed: $e');
      // Last-resort fallback: still open AR even if variants cannot be built.
      variantsJson = jsonEncode([_variantToJson(product)]);
    }

    try {
      await _channel.invokeMethod<void>('openEditor', <String, dynamic>{
        'modelSrc': normalizedSrc,
        'altText': product.name,
        'realWidthMeters': product.realWidthMeters,
        'realHeightMeters': product.realHeightMeters,
        'realDepthMeters': product.realDepthMeters,
        'modelBaseScale': product.modelBaseScale,
        'initialProductId': product.id,
        'variantProductsJson': variantsJson,
      });
    } on PlatformException catch (e) {
      // Native editor unavailable; log for debugging. Could surface a Toast.
      debugPrint('Native AR editor failed to open: ${e.code} - ${e.message}');
    }
  }
}

