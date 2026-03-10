import 'dart:developer' as developer;

/// Helper class to handle deep links for email verification
class DeepLinkHandler {
  /// Extracts verification token from various URL formats
  /// Supports:
  /// - smartspace://verify-email?token=...
  /// - https://domain.com/verify-email?token=...
  /// - http://domain.com/verify-email?token=...
  static String? extractVerificationToken(String? url) {
    if (url == null || url.isEmpty) return null;

    try {
      // Parse the URL
      final uri = Uri.parse(url);
      
      // Check if it's a verification email link
      if (uri.path.contains('verify-email') || 
          uri.host == 'verify-email' ||
          uri.scheme == 'smartspace') {
        final token = uri.queryParameters['token'];
        if (token != null && token.isNotEmpty) {
          developer.log('✅ Extracted verification token from deep link');
          return token;
        }
      }
    } catch (e) {
      developer.log('⚠️ Failed to parse deep link URL: $e');
    }

    return null;
  }

  /// Checks if a URL is a verification email deep link
  static bool isVerificationLink(String? url) {
    if (url == null || url.isEmpty) return false;
    
    return url.contains('verify-email') || 
           url.startsWith('smartspace://');
  }
}





