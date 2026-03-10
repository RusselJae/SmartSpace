import '../utils/env_loader.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'dart:developer' as developer;

// Conditional import: web_config_web.dart for web, web_config_stub.dart for other platforms
import '../utils/web_config_stub.dart'
    if (dart.library.html) '../utils/web_config_web.dart';

class ApiConfig {
  /// Get the API base URL, checking multiple sources in order of priority:
  /// 1. For web: window.flutterConfig.apiBaseUrl (from index.html)
  /// 2. .env file: API_BASE_URL
  /// 3. Platform-specific defaults:
  ///    - Android: http://10.0.2.2:4000/api (works for emulator)
  ///    - iOS/Desktop: http://localhost:4000/api
  /// 
  /// For physical Android devices, you MUST set API_BASE_URL in .env to your computer's IP address
  /// (e.g., http://192.168.1.100:4000/api)
  static String get baseUrl {
    // For web platform, check window.flutterConfig first
    if (kIsWeb) {
      final webUrl = WebConfigHelper.getApiBaseUrl();
      if (webUrl != null && webUrl.isNotEmpty) {
        developer.log('🌐 Raw API URL from window.flutterConfig: $webUrl');
        final normalized = _normalizedBaseUrl(webUrl);
        developer.log('✅ Final normalized API URL: $normalized');
        return normalized;
      } else {
        developer.log('⚠️  window.flutterConfig.apiBaseUrl is null or empty');
      }
    }
    
    // Try .env file (works for mobile/desktop, and web if .env is in assets)
    final envValue = EnvLoader.get('API_BASE_URL');
    if (envValue.isNotEmpty) {
      developer.log('📝 Raw API URL from .env: $envValue');
      final normalized = _normalizedBaseUrl(envValue);
      developer.log('✅ Final normalized API URL: $normalized');
      return normalized;
    }
    
    // Platform-specific default fallback
    // Android emulator uses 10.0.2.2 to access host machine's localhost
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      developer.log('📱 Android detected - using emulator-friendly default: http://10.0.2.2:4000/api');
      developer.log('💡 For physical Android devices, set API_BASE_URL in .env to your computer IP');
      developer.log('💡 Example: API_BASE_URL=http://192.168.1.100:4000/api');
      developer.log('💡 Find your IP: Windows (ipconfig) or Mac/Linux (ifconfig)');
      return _normalizedBaseUrl('http://10.0.2.2:4000/api');
    }
    
    // Default for iOS, Desktop, and other platforms
    developer.log('📝 Using default API URL: http://localhost:4000/api');
    developer.log('💡 To use your IPv4 address, update API_BASE_URL in .env or window.flutterConfig.apiBaseUrl in index.html');
    return _normalizedBaseUrl('http://localhost:4000/api');
  }
  
  /// Get the API timeout duration
  static Duration get timeout {
    // For web, check window.flutterConfig first
    if (kIsWeb) {
      final webTimeout = WebConfigHelper.getApiTimeout();
      if (webTimeout != null && webTimeout > 0) {
        return Duration(seconds: webTimeout);
      }
    }
    
    // Try .env file
    final envTimeout = EnvLoader.getInt('API_TIMEOUT');
    if (envTimeout > 0) {
      return Duration(seconds: envTimeout);
    }
    
    // Default timeout
    return const Duration(seconds: 10);
  }

  /// Normalize the base URL by ensuring it has protocol, port, and removing trailing slashes and fragments
  static String _normalizedBaseUrl(String value) {
    if (value.isEmpty) {
      return 'http://localhost:4000/api';
    }
    
    // Remove any hash fragments (everything after #) - fragments are not sent to server
    String cleaned = value.contains('#') 
        ? value.substring(0, value.indexOf('#'))
        : value;
    
    // Remove trailing slashes
    String normalized = cleaned.endsWith('/') 
        ? cleaned.substring(0, cleaned.length - 1) 
        : cleaned;
    
    // Check if port :4000 is explicitly in the string
    final hasExplicitPort = RegExp(r':4000').hasMatch(normalized);
    
    // Ensure protocol is present (default to http://)
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      developer.log('⚠️  API URL missing protocol, adding http://');
      normalized = 'http://$normalized';
    }
    
    // Parse the URL to check if it has a port
    try {
      final uri = Uri.parse(normalized);
      
      // Check if port is missing or is the default port (80 for http, 443 for https)
      // We want to use port 4000 for our API, so if it's default or missing, add :4000
      final isDefaultPort = (uri.scheme == 'http' && uri.port == 80) || 
                            (uri.scheme == 'https' && uri.port == 443) ||
                            uri.port == 0;
      
      // If no explicit port in original string AND it's using default port, add :4000
      if (!hasExplicitPort && (isDefaultPort || uri.port == 0)) {
        developer.log('⚠️  API URL missing port :4000, adding it');
        // Reconstruct URI with port 4000, explicitly excluding fragments
        final scheme = uri.scheme.isEmpty ? 'http' : uri.scheme;
        final newUri = Uri(
          scheme: scheme,
          host: uri.host,
          port: 4000,
          path: uri.path,
          query: uri.query,
          // Explicitly set fragment to empty - we don't want fragments in API URLs
        );
        normalized = newUri.toString();
        developer.log('✅ Normalized API URL: $normalized');
      } else {
        // Even if port is correct, ensure no fragments
        if (uri.hasFragment) {
          developer.log('⚠️  Removing hash fragment from API URL');
          final cleanUri = Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.port,
            path: uri.path,
            query: uri.query,
            // No fragment
          );
          normalized = cleanUri.toString();
        }
      }
      
      return normalized;
    } catch (e) {
      developer.log('⚠️  Failed to parse API URL: $value, error: $e');
      developer.log('💡 Using default URL instead');
      return 'http://localhost:4000/api';
    }
  }
}

