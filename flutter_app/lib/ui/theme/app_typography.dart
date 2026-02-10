import 'package:flutter/material.dart';

class AppTypography {
  const AppTypography._();

  // TODO(ui-fonts): add real brand font files in pubspec assets.
  static const String displayFontFamily = 'Bricolage Grotesque';
  static const String bodyFontFamily = 'Plus Jakarta Sans';
  static const List<String> fallbackFamily = <String>[
    'Segoe UI',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  static TextTheme get textTheme {
    TextStyle bodyStyle({
      required double size,
      FontWeight weight = FontWeight.w500,
      double height = 1.45,
      double? letterSpacing,
    }) {
      return TextStyle(
        fontFamily: bodyFontFamily,
        fontFamilyFallback: fallbackFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
      );
    }

    TextStyle displayStyle({
      required double size,
      FontWeight weight = FontWeight.w800,
      double height = 1.08,
      double? letterSpacing,
    }) {
      return TextStyle(
        fontFamily: displayFontFamily,
        fontFamilyFallback: fallbackFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
      );
    }

    return TextTheme(
      displayLarge: displayStyle(size: 52),
      displayMedium: displayStyle(size: 44),
      displaySmall: displayStyle(size: 36),
      headlineLarge: displayStyle(size: 30),
      headlineMedium: displayStyle(size: 26),
      headlineSmall: displayStyle(size: 22),
      titleLarge: displayStyle(size: 20, weight: FontWeight.w700, height: 1.2),
      titleMedium: bodyStyle(size: 18, weight: FontWeight.w700, height: 1.25),
      titleSmall: bodyStyle(size: 16, weight: FontWeight.w700, height: 1.25),
      bodyLarge: bodyStyle(size: 16),
      bodyMedium: bodyStyle(size: 14),
      bodySmall: bodyStyle(size: 12, height: 1.35),
      labelLarge: bodyStyle(size: 14, weight: FontWeight.w700, height: 1.2),
      labelMedium: bodyStyle(size: 13, weight: FontWeight.w700, height: 1.2),
      labelSmall: bodyStyle(size: 12, weight: FontWeight.w700, height: 1.15),
    );
  }
}
