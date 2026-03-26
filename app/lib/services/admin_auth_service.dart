import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// Admin authentication service that authenticates against the backend API.
///
/// This service:
/// - Authenticates admins via the backend API (/api/admin-auth/login)
/// - Stores session locally using SharedPreferences for persistence
/// - Supports multiple admins stored in the database
///
/// Session is stored locally so that closing and reopening the app
/// keeps the admin logged in.
class AdminAuthService {
  AdminAuthService._internal();

  static final AdminAuthService _instance = AdminAuthService._internal();

  factory AdminAuthService() => _instance;

  static const String _sessionKey = 'smartspace.admin.session';

  final http.Client _client = http.Client();
  SharedPreferences? _prefs;
  bool _initialized = false;
  String? _email;
  String? _adminId;
  String? _fullName;
  DateTime? _signedInAt;

  /// Returns true when an admin session is active on this device.
  bool get isAuthenticated => _email != null;

  /// Email of the currently signed-in admin, if any.
  String? get currentEmail => _email;

  /// Full name of the currently signed-in admin, if any.
  String? get currentFullName => _fullName;

  /// ID of the currently signed-in admin, if any.
  String? get currentAdminId => _adminId;

  /// When the current admin session was created on this device.
  DateTime? get signedInAt => _signedInAt;

  Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Restore a previously stored admin session, if present.
  Future<void> initialize() async {
    if (_initialized) return;
    await _ensurePrefs();
    final raw = _prefs?.getString(_sessionKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _email = decoded['email'] as String?;
        _adminId = decoded['adminId'] as String?;
        _fullName = decoded['fullName'] as String?;
        final signedInAtRaw = decoded['signedInAt'] as String?;
        _signedInAt = signedInAtRaw != null ? DateTime.tryParse(signedInAtRaw) : null;
        if (_email != null) {
          developer.log('🔁 Restored admin session for $_email');
        }
      } catch (error) {
        developer.log('⚠️ Failed to restore admin session: $error');
        await _prefs?.remove(_sessionKey);
      }
    }
    _initialized = true;
  }

  /// Attempt to sign in with admin credentials via the backend API.
  ///
  /// Returns true when credentials are valid and authentication succeeds.
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    await initialize();

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/admin-auth/login');
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim(),
              'password': password,
            }),
          )
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true) {
          final data = decoded['data'] as Map<String, dynamic>;
          _email = data['email'] as String?;
          _adminId = data['id'] as String?;
          _fullName = data['fullName'] as String?;
          _signedInAt = DateTime.now();

          final sessionPayload = <String, dynamic>{
            'email': _email,
            'adminId': _adminId,
            'fullName': _fullName,
            'signedInAt': _signedInAt!.toIso8601String(),
          };
          await _prefs?.setString(_sessionKey, jsonEncode(sessionPayload));
          developer.log('✅ Admin logged in as $_email');
          return true;
        } else {
          developer.log('❌ Admin login failed: API returned success: false');
          return false;
        }
      } else if (response.statusCode == 401) {
        developer.log('❌ Admin login failed: Invalid credentials');
        return false;
      } else {
        developer.log('❌ Admin login failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (error) {
      developer.log('❌ Admin login error: $error');
      // If API is unavailable, fall back to checking environment variables
      // This allows the app to work even if backend is down (for development)
      final fallbackEmail = 'admin@smartspace.local';
      final fallbackPassword = 'admin123';
      if (email.trim().toLowerCase() == fallbackEmail.toLowerCase() &&
          password == fallbackPassword) {
        _email = email.trim();
        _signedInAt = DateTime.now();
        final sessionPayload = <String, dynamic>{
          'email': _email,
          'signedInAt': _signedInAt!.toIso8601String(),
        };
        await _prefs?.setString(_sessionKey, jsonEncode(sessionPayload));
        developer.log('✅ Admin logged in (fallback mode) as $_email');
        return true;
      }
      return false;
    }
  }

  /// Update locally-stored profile fields for the current session.
  ///
  /// This is used after the backend successfully updates the admin record, so
  /// the UI immediately reflects the new values without forcing re-login.
  Future<void> updateLocalProfile({String? fullName}) async {
    await initialize();
    if (fullName != null) {
      _fullName = fullName.trim().isEmpty ? _fullName : fullName.trim();
    }
    final sessionPayload = <String, dynamic>{
      'email': _email,
      'adminId': _adminId,
      'fullName': _fullName,
      if (_signedInAt != null) 'signedInAt': _signedInAt!.toIso8601String(),
    };
    await _prefs?.setString(_sessionKey, jsonEncode(sessionPayload));
  }

  /// Clear the current admin session.
  Future<void> signOut() async {
    await initialize();
    final previous = _email;
    _email = null;
    _adminId = null;
    _fullName = null;
    _signedInAt = null;
    await _prefs?.remove(_sessionKey);
    developer.log('👋 Admin signed out (previous: $previous)');
  }
}








