/// Matches backend [STRONG_PASSWORD_MESSAGE] for admin + password reset flows.
class PasswordPolicy {
  PasswordPolicy._();

  static const String strongPasswordMessage =
      'Password must be at least 12 characters and include uppercase, lowercase, a number, and a symbol.';

  static final RegExp _special = RegExp(r'''[!@#$%^&*()_+\-=[\]{};':"\\|,.<>/?]''');

  /// Returns null if valid, otherwise the user-facing error message.
  static String? validateStrongPassword(String raw) {
    final p = raw.trim();
    if (p.length < 12) return strongPasswordMessage;
    if (!RegExp(r'[A-Z]').hasMatch(p)) return strongPasswordMessage;
    if (!RegExp(r'[a-z]').hasMatch(p)) return strongPasswordMessage;
    if (!RegExp(r'[0-9]').hasMatch(p)) return strongPasswordMessage;
    if (!_special.hasMatch(p)) return strongPasswordMessage;
    return null;
  }
}
