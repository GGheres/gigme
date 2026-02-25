import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radii.dart';
import 'app_shadows.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// buildAppTheme builds app theme.

ThemeData buildAppTheme({
  required Brightness brightness,
}) {
  final isDark = brightness == Brightness.dark;
  final textTheme = AppTypography.textTheme.apply(
    bodyColor: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
    displayColor: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
  );

  final colorScheme =
      isDark ? AppColors.darkColorScheme : AppColors.lightColorScheme;

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor:
        isDark ? AppColors.backgroundDeep : AppColors.backgroundSoft,
    fontFamily: AppTypography.bodyFontFamily,
    textTheme: textTheme,
    brightness: brightness,
  );

  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.lg),
  );

  final textPrimary =
      isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  final textSecondary =
      isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  final surface = isDark ? AppColors.darkSurface : AppColors.surface;
  final surfaceStrong =
      isDark ? AppColors.darkSurfaceStrong : AppColors.surfaceStrong;
  final border = isDark ? AppColors.darkBorder : AppColors.border;
  final borderStrong =
      isDark ? AppColors.darkBorderStrong : AppColors.borderStrong;
  final outlineButtonForeground =
      isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  final navUnselectedColor = isDark
      ? AppColors.darkTextPrimary.withValues(alpha: 0.78)
      : textSecondary.withValues(alpha: 0.86);
  final navSelectedColor = isDark ? AppColors.darkTextPrimary : textPrimary;

  return base.copyWith(
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: textPrimary),
      iconTheme: IconThemeData(color: textPrimary),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        side: BorderSide(color: border),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        foregroundColor: AppColors.textInverse,
        backgroundColor: AppColors.primary,
        elevation: 0,
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        minimumSize: const Size(0, AppTouchTargets.minSize),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        side: BorderSide(color: borderStrong),
        foregroundColor: outlineButtonForeground,
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        minimumSize: const Size(0, AppTouchTargets.minSize),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        foregroundColor: colorScheme.primary,
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, AppTouchTargets.minSize),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceStrong,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      labelStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      helperStyle: textTheme.bodySmall?.copyWith(color: textSecondary),
      errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.danger),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        borderSide: BorderSide(color: borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        borderSide: BorderSide(color: borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: borderStrong,
      thickness: 1,
      space: 1,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: surfaceStrong,
      selectedColor:
          colorScheme.primary.withValues(alpha: isDark ? 0.34 : 0.18),
      side: BorderSide(color: borderStrong),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      labelStyle: textTheme.labelMedium?.copyWith(color: textPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceStrong,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xxl),
      ),
      elevation: 0,
      shadowColor: Colors.transparent,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: navSelectedColor,
      unselectedLabelColor: navUnselectedColor,
      indicatorColor: colorScheme.primary,
      dividerColor: borderStrong,
      labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle:
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      overlayColor: WidgetStateProperty.all(
        colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.1),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: surface.withValues(alpha: isDark ? 0.72 : 0.9),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelSmall?.copyWith(
          color: selected ? navSelectedColor : navUnselectedColor,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: navSelectedColor);
        }
        return IconThemeData(color: navUnselectedColor);
      }),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      indicatorColor:
          colorScheme.primary.withValues(alpha: isDark ? 0.26 : 0.16),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: colorScheme.primary.withValues(alpha: 0.16),
      selectedIconTheme: IconThemeData(color: colorScheme.primary),
      unselectedIconTheme: IconThemeData(color: textSecondary),
      selectedLabelTextStyle:
          textTheme.labelSmall?.copyWith(color: colorScheme.primary),
      unselectedLabelTextStyle:
          textTheme.labelSmall?.copyWith(color: textSecondary),
      useIndicator: true,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.textInverse,
      elevation: 0,
      shape: StadiumBorder(),
    ),
    listTileTheme: ListTileThemeData(
      shape: shape,
      iconColor: textSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      textColor: textPrimary,
    ),
    splashColor: colorScheme.primary.withValues(alpha: 0.08),
    highlightColor: colorScheme.primary.withValues(alpha: 0.05),
    hoverColor: colorScheme.primary.withValues(alpha: 0.06),
    shadowColor: AppShadows.surface.first.color,
  );
}
