import 'package:flutter/material.dart';

abstract final class BluesColors {
  static const blue = Color(0xFF184AE8);
  static const navy = Color(0xFF101D3A);
  static const canvas = Color(0xFFF6F7F9);
  static const ink = Color(0xFF172544);
  static const muted = Color(0xFF5D6B82);
  static const line = Color(0xFFE3E7EF);
  static const paleBlue = Color(0xFFEDF2FF);
  static const gold = Color(0xFFE9C87A);
}

ThemeData bluesTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BluesColors.blue,
    primary: BluesColors.blue,
    surface: Colors.white,
    onSurface: BluesColors.ink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: BluesColors.canvas,
    fontFamily: 'Apple SD Gothic Neo',
    fontFamilyFallback: const ['Noto Sans KR', 'Malgun Gothic', 'sans-serif'],
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 14, height: 1.55),
      bodyLarge: TextStyle(fontSize: 15, height: 1.6),
    ),
    dividerColor: BluesColors.line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BluesColors.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BluesColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BluesColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: BluesColors.navy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
