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
          return _normalizedBaseUrl(webUrl);
        }
        // Hard fallback when index.html has no flutterConfig (production web = Railway).
        return 'https://smartspace-production.up.railway.app/api';
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
    
    // Check if any port is explicitly provided (e.g. :4000, :443, :8080).
    //
    // We only auto-add :4000 for local/dev style hosts. In production, your API
    // will typically sit behind a reverse proxy (Railway, Vercel, Cloud Run),
    // and forcing :4000 breaks HTTPS deployments.
    final hasExplicitPort = RegExp(r':\d+').hasMatch(normalized);
    
    // Ensure protocol is present (default to http://)
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      developer.log('⚠️  API URL missing protocol, adding http://');
      normalized = 'http://$normalized';
    }
    
    // Parse the URL to check if it has a port
    try {
      final uri = Uri.parse(normalized);
      
      // If caller didn't specify a port, only auto-add :4000 for local/dev hosts.
      final bool looksLikeDevHost =
          uri.host == 'localhost' ||
          uri.host == '127.0.0.1' ||
          uri.host == '0.0.0.0' ||
          uri.host == '10.0.2.2' ||
          uri.host.startsWith('192.168.') ||
          uri.host.startsWith('10.') ||
          uri.host.startsWith('172.16.') ||
          uri.host.startsWith('172.17.') ||
          uri.host.startsWith('172.18.') ||
          uri.host.startsWith('172.19.') ||
          uri.host.startsWith('172.2') ||
          uri.host.startsWith('172.30.') ||
          uri.host.startsWith('172.31.');

      if (!hasExplicitPort && looksLikeDevHost) {
        developer.log('⚠️  Dev API URL missing port :4000, adding it');
        final scheme = uri.scheme.isEmpty ? 'http' : uri.scheme;
        final newUri = Uri(
          scheme: scheme,
          host: uri.host,
          port: 4000,
          path: uri.path,
          query: uri.query,
        );
        normalized = newUri.toString();
      }

      // Ensure no fragments (fragments are never sent to the server).
      if (uri.hasFragment) {
        developer.log('⚠️  Removing hash fragment from API URL');
        final cleanUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: uri.path,
          query: uri.query,
        );
        normalized = cleanUri.toString();
      }
      
      return normalized;
    } catch (e) {
      developer.log('⚠️  Failed to parse API URL: $value, error: $e');
      developer.log('💡 Using default URL instead');
      return 'http://localhost:4000/api';
    }
  }
}

