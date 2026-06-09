import '../models/product.dart';
import '../utils/model_path_helper.dart';
import 'model_file_cache.dart';
import 'mysql_database_service.dart';

/// =============================================================
/// CatalogModelPrefetch
///
/// Downloads every remote GLB/GLTF for active storefront products into the
/// app support cache **in parallel** (deduped per URL inside the cache layer).
/// Second launch is fast: [ModelFileCacheService.resolveForViewer] hits disk
/// and returns immediately without another network fetch.
/// =============================================================
class CatalogModelPrefetch {
  CatalogModelPrefetch._();

  /// Remote http(s) model URLs only — bundled `assets/...` GLBs stay in the APK
  /// and must not be copied at startup (parallel 50MB loads OOM-crash the app).
  static Set<String> collectRemoteModelSources(Iterable<Product> products) {
    final sources = <String>{};
    for (final p in products) {
      if (p.isArchived) continue;
      final u = ModelPathHelper.normalize(p.modelPath).trim();
      if (u.isEmpty) continue;
      if (u.startsWith('assets/')) continue;
      if (!u.startsWith('http://') && !u.startsWith('https://')) continue;
      sources.add(u);
    }
    return sources;
  }

  /// Ensures remote GLB URLs exist on disk (one at a time). Skips bundled assets.
  static Future<void> warmCacheForStorefront() async {
    final db = MySQLDatabaseService();
    late final List<Product> products;
    try {
      products = await db.getAllProducts();
    } catch (_) {
      return;
    }

    final sources = collectRemoteModelSources(products);
    if (sources.isEmpty) return;

    try {
      final limited = sources.take(4).toList();
      await ModelFileCacheService.prefetchAll(limited)
          .timeout(const Duration(seconds: 45));
    } catch (_) {
      // Catalog still works; [CachedModelSrcLoader] falls back to the remote URL.
    }
  }
}
