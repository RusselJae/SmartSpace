import 'package:flutter/services.dart';

/// Philippine mobile: exactly **11 digits**, prefix **09** (e.g. 09XXXXXXXXX).
/// Strips non-digits, enforces leading `09`, max length 11.
class PhilippinesPhoneDigitsFormatter extends TextInputFormatter {
  PhilippinesPhoneDigitsFormatter({this.maxDigits = 11});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final sanitized = sanitizePhilippinesMobileDigits(
      newValue.text.replaceAll(RegExp(r'\D'), ''),
      maxDigits: maxDigits,
    );
    return TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(offset: sanitized.length),
    );
  }

  /// Keeps only a valid partial `09…` sequence (max [maxDigits], default 11).
  static String sanitizePhilippinesMobileDigits(String digits, {int maxDigits = 11}) {
    if (digits.isEmpty) return '';

    // Must begin with 0; if user starts with 9, treat as 09…
    if (!digits.startsWith('0')) {
      if (digits.startsWith('9')) {
        return sanitizePhilippinesMobileDigits('0$digits', maxDigits: maxDigits);
      }
      final i = digits.indexOf('0');
      if (i < 0) return '';
      return sanitizePhilippinesMobileDigits(digits.substring(i), maxDigits: maxDigits);
    }

    if (digits.length >= 2 && digits[1] != '9') {
      return digits.substring(0, 1);
    }

    if (digits.length > maxDigits) {
      return digits.substring(0, maxDigits);
    }
    return digits;
  }
}

/// `true` when [text] is exactly 11 digits starting with `09`.
bool isValidPhilippinesMobile11(String text) {
  final d = text.replaceAll(RegExp(r'\D'), '');
  return d.length == 11 && d.startsWith('09');
}

/// Non-null error message when invalid or empty (when phone is required).
String? philippinesMobileRequiredError(String text) {
  final d = text.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return 'Phone number is required.';
  if (!isValidPhilippinesMobile11(text)) {
    return 'Use 11 digits starting with 09 (e.g. 09123456789).';
  }
  return null;
}

/// When phone is optional: only validate format if user typed something.
String? philippinesMobileOptionalError(String text) {
  final d = text.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return null;
  if (!isValidPhilippinesMobile11(text)) {
    return 'Use 11 digits starting with 09 (e.g. 09123456789).';
  }
  return null;
}

/// Use on phone / contact fields (checkout, profile, MTO).
List<TextInputFormatter> philippinesPhoneInputFormatters({int maxDigits = 11}) => [
      PhilippinesPhoneDigitsFormatter(maxDigits: maxDigits),
    ];
