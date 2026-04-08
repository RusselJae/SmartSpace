import '../config/api_config.dart';

/// Helper utility to normalize model paths for ModelViewer.
/// Handles both bundled assets and backend-served model URLs.
class ModelPathHelper {
  /// API origin for static files: strip trailing slashes and a trailing `/api` only.
  /// Using [replaceAll] on `/api` breaks hosts like `myapi.example.com`.
  static String _originFromApiBase() {
    var b = ApiConfig.baseUrl.trim();
    b = b.replaceAll(RegExp(r'/+$'), '');
    if (b.endsWith('/api')) {
      b = b.substring(0, b.length - 4);
    }
    return b;
  }

  static bool _isLoopbackHost(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '10.0.2.2' ||
        h == '0.0.0.0';
  }

  /// Private IPv4 ranges often appear in DB rows after local admin uploads;
  /// the app may later use a hosted API — rewrite media to that origin.
  static bool _isPrivateIpv4Host(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    final c = int.tryParse(parts[2]);
    final d = int.tryParse(parts[3]);
    if (a == null || b == null || c == null || d == null) return false;
    if (a == 192 && b == 168) return true;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  /// Files are mounted at `/uploads`, not `/api/uploads`. Fix mistaken prefixes.
  static String _fixUploadsPath(String path) {
    if (path.startsWith('/api/uploads')) {
      return path.substring(4); // -> /uploads...
    }
    if (path.startsWith('api/uploads/')) {
      return '/${path.substring(4)}'; // -> /uploads/...
    }
    return path;
  }

  /// Hostnames that used to serve `/uploads/*` but are no longer the active API (DB may still store them).
  static const Set<String> _legacyMediaHosts = {
    'smartspace-xhuu.onrender.com',
  };

  /// When the API stored a full URL to localhost/LAN or an old deploy host but the app now talks to another origin.
  static String _rewriteAbsoluteMediaUrlIfNeeded(String raw) {
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) return raw;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority) return raw;
    final apiUri = Uri.tryParse(ApiConfig.baseUrl);
    if (apiUri == null || !apiUri.hasAuthority) return raw;

    final mediaHost = uri.host.toLowerCase();
    final apiHost = apiUri.host.toLowerCase();

    final pathLower = uri.path.toLowerCase();
    final bool legacyHostedUploads =
        _legacyMediaHosts.contains(mediaHost) &&
            (pathLower.contains('/uploads/') || pathLower.endsWith('/uploads'));

    final bool mustRewrite = legacyHostedUploads ||
        _isLoopbackHost(mediaHost) ||
        (_isPrivateIpv4Host(mediaHost) && mediaHost != apiHost);

    if (!mustRewrite) return raw;

    var path = _fixUploadsPath(uri.path);
    final origin = _originFromApiBase();
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '$origin$path$query';
  }

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
    var raw = modelPath.trim().replaceAll('\\', '/');
    raw = _fixUploadsPath(raw);

    // If it's an asset path, return as-is
    if (raw.startsWith('assets/')) {
      return raw;
    }

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return _rewriteAbsoluteMediaUrlIfNeeded(raw);
    }

    // If it's a backend uploads path (relative), prefix with API base host
    if (raw.startsWith('/uploads') || raw.startsWith('uploads/')) {
      final base = _originFromApiBase();
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
      final base = _originFromApiBase();
      return '$base$tail';
    }
    if (raw.contains('backend/uploads/')) {
      final idx = raw.indexOf('backend/uploads/');
      final tail = raw.substring(idx + 'backend'.length); // /uploads/...
      final base = _originFromApiBase();
      return '$base/${tail.replaceFirst(RegExp(r'^/+'), '')}';
    }

    // If it doesn't start with assets/, assume it should
    if (!raw.contains('/')) {
      return 'assets/$raw';
    }

    // Default: return as-is (might be a full path)
    return raw;
  }

  /// Product [imageUrls] from the API are often `/uploads/images/...`.
  /// [Image.network] needs a full `http(s)://` URL — relative paths load blank on device.
  static String normalizeImageUrl(String value) {
    if (value.isEmpty) return value;
    var raw = value.trim().replaceAll('\\', '/');
    raw = _fixUploadsPath(raw);
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return _rewriteAbsoluteMediaUrlIfNeeded(raw);
    }
    if (raw.startsWith('/uploads') || raw.startsWith('uploads/')) {
      final base = _originFromApiBase();
      final normalizedPath = raw.startsWith('/') ? raw : '/$raw';
      return '$base$normalizedPath';
    }
    if (raw.contains('/backend/uploads/')) {
      final idx = raw.indexOf('/backend/uploads/');
      final tail = raw.substring(idx + '/backend'.length);
      return '${_originFromApiBase()}$tail';
    }
    if (raw.contains('backend/uploads/')) {
      final idx = raw.indexOf('backend/uploads/');
      final tail = raw.substring(idx + 'backend'.length);
      return '${_originFromApiBase()}/${tail.replaceFirst(RegExp(r'^/+'), '')}';
    }
    return raw;
  }
}

