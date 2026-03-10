import '../config/api_config.dart';

/// Helper utility to normalize model paths for ModelViewer.
/// Handles both bundled assets and backend-served model URLs.
class ModelPathHelper {
  /// Normalizes a model path to work with ModelViewer.
  /// 
  /// - Asset paths (assets/...) are returned as-is
  /// - `/uploads/...` paths are converted to absolute URLs using API_BASE_URL
  /// - Empty paths default to assets/chair.glb
  static String normalize(String modelPath) {
    if (modelPath.isEmpty) {
      return 'assets/chair.glb'; // Default fallback
    }

    // If it's an asset path, return as-is
    if (modelPath.startsWith('assets/')) {
      return modelPath;
    }

    // If it's a backend uploads path (relative), prefix with API base host
    if (modelPath.startsWith('/uploads') || modelPath.startsWith('uploads/')) {
      final base = ApiConfig.baseUrl.replaceAll('/api', '');
      // Ensure we have exactly one leading slash before 'uploads'
      final normalizedPath = modelPath.startsWith('/') ? modelPath : '/$modelPath';
      return '$base$normalizedPath';
    }

    // If it doesn't start with assets/, assume it should
    if (!modelPath.contains('/')) {
      return 'assets/$modelPath';
    }

    // Default: return as-is (might be a full path)
    return modelPath;
  }
}

