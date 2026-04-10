import 'package:flutter/services.dart';

/// Philippine mobile numbers are commonly entered as 11 digits (e.g. 09xxxxxxxxx).
/// Strips non-digits and caps length at [maxDigits].
class PhilippinesPhoneDigitsFormatter extends TextInputFormatter {
  PhilippinesPhoneDigitsFormatter({this.maxDigits = 11});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated =
        digitsOnly.length > maxDigits ? digitsOnly.substring(0, maxDigits) : digitsOnly;
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}

/// Use on phone / "contact number" fields tied to checkout and profile.
List<TextInputFormatter> philippinesPhoneInputFormatters({int maxDigits = 11}) => [
      PhilippinesPhoneDigitsFormatter(maxDigits: maxDigits),
    ];
