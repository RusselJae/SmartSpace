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
          try {
            // Parse user data with detailed error handling
            final userData = decoded['data'] as Map<String, dynamic>;
            developer.log('📦 User data from backend: $userData');
            
            // Check emailVerified field specifically
            if (userData.containsKey('emailVerified')) {
              developer.log('📧 emailVerified value: ${userData['emailVerified']} (type: ${userData['emailVerified'].runtimeType})');
            }
            
            _currentUser = User.fromJson(userData);
            await _persistUser(_currentUser!);
            await CartService().syncWithUser(_currentUser?.id);
            developer.log('✅ User signed up successfully: ${_currentUser?.email}');
            return _currentUser!;
          } catch (parseError) {
            developer.log('❌ Failed to parse user data: $parseError');
            developer.log('   Raw user data: ${decoded['data']}');
            rethrow;
          }
        }
      }
      
      // Handle specific error responses from backend
      // 409 Conflict - typically means email already exists
      if (response.statusCode == 409) {
        try {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final message = decoded['message'] as String? ?? 'Email address is already taken';
          throw Exception(message);
        } catch (_) {
          throw Exception('Email address is already taken');
        }
      }
      
      // Try to extract error message from response body if it's JSON
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final message = decoded['message'] as String?;
        if (message != null) {
          throw Exception(message);
        }
      } catch (_) {
        // If parsing fails, use the raw response body
      }
      
      throw Exception('Failed to sign up: ${response.body}');
    } catch (e) {
      developer.log('❌ Sign up failed: $e');
      rethrow;
    }
  }

  /// Sign in an existing user (checks if user exists by email)
  /// Also verifies that the user's email has been verified before allowing login
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

          // Check if email is verified - users cannot login until they verify their email
          if (!user.emailVerified) {
            developer.log('⚠️ Login blocked: Email not verified for ${user.email}');
            throw Exception('Please verify your email address before signing in. Check your inbox for the verification email.');
          }

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
      // Re-throw the exception with the original message (especially for email verification errors)
      rethrow;
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

  /// Verify user email using verification token
  /// Called when user clicks the verification link in their email
  Future<User> verifyEmail(String token) async {
    developer.log('✉️ Verifying email with token');
    
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/users/verify-email').replace(
        queryParameters: {'token': token},
      );
      final response = await _client.get(uri).timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          final user = User.fromJson(decoded['data'] as Map<String, dynamic>);
          
          // Update current user if it's the same user
          if (_currentUser?.id == user.id) {
            _currentUser = user;
            await _persistUser(user);
          }
          
          developer.log('✅ Email verified successfully: ${user.email}');
          return user;
        }
      }
      throw Exception('Failed to verify email');
    } catch (e) {
      developer.log('❌ Email verification failed: $e');
      rethrow;
    }
  }

  /// Verify user email using verification code
  /// Called when user manually enters the verification code
  Future<User> verifyEmailByCode(String code) async {
    developer.log('✉️ Verifying email with code');
    
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/users/verify-email-code');
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code.trim().toUpperCase()}),
      ).timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true && decoded['data'] != null) {
          final user = User.fromJson(decoded['data'] as Map<String, dynamic>);
          
          // Update current user if it's the same user
          if (_currentUser?.id == user.id) {
            _currentUser = user;
            await _persistUser(user);
          }
          
          developer.log('✅ Email verified successfully with code: ${user.email}');
          return user;
        }
      }
      
      // Try to extract error message
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final message = decoded['message'] as String?;
        if (message != null) {
          throw Exception(message);
        }
      } catch (_) {
        // If parsing fails, use default message
      }
      
      throw Exception('Invalid or expired verification code');
    } catch (e) {
      developer.log('❌ Email verification failed: $e');
      rethrow;
    }
  }

  /// Resend verification email for a user
  Future<void> resendVerificationEmail(String userId) async {
    developer.log('📧 Resending verification email for user: $userId');
    
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/users/$userId/resend-verification');
      final response = await _client.post(uri).timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true) {
          developer.log('✅ Verification email resent successfully');
          return;
        }
      }
      throw Exception('Failed to resend verification email');
    } catch (e) {
      developer.log('❌ Failed to resend verification email: $e');
      rethrow;
    }
  }
}


