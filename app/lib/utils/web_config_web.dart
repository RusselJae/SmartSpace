// Web-specific implementation for accessing window.flutterConfig
// This file is only compiled for web builds
//
// Note: dart:html is deprecated but still functional. This conditional import
// only runs on web builds, so the deprecation warning is acceptable for now.
// ignore: avoid_web_libraries_in_flutter
// ignore: deprecated_member_use
import 'dart:html' as html;

/// Helper class for accessing window.flutterConfig on web platform
class WebConfigHelper {
  /// Get API base URL from window.flutterConfig
  static String? getApiBaseUrl() {
    try {
      final flutterConfig = (html.window as dynamic).flutterConfig;
      if (flutterConfig != null && flutterConfig['apiBaseUrl'] != null) {
        return flutterConfig['apiBaseUrl'] as String?;
      }
    } catch (e) {
      // window.flutterConfig not available
    }
    return null;
  }

  /// Get API timeout from window.flutterConfig
  static int? getApiTimeout() {
    try {
      final flutterConfig = (html.window as dynamic).flutterConfig;
      if (flutterConfig != null && flutterConfig['apiTimeout'] != null) {
        return flutterConfig['apiTimeout'] as int?;
      }
    } catch (e) {
      // window.flutterConfig not available
    }
    return null;
  }
}

