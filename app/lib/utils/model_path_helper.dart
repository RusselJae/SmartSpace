import '../config/api_config.dart';

/// Helper utility to normalize model paths for ModelViewer.
/// Handles both bundled assets and backend-served model URLs.
class ModelPathHelper {
  /// Normalizes a model path to work with ModelViewer.
  /// 
  /// - Asset paths (assets/...) are returned as-is
  /// - `/uploads/...` paths are converted to absolute URLs using API_BASE_URL
  /// - Empty paths return an empty string (so callers can fall back)
  static String normalize(String modelPath) {
    if (modelPath.isEmpty) {
      return '';
    }

    // Normalize separators first so Windows-style paths can be recognized.
    final raw = modelPath.trim().replaceAll('\\', '/');

    // If it's an asset path, return as-is
    if (raw.startsWith('assets/')) {
      return raw;
    }

    // If already absolute URL, keep as-is.
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    // If it's a backend uploads path (relative), prefix with API base host
    if (raw.startsWith('/uploads') || raw.startsWith('uploads/')) {
      final base = ApiConfig.baseUrl.replaceAll('/api', '');
      // Ensure we have exactly one leading slash before 'uploads'
      final normalizedPath = raw.startsWith('/') ? raw : '/$raw';
      return '$base$normalizedPath';
    }

    // Handle local-ish backend paths such as:
    // - backend/uploads/models/foo.glb
    // - C:/.../backend/uploads/models/foo.glb
    // by trimming to /uploads/... and prefixing API host.
    if (raw.contains('/backend/uploads/')) {
      final idx = raw.indexOf('/backend/uploads/');
      final tail = raw.substring(idx + '/backend'.length); // /uploads/...
      final base = ApiConfig.baseUrl.replaceAll('/api', '');
      return '$base$tail';
    }
    if (raw.contains('backend/uploads/')) {
      final idx = raw.indexOf('backend/uploads/');
      final tail = raw.substring(idx + 'backend'.length); // /uploads/...
      final base = ApiConfig.baseUrl.replaceAll('/api', '');
      return '$base/${tail.replaceFirst(RegExp(r'^/+'), '')}';
    }

    // If it doesn't start with assets/, assume it should
    if (!raw.contains('/')) {
      return 'assets/$raw';
    }

    // Default: return as-is (might be a full path)
    return raw;
  }
}

