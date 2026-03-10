import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import 'mysql_database_service.dart';

/// Service for managing application settings
/// 
/// Settings can be stored locally (for offline access) and synced with the backend
/// for multi-device consistency. Admins can update settings through the admin panel.
class AppSettingsService {
  static final AppSettingsService _instance = AppSettingsService._internal();
  factory AppSettingsService() => _instance;
  AppSettingsService._internal();

  static const String _settingsKey = 'app_settings';
  AppSettings? _cachedSettings;
  final MySQLDatabaseService _db = MySQLDatabaseService();

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// Load settings from local storage or backend
  /// 
  /// Tries to load from backend first, then falls back to local storage
  Future<AppSettings> loadSettings() async {
    // Return cached settings if available
    if (_cachedSettings != null) {
      return _cachedSettings!;
    }

    try {
      // Try to load from backend first
      if (_db.isConnected) {
        try {
          // TODO: Implement backend API endpoint for settings
          // For now, we'll use local storage
          // final settings = await _db.getAppSettings();
          // _cachedSettings = settings;
          // return settings;
        } catch (e) {
          // Fall back to local storage if backend fails
        }
      }
    } catch (e) {
      // Fall back to local storage
    }

    // Load from local storage
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(_settingsKey);
    
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _cachedSettings = AppSettings.fromJson(json);
        return _cachedSettings!;
      } catch (e) {
        // If parsing fails, return default settings
      }
    }

    // Return default settings if nothing is stored
    _cachedSettings = const AppSettings();
    return _cachedSettings!;
  }

  /// Save settings to both local storage and backend
  /// 
  /// Saves locally for immediate access and syncs with backend for consistency
  Future<void> saveSettings(AppSettings settings) async {
    _cachedSettings = settings;

    // Save to local storage
    final prefs = await _ensurePrefs();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));

    // Try to save to backend
    try {
      if (_db.isConnected) {
        // TODO: Implement backend API endpoint for saving settings
        // await _db.saveAppSettings(settings);
      }
    } catch (e) {
      // If backend save fails, settings are still saved locally
      // This ensures the app continues to work even if backend is unavailable
    }
  }

  /// Clear cached settings (force reload on next access)
  void clearCache() {
    _cachedSettings = null;
  }
}


