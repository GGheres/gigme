import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';

enum AppBadgeVariant {
  neutral,
  accent,
  ghost,
  danger,
  success,
  info,
}

class AppBadge extends StatelessWidget {
  const AppBadge({
    required this.label,
    this.variant = AppBadgeVariant.neutral,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.textStyle,
    super.key,
  });

  final String label;
  final AppBadgeVariant variant;
  final EdgeInsetsGeometry padding;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = _styleFor(variant, isDark: isDark);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: style.border),
      ),
      child: Text(
        label,
        style: (textStyle ?? Theme.of(context).textTheme.labelSmall)
            ?.copyWith(color: style.foreground),
      ),
    );
  }
}

class _BadgeStyle {
  const _BadgeStyle({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}

_BadgeStyle _styleFor(AppBadgeVariant variant, {required bool isDark}) {
  final textPrimary =
      isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  final textSecondary =
      isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

  switch (variant) {
    case AppBadgeVariant.neutral:
      return _BadgeStyle(
        background: isDark
            ? AppColors.darkSurfaceMuted.withValues(alpha: 0.92)
            : AppColors.surfaceStrong.withValues(alpha: 0.88),
        border: isDark ? AppColors.darkBorder : AppColors.border,
        foreground: textPrimary,
      );
    case AppBadgeVariant.accent:
      return _BadgeStyle(
        background: AppColors.secondary.withValues(alpha: 0.18),
        border: AppColors.secondary.withValues(alpha: 0.4),
        foreground: textPrimary,
      );
    case AppBadgeVariant.ghost:
      return _BadgeStyle(
        background: textPrimary.withValues(alpha: isDark ? 0.14 : 0.05),
        border: textPrimary.withValues(alpha: isDark ? 0.24 : 0.10),
        foreground: textPrimary,
      );
    case AppBadgeVariant.danger:
      return _BadgeStyle(
        background: AppColors.danger.withValues(alpha: 0.16),
        border: AppColors.danger.withValues(alpha: 0.45),
        foreground:
            isDark ? AppColors.darkTextPrimary : const Color(0xFF8F1F1F),
      );
    case AppBadgeVariant.success:
      return _BadgeStyle(
        background: AppColors.success.withValues(alpha: 0.20),
        border: AppColors.success.withValues(alpha: 0.45),
        foreground: textPrimary,
      );
    case AppBadgeVariant.info:
      return _BadgeStyle(
        background: AppColors.info.withValues(alpha: 0.16),
        border: AppColors.info.withValues(alpha: 0.4),
        foreground: textSecondary,
      );
  }
}
