import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminPalette {
  const AdminPalette._();

  // Updated color palette: light brown to brown and orange tones
  // Removed all dark brown colors for a warmer, more inviting aesthetic
  static const Color textPrimary = Color(0xFF6D4C41); // Medium brown for text
  static const Color brown = Color(0xFF8D6E63); // Primary brown
  static const Color lightBrown = Color(0xFFBCAAA4); // Light brown
  static const Color orange = Color(0xFFFF9800); // Primary orange
  static const Color lightOrange = Color(0xFFFFB74D); // Light orange
  static const Color sand = Color(0xFFF4E6D4);
  static const Color clay = Color(0xFFD7BFA6);
  static const Color accent = Color(0xFF8D6E63);
  static const Color surface = Color(0xFFFFFBF7);
}

class AdminGradients {
  const AdminGradients._();

  // Updated gradient using brown and orange tones
  // Creates a warm, inviting feel without dark brown
  static const LinearGradient hero = LinearGradient(
    colors: [Color(0xFF8D6E63), Color(0xFFFF9800)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  // Subtle background gradient for depth
  static const LinearGradient background = LinearGradient(
    colors: [Color(0xFFFFFBF7), Color(0xFFF4E6D4)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

ThemeData buildAdminTheme() {
  // Updated text theme to use medium brown instead of dark brown
  final TextTheme baseTextTheme = GoogleFonts.poppinsTextTheme().apply(
    bodyColor: AdminPalette.textPrimary,
    displayColor: AdminPalette.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AdminPalette.brown,
      brightness: Brightness.light,
      surface: AdminPalette.surface,
    ),
    scaffoldBackgroundColor: AdminPalette.sand,
    textTheme: baseTextTheme,
    cardTheme: CardThemeData(
      color: AdminPalette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 2,
      shadowColor: AdminPalette.textPrimary.withAlpha(15),
      // Enhanced shadow for better depth perception
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
      labelStyle: const TextStyle(color: AdminPalette.textPrimary, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: baseTextTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}


