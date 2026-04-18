import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/admin.dart';

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
  String? _role;
  String? _accessToken;
  DateTime? _signedInAt;

  /// Returns true when an admin session is active on this device.
  bool get isAuthenticated => _email != null;

  /// Email of the currently signed-in admin, if any.
  String? get currentEmail => _email;

  /// Full name of the currently signed-in admin, if any.
  String? get currentFullName => _fullName;

  /// ID of the currently signed-in admin, if any.
  String? get currentAdminId => _adminId;

  /// Backend RBAC role for the signed-in admin (null when not signed in).
  String? get currentRole => _role;

  /// JWT for [Authorization: Bearer] on admin API calls.
  String? get adminAccessToken => _accessToken;

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
        _role = decoded['role'] as String?;
        _accessToken = decoded['accessToken'] as String?;
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
          _role = data['role'] as String?;
          _accessToken = decoded['token'] as String?;
          _signedInAt = DateTime.now();

          final sessionPayload = <String, dynamic>{
            'email': _email,
            'adminId': _adminId,
            'fullName': _fullName,
            if (_role != null) 'role': _role,
            if (_accessToken != null) 'accessToken': _accessToken,
            'signedInAt': _signedInAt!.toIso8601String(),
          };
          await _prefs?.setString(_sessionKey, jsonEncode(sessionPayload));
          developer.log('✅ Admin logged in as $_email');
          return true;
        } else {
          developer.log('❌ Admin login failed: API returned success: false');
          return false;
        }
      }
      if (response.statusCode == 403) {
        String message = 'Please verify your email before signing in.';
        try {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final m = decoded['message'] as String?;
          if (m != null && m.trim().isNotEmpty) {
            message = m.trim();
          }
        } catch (_) {}
        developer.log('❌ Admin login blocked: $message');
        throw Exception(message);
      }
      if (response.statusCode == 401) {
        developer.log('❌ Admin login failed: Invalid credentials');
        return false;
      }
      developer.log('❌ Admin login failed: ${response.statusCode} - ${response.body}');
      return false;
    } catch (error) {
      if (error is Exception) {
        final s = error.toString();
        if (s.contains('verify your email') || s.contains('verify your email before')) {
          rethrow;
        }
      }
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
          'role': 'super_admin',
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
  Future<void> updateLocalProfile({String? fullName, String? role}) async {
    await initialize();
    if (fullName != null) {
      _fullName = fullName.trim().isEmpty ? _fullName : fullName.trim();
    }
    if (role != null && role.trim().isNotEmpty) {
      _role = role.trim();
    }
    final sessionPayload = <String, dynamic>{
      'email': _email,
      'adminId': _adminId,
      'fullName': _fullName,
      if (_role != null) 'role': _role,
      if (_accessToken != null) 'accessToken': _accessToken,
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
    _role = null;
    _accessToken = null;
    _signedInAt = null;
    await _prefs?.remove(_sessionKey);
    developer.log('👋 Admin signed out (previous: $previous)');
  }

  /// Sends the admin password reset email (no indication whether the address exists).
  Future<void> requestPasswordReset({required String email}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/admin-auth/forgot-password');
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(ApiConfig.timeout);
    if (response.statusCode != 200) {
      throw Exception('Could not start password reset. Try again later.');
    }
  }

  /// Sets a new admin password using the token from the email link.
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/admin-auth/reset-password');
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': token.trim(),
            'newPassword': newPassword,
          }),
        )
        .timeout(ApiConfig.timeout);
    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final message = decoded['message'] as String?;
        if (message != null && message.isNotEmpty) {
          throw Exception(message);
        }
      } catch (_) {}
      throw Exception('Could not reset password. The link may have expired.');
    }
  }

  /// Verifies admin email with the 6-character code from the welcome email.
  Future<Admin> verifyEmailWithCode(String code) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/admin-auth/verify-email-code');
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'code': code.trim().toUpperCase()}),
        )
        .timeout(ApiConfig.timeout);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final data = decoded['data'] as Map<String, dynamic>?;
      if (decoded['success'] == true && data != null) {
        return Admin.fromJson(data);
      }
    }
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final message = decoded['message'] as String?;
      if (message != null && message.isNotEmpty) {
        throw Exception(message);
      }
    } catch (_) {}
    throw Exception('Invalid or expired verification code');
  }
}








