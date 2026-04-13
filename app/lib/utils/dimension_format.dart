/// =============================================================
/// DimensionFormat
///
/// Storefront data is stored in **meters** (API / DB). Customer-facing
/// copy uses **decimal inches** for a single consistent unit (no cm/m mix).
/// =============================================================
class DimensionFormat {
  DimensionFormat._();

  /// Inches with a trailing `in` unit, or `-` when missing / non-positive.
  static String formatMetersAsInches(double? meters) {
    if (meters == null || meters <= 0) return '-';

    final inches = meters * 39.37007874015748;
    final rounded = inches.round();
    // Prefer a clean integer when we are effectively on a whole inch.
    if ((inches - rounded).abs() < 0.05) {
      return '$rounded in';
    }
    return '${inches.toStringAsFixed(1)} in';
  }

  /// Floor footprint (width × depth) shown in square inches for AR panels.
  static String formatSquareMetersAsSquareInches(double squareMeters) {
    if (squareMeters <= 0) return '-';
    final sqIn = squareMeters * 1550.003100006;
    if (sqIn >= 100) {
      return '${sqIn.toStringAsFixed(0)} sq in';
    }
    return '${sqIn.toStringAsFixed(1)} sq in';
  }

  // --- Admin product form: edit in inches, persist meters on the API ---------

  static const double _inchesPerMeter = 39.37007874015748;

  /// Plain numeric inches for a text field (no unit suffix). Pair with [inchesFieldToMeters] on save.
  static String metersToInchesFieldValue(double? meters, {int fractionDigits = 2}) {
    if (meters == null || meters <= 0) return '';
    final inches = meters * _inchesPerMeter;
    return inches.toStringAsFixed(fractionDigits);
  }

  /// Parses admin inch fields back to meters for API payloads.
  static double? inchesFieldToMeters(String text) {
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return v / _inchesPerMeter;
  }
}
