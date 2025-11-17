import 'package:flutter/material.dart';

class AdminPalette {
  const AdminPalette._();

  static const Color dark = Color(0xFF3E2723);
  static const Color brown = Color(0xFF5D4037);
  static const Color sand = Color(0xFFF4E6D4);
  static const Color clay = Color(0xFFD7BFA6);
  static const Color accent = Color(0xFF8D6E63);
  static const Color surface = Color(0xFFFFFBF7);
}

class AdminGradients {
  const AdminGradients._();

  static const LinearGradient hero = LinearGradient(
    colors: [Color(0xFF6D4C41), Color(0xFF8D6E63)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildAdminTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AdminPalette.brown,
      brightness: Brightness.light,
      surface: AdminPalette.surface,
    ),
    scaffoldBackgroundColor: AdminPalette.sand,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AdminPalette.dark, fontSize: 15),
    ),
    cardTheme: CardThemeData(
      color: AdminPalette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 1,
      shadowColor: AdminPalette.dark.withAlpha(20),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AdminPalette.sand,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide.none,
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AdminPalette.clay,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: const TextStyle(color: AdminPalette.dark, fontWeight: FontWeight.w600),
    ),
  );
}


