import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer' as developer;

/// Utility class for loading and managing environment variables
class EnvLoader {
  static bool _isLoaded = false;
  
  /// Load environment variables from .env file
  static Future<void> load() async {
    if (_isLoaded) return;
    
    try {
      await dotenv.load(fileName: ".env");
      _isLoaded = true;
      developer.log('✅ Environment variables loaded successfully');
    } catch (e) {
      developer.log('⚠️  Could not load .env file: $e');
      developer.log('📝 Using default configuration values');
      developer.log('💡 Create a .env file based on env.example for custom configuration');
    }
  }
  
  /// Get environment variable with optional default value
  static String get(String key, [String? defaultValue]) {
    return dotenv.env[key] ?? defaultValue ?? '';
  }
  
  /// Get environment variable as integer
  static int getInt(String key, [int? defaultValue]) {
    final value = dotenv.env[key];
    if (value == null) return defaultValue ?? 0;
    return int.tryParse(value) ?? defaultValue ?? 0;
  }
  
  /// Get environment variable as boolean
  static bool getBool(String key, [bool defaultValue = false]) {
    final value = dotenv.env[key]?.toLowerCase();
    if (value == null) return defaultValue;
    return value == 'true' || value == '1' || value == 'yes';
  }
  
  /// Check if environment variable exists
  static bool has(String key) {
    return dotenv.env.containsKey(key);
  }
  
  /// Get all environment variables (for debugging)
  static Map<String, String> getAll() {
    return Map.from(dotenv.env);
  }
  
  /// Check if running in development mode
  static bool get isDevelopment {
    return get('APP_ENV', 'development') == 'development';
  }
  
  /// Check if running in production mode
  static bool get isProduction {
    return get('APP_ENV', 'development') == 'production';
  }
  
  /// Check if debug mode is enabled
  static bool get isDebugMode {
    return getBool('APP_DEBUG', true);
  }
}






