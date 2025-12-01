import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/user.dart';
import 'cart_service.dart';

/// Authentication service for user sign in and sign up
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final http.Client _client = http.Client();
  SharedPreferences? _prefs;
  User? _currentUser;
  bool _sessionLoaded = false;

  static const String _sessionKey = 'smartspace.user';

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  Future<void> initializeSession() async {
    if (_sessionLoaded) {
      return;
    }
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs?.getString(_sessionKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _currentUser = User.fromJson(decoded);
        developer.log('🔁 Restored session for ${_currentUser?.email}');
      } catch (e) {
        developer.log('⚠️ Failed to restore session: $e');
        await _prefs?.remove(_sessionKey);
      }
    }
    await CartService().syncWithUser(_currentUser?.id);
    _sessionLoaded = true;
  }

  Future<void> _persistUser(User user) async {
    await initializeSession();
    await _prefs?.setString(_sessionKey, jsonEncode(user.toJson()));
  }

  Future<void> updateCurrentUser(User user) async {
    _currentUser = user;
    await _persistUser(user);
    await CartService().syncWithUser(_currentUser?.id);
  }

  /// Sign up a new user
  Future<User> signUp({
    required String email,
    required String fullName,
    required String password,
    String? phoneNumber,
  }) async {
    developer.log('📝 Signing up user: $email');
    
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/users');
      final payload = {
        'email': email,
        'fullName': fullName,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
      };

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          _currentUser = User.fromJson(decoded['data'] as Map<String, dynamic>);
          await _persistUser(_currentUser!);
          await CartService().syncWithUser(_currentUser?.id);
          developer.log('✅ User signed up successfully: ${_currentUser?.email}');
          return _currentUser!;
        }
      }
      throw Exception('Failed to sign up: ${response.body}');
    } catch (e) {
      developer.log('❌ Sign up failed: $e');
      rethrow;
    }
  }

  /// Sign in an existing user (checks if user exists by email)
  Future<User> signIn({
    required String email,
    required String password,
  }) async {
    developer.log('🔐 Signing in user: $email');
    
    try {
      // Get all users and find by email
      final uri = Uri.parse('${ApiConfig.baseUrl}/users');
      final response = await _client.get(uri).timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          final usersList = decoded['data'] as List;
          final users = usersList.map((u) => User.fromJson(u as Map<String, dynamic>)).toList();
          
          // Find user by email (simple check - in production, use proper auth)
          final user = users.firstWhere(
            (u) => u.email.toLowerCase() == email.toLowerCase(),
            orElse: () => throw Exception('Invalid username or password'),
          );

          _currentUser = user;
          await _persistUser(user);
          await CartService().syncWithUser(_currentUser?.id);
          developer.log('✅ User signed in successfully: ${_currentUser?.email}');
          return _currentUser!;
        }
      }
      throw Exception('Invalid username or password');
    } catch (e) {
      developer.log('❌ Sign in failed: $e');
      throw Exception('Invalid username or password');
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    _currentUser = null;
    await initializeSession();
    await _prefs?.remove(_sessionKey);
    await CartService().syncWithUser(null);
    developer.log('👋 User signed out');
  }

  /// Sign in with Google (placeholder - requires Google Sign In package)
  Future<User> signInWithGoogle() async {
    developer.log('🔐 Signing in with Google...');
    // TODO: Implement Google Sign In
    throw UnimplementedError('Google Sign In not yet implemented');
  }

  /// Sign in with Facebook (placeholder - requires Facebook Login package)
  Future<User> signInWithFacebook() async {
    developer.log('🔐 Signing in with Facebook...');
    // TODO: Implement Facebook Login
    throw UnimplementedError('Facebook Login not yet implemented');
  }
}


