import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const Color background = Color(0xFF101A35);
  static const Color backgroundDeep = Color(0xFF0A1228);
  static const Color backgroundSoft = Color(0xFFF4F7FC);

  static const Color surface = Color(0xF8FFFFFF);
  static const Color surfaceStrong = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEAF0FA);

  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF4B5565);
  static const Color textInverse = Color(0xFFFFFFFF);

  static const Color primary = Color(0xFF5868F9);
  static const Color secondary = Color(0xFF2AC9C5);
  static const Color tertiary = Color(0xFF7BD88F);
  static const Color accentPurple = Color(0xFF7B7EFF);

  static const Color success = Color(0xFF1D9A52);
  static const Color warning = Color(0xFFE49E34);
  static const Color danger = Color(0xFFD74242);
  static const Color info = Color(0xFF3569F6);

  static const Color border = Color(0x1F111827);
  static const Color borderStrong = Color(0x33111827);
  static const Color focusRing = Color(0x805868F9);

  static const Color darkSurface = Color(0xFF16244A);
  static const Color darkSurfaceStrong = Color(0xFF1A2B55);
  static const Color darkSurfaceMuted = Color(0xFF223665);
  static const Color darkTextPrimary = Color(0xFFF3F6FF);
  static const Color darkTextSecondary = Color(0xFFB3C2E8);
  static const Color darkBorder = Color(0x33DDE7FF);
  static const Color darkBorderStrong = Color(0x4DDDE7FF);

  static const LinearGradient appBackgroundGradientWide = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFF1A2B55),
      Color(0xFF101E43),
      Color(0xFF0A1228),
    ],
    stops: <double>[0.0, 0.55, 1.0],
  );

  static const LinearGradient appBackgroundGradientTall = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF1A2B55),
      Color(0xFF111E41),
      Color(0xFF0A1228),
    ],
    stops: <double>[0.0, 0.48, 1.0],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFF5F8FF),
    ],
  );

  static const LinearGradient panelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0x66335FCB),
      Color(0x55325BAF),
      Color(0x552A4C95),
    ],
  );

  static const LinearGradient primaryButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFF5868F9),
      Color(0xFF6B7AFB),
    ],
  );

  static const LinearGradient secondaryButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFF2AC9C5),
      Color(0xFF59D7B4),
    ],
  );

  static const LinearGradient dangerButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFFD74242),
      Color(0xFFEF6060),
    ],
  );

  static const ColorScheme lightColorScheme = ColorScheme.light(
    primary: primary,
    secondary: secondary,
    tertiary: tertiary,
    surface: surfaceStrong,
    onSurface: textPrimary,
    error: danger,
    onError: textInverse,
    outline: borderStrong,
    shadow: Color(0x29111A35),
  );

  static const ColorScheme darkColorScheme = ColorScheme.dark(
    primary: Color(0xFF8790FF),
    secondary: Color(0xFF54DDD7),
    tertiary: Color(0xFF91E2A1),
    surface: darkSurfaceStrong,
    onSurface: darkTextPrimary,
    error: Color(0xFFFF8B8B),
    onError: Color(0xFF390808),
    outline: darkBorderStrong,
    shadow: Color(0x66000000),
  );
}
