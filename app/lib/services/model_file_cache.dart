import 'model_file_cache_io.dart' if (dart.library.html) 'model_file_cache_web.dart' as platform;

/// Persists remote GLB/GLTF files under app support storage so repeat views
/// do not re-download (especially after flaky or wiped backends).
///
/// On **web**, this is a no-op and the original URL is returned.
class ModelFileCacheService {
  ModelFileCacheService._();

  /// Returns a `src` string suitable for [ModelViewer]:
  /// - Web / non-http: unchanged
  /// - Mobile & desktop http(s): `file:///...` after cache hit or download
  static Future<String> resolveForViewer(String normalizedSrc) =>
      platform.resolveModelSourceForViewer(normalizedSrc);
}
