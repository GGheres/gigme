import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_shadows.dart';

/// AppCardVariant represents app card variant.

enum AppCardVariant {
  surface,
  panel,
  plain,
}

/// AppCard represents app card.

class AppCard extends StatelessWidget {
  /// AppCard handles app card.
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.variant = AppCardVariant.surface,
    this.borderRadius,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final AppCardVariant variant;
  final double? borderRadius;
  final Clip clipBehavior;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius ?? AppRadii.xl);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final decoration = _decorationFor(
      variant,
      radius: radius,
      isDark: isDark,
    );

    Widget body = Ink(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );

    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        child: Ink(
          decoration: decoration,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
    }

    return Container(
      margin: margin,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(borderRadius: radius),
      child: body,
    );
  }
}

/// _decorationFor handles decoration for.

BoxDecoration _decorationFor(
  AppCardVariant variant, {
  required BorderRadius radius,
  required bool isDark,
}) {
  switch (variant) {
    case AppCardVariant.surface:
      return BoxDecoration(
        borderRadius: radius,
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xDD1C2D57),
                  Color(0xCC172749),
                ],
              )
            : AppColors.cardGradient,
        border: Border.all(
          color: isDark ? AppColors.darkBorderStrong : AppColors.borderStrong,
        ),
        boxShadow: AppShadows.surface,
      );
    case AppCardVariant.panel:
      return BoxDecoration(
        borderRadius: radius,
        gradient: isDark
            ? AppColors.panelGradient
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFFF0F5FF),
                  Color(0xFFEAF1FF),
                ],
              ),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorderStrong.withValues(alpha: 0.85)
              : AppColors.borderStrong,
        ),
        boxShadow: AppShadows.surface,
      );
    case AppCardVariant.plain:
      return BoxDecoration(
        borderRadius: radius,
        color: isDark
            ? AppColors.darkSurfaceStrong.withValues(alpha: 0.94)
            : AppColors.surfaceStrong.withValues(alpha: 0.95),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      );
  }
}
