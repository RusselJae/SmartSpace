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

  /// Keeps the Android Intent binder payload small (large JSON can crash on open).
  static const int _maxArGalleryModels = 48;

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

  static double? _finiteOrNull(double? value) {
    if (value == null) return null;
    return value.isFinite ? value : null;
  }

  static Map<String, dynamic> _variantToJson(Product p) {
    return <String, dynamic>{
      'productId': p.id,
      'name': p.name,
      'category': p.category.trim().isEmpty ? 'Other' : p.category.trim(),
      'modelSrc': ModelPathHelper.normalize(p.modelPath),
      // First catalog image for the native AR model gallery thumbnail.
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
    final normalizedPrimarySrc = ModelPathHelper.normalize(product.modelPath);

    // Never block the native Activity on a full-catalog scan (can freeze / OOM).
    String variantsJson;
    try {
      variantsJson = await _buildVariantsJson(product).timeout(
        const Duration(seconds: 2),
        onTimeout: () => jsonEncode([_variantToJson(product)]),
      );
    } catch (e) {
      debugPrint('AR variants build failed: $e');
      variantsJson = jsonEncode([_variantToJson(product)]);
    }

    try {
      await _channel.invokeMethod<void>('openEditor', <String, dynamic>{
        'modelSrc': normalizedPrimarySrc,
        'altText': product.name,
        'realWidthMeters': product.realWidthMeters,
        'realHeightMeters': product.realHeightMeters,
        'realDepthMeters': product.realDepthMeters,
        'modelBaseScale': product.modelBaseScale,
        'initialProductId': product.id,
        'variantProductsJson': variantsJson,
      });
    } on PlatformException catch (e) {
      debugPrint('Native AR editor failed to open: ${e.code} - ${e.message}');
    }
  }

  static Future<String> _buildVariantsJson(Product product) async {
    try {
      final db = MySQLDatabaseService();
      await db.initialize();
      List<Product> allProducts;
      try {
        allProducts = await db.getAllProducts();
      } catch (e) {
        debugPrint('AR variants fetch failed, retrying via fallback: $e');
        await db.retryConnection();
        allProducts = await db.getAllProducts();
      }

      // Keep only products that can actually be loaded as variants.
      final loadable = allProducts.where((p) {
        final src = ModelPathHelper.normalize(p.modelPath).trim();
        return !p.isArchived && src.isNotEmpty;
      }).toList();

      // Gallery shows the full catalog; category filtering happens in native UI.
      var variants = List<Product>.from(loadable);
      if (!variants.any((p) => p.id == product.id)) {
        variants.add(product);
      }
      variants.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Tapped product must be index 0 so native fallbacks never load the wrong GLB.
      final tappedIndex = variants.indexWhere((p) => p.id == product.id);
      if (tappedIndex > 0) {
        final tapped = variants.removeAt(tappedIndex);
        variants.insert(0, tapped);
      }

      // Cap gallery size but always keep the tapped product at the front.
      if (variants.length > _maxArGalleryModels) {
        final tapped = variants.firstWhere((p) => p.id == product.id);
        final rest = variants
            .where((p) => p.id != product.id)
            .take(_maxArGalleryModels - 1)
            .toList();
        variants = [tapped, ...rest];
      }

      debugPrint(
        'AR gallery prepared: all=${allProducts.length}, '
        'loadable=${loadable.length}, selected=${variants.length}',
      );

      final safeVariantPayload = <Map<String, dynamic>>[];
      // Include all available variants so the native gallery can show the full set.
      for (final p in variants) {
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
      return jsonEncode(safeVariantPayload);
    } catch (e) {
      debugPrint('AR variants payload failed: $e');
      return jsonEncode([_variantToJson(product)]);
    }
  }
}

