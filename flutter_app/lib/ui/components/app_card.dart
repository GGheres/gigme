import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_shadows.dart';

enum AppCardVariant {
  surface,
  panel,
  plain,
}

class AppCard extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius ?? AppRadii.xl);
    final decoration = _decorationFor(variant, radius: radius);

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

BoxDecoration _decorationFor(AppCardVariant variant,
    {required BorderRadius radius}) {
  switch (variant) {
    case AppCardVariant.surface:
      return BoxDecoration(
        borderRadius: radius,
        gradient: AppColors.cardGradient,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.surface,
      );
    case AppCardVariant.panel:
      return BoxDecoration(
        borderRadius: radius,
        gradient: AppColors.panelGradient,
        border:
            Border.all(color: AppColors.borderStrong.withValues(alpha: 0.7)),
        boxShadow: AppShadows.surface,
      );
    case AppCardVariant.plain:
      return BoxDecoration(
        borderRadius: radius,
        color: AppColors.surfaceStrong,
        border: Border.all(color: AppColors.border),
      );
  }
}
