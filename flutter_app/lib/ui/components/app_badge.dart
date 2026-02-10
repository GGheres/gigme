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
    final style = _styleFor(variant);
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

_BadgeStyle _styleFor(AppBadgeVariant variant) {
  switch (variant) {
    case AppBadgeVariant.neutral:
      return _BadgeStyle(
        background: AppColors.surfaceStrong.withValues(alpha: 0.88),
        border: AppColors.border,
        foreground: AppColors.textPrimary,
      );
    case AppBadgeVariant.accent:
      return _BadgeStyle(
        background: AppColors.secondary.withValues(alpha: 0.18),
        border: AppColors.secondary.withValues(alpha: 0.4),
        foreground: AppColors.textPrimary,
      );
    case AppBadgeVariant.ghost:
      return _BadgeStyle(
        background: AppColors.textPrimary.withValues(alpha: 0.05),
        border: AppColors.textPrimary.withValues(alpha: 0.10),
        foreground: AppColors.textPrimary,
      );
    case AppBadgeVariant.danger:
      return _BadgeStyle(
        background: AppColors.danger.withValues(alpha: 0.16),
        border: AppColors.danger.withValues(alpha: 0.45),
        foreground: const Color(0xFF8F1F1F),
      );
    case AppBadgeVariant.success:
      return _BadgeStyle(
        background: AppColors.success.withValues(alpha: 0.20),
        border: AppColors.success.withValues(alpha: 0.45),
        foreground: AppColors.textPrimary,
      );
    case AppBadgeVariant.info:
      return _BadgeStyle(
        background: AppColors.info.withValues(alpha: 0.16),
        border: AppColors.info.withValues(alpha: 0.4),
        foreground: AppColors.textPrimary,
      );
  }
}
