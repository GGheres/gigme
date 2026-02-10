import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  // Core background palette derived from the current web skin.
  static const Color background = Color(0xFF1C3F67);
  static const Color backgroundDeep = Color(0xFF173556);
  static const Color backgroundSoft = Color(0xFFF6F8FF);

  static const Color surface = Color(0xDBFFFFFF);
  static const Color surfaceStrong = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF2F5FF);

  static const Color textPrimary = Color(0xFF14161F);
  static const Color textSecondary = Color(0xFF5B606C);
  static const Color textInverse = Color(0xFFFFFFFF);

  static const Color primary = Color(0xFFFF7B1F);
  static const Color secondary = Color(0xFF3B7BFF);
  static const Color tertiary = Color(0xFF66D364);
  static const Color accentPurple = Color(0xFF6A4CFF);

  static const Color success = Color(0xFF66D364);
  static const Color warning = Color(0xFFF2C678);
  static const Color danger = Color(0xFFFF5D5D);
  static const Color info = Color(0xFF3B7BFF);

  static const Color border = Color(0x1F14161F);
  static const Color borderStrong = Color(0x3314161F);
  static const Color focusRing = Color(0x663B7BFF);

  static const LinearGradient appBackgroundGradientWide = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFF2B5FA5),
      Color(0xFF3AA6C6),
      Color(0xFF7FD0B7),
      Color(0xFFF2C678),
      Color(0xFFA88BD5),
    ],
    stops: <double>[0.0, 0.32, 0.52, 0.72, 1.0],
  );

  static const LinearGradient appBackgroundGradientTall = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF2F68B7),
      Color(0xFF49B8D2),
      Color(0xFF9FDC9D),
      Color(0xFFF5C06C),
      Color(0xFF946CC4),
    ],
    stops: <double>[0.0, 0.38, 0.56, 0.78, 1.0],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xF5FFFFFF),
      Color(0xE6F5F7FF),
    ],
  );

  static const LinearGradient panelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0x2EFF7B1F),
      Color(0x2966D364),
      Color(0x333B7BFF),
    ],
  );

  static const LinearGradient primaryButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[primary, accentPurple],
  );

  static const LinearGradient secondaryButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[tertiary, secondary],
  );

  static const LinearGradient dangerButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[danger, Color(0xFFFF8A8A)],
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
    shadow: Color(0x33141022),
  );
}
