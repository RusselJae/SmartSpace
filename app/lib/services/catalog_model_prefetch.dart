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

  /// Unique http(s) model URLs for catalog products (skips archived / empty).
  static Set<String> collectModelUrls(Iterable<Product> products) {
    final urls = <String>{};
    for (final p in products) {
      if (p.isArchived) continue;
      final u = ModelPathHelper.normalize(p.modelPath).trim();
      if (u.isEmpty) continue;
      if (!u.startsWith('http://') && !u.startsWith('https://')) continue;
      urls.add(u);
    }
    return urls;
  }

  /// Fetches the full product list and ensures each remote model exists on disk.
  static Future<void> warmCacheForStorefront() async {
    final db = MySQLDatabaseService();
    late final List<Product> products;
    try {
      products = await db.getAllProducts();
    } catch (_) {
      return;
    }

    final urls = collectModelUrls(products);
    if (urls.isEmpty) return;

    try {
      await ModelFileCacheService.prefetchAll(urls)
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      // Catalog still works; [CachedModelSrcLoader] falls back to the remote URL.
    }
  }
}
