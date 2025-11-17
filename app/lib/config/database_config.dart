import '../utils/env_loader.dart';
import 'dart:developer' as developer;

/// Database configuration for MySQL connection
/// Uses environment variables for secure configuration
class DatabaseConfig {
  // Load from .env file or use defaults
  static String get host => EnvLoader.get('DB_HOST', 'localhost');
  static int get port => EnvLoader.getInt('DB_PORT', 3306);
  static String get database => EnvLoader.get('DB_NAME', 'smartspace_ar');
  static String get username => EnvLoader.get('DB_USERNAME', 'root');
  static String get password => EnvLoader.get('DB_PASSWORD', 'password');
  
  // Connection timeout in seconds
  static int get timeout => EnvLoader.getInt('DB_TIMEOUT', 30);
  
  // Connection pool settings
  static int get maxConnections => EnvLoader.getInt('DB_MAX_CONNECTIONS', 10);
  static int get minConnections => EnvLoader.getInt('DB_MIN_CONNECTIONS', 2);
  
  // Application settings
  static String get appEnv => EnvLoader.get('APP_ENV', 'development');
  static bool get isDebug => EnvLoader.getBool('APP_DEBUG', true);
  
  // Security
  static String get jwtSecret => EnvLoader.get('JWT_SECRET', 'default_jwt_secret');
  static String get apiKey => EnvLoader.get('API_KEY', 'default_api_key');
  
  /// Print current configuration (for debugging)
  static void printConfig() {
    if (isDebug) {
      developer.log('🔧 Database Configuration:');
      developer.log('   Host: $host:$port');
      developer.log('   Database: $database');
      developer.log('   Username: $username');
      developer.log('   Password: ${password.replaceAll(RegExp(r'.'), '*')}');
      developer.log('   Environment: $appEnv');
      developer.log('   Debug Mode: $isDebug');
    }
  }
}


