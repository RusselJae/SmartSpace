import '../utils/env_loader.dart';

class ApiConfig {
  static String get baseUrl {
    // For web, use default localhost URL
    // For mobile/desktop, try .env first, then default
    final envValue = EnvLoader.get('API_BASE_URL');
    if (envValue.isNotEmpty) {
      return _normalizedBaseUrl(envValue);
    }
    // Default for web and fallback
    return _normalizedBaseUrl('http://localhost:4000/api');
  }
  
  static Duration get timeout {
    final envTimeout = EnvLoader.getInt('API_TIMEOUT');
    if (envTimeout > 0) {
      return Duration(seconds: envTimeout);
    }
    return const Duration(seconds: 10);
  }

  static String _normalizedBaseUrl(String value) {
    if (value.isEmpty) {
      return 'http://localhost:4000/api';
    }
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}

