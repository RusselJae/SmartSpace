import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Walnut-themed compact modal date picker shared across admin screens.
class AdminCompactDatePicker {
  AdminCompactDatePicker._();

  static const Color _walnut = Color(0xFF5D4037);

  static ThemeData _pickerTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      canvasColor: Colors.white,
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      colorScheme: base.colorScheme.copyWith(
        surface: Colors.white,
        onSurface: Colors.black87,
        primary: _walnut,
        onPrimary: Colors.white,
      ),
      datePickerTheme: base.datePickerTheme.copyWith(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: _walnut,
        headerForegroundColor: Colors.white,
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return Colors.black87;
        }),
        rangeSelectionBackgroundColor: const Color(0xFF8D6E63).withValues(alpha: 0.18),
        rangeSelectionOverlayColor: WidgetStateProperty.all(
          const Color(0xFF8D6E63).withValues(alpha: 0.10),
        ),
      ),
    );
  }

  static Widget _pickerBuilder(BuildContext context, Widget? child) {
    return Theme(
      data: _pickerTheme(context),
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  /// Opens the compact admin date picker; returns date at midnight local time.
  static Future<DateTime?> pick({
    required BuildContext context,
    required String helpText,
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? now,
      firstDate: firstDate ?? DateTime(now.year - 1, 1, 1),
      lastDate: lastDate ?? DateTime(now.year + 2, 12, 31),
      helpText: helpText,
      builder: _pickerBuilder,
    );
    if (picked == null) return null;
    return DateTime(picked.year, picked.month, picked.day);
  }

  static String formatButtonDate(DateTime date) => DateFormat.yMMMd().format(date);
}
