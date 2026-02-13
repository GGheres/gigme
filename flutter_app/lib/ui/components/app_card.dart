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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xEEFFFFFF),
            Color(0xD8F0F6FF),
            Color(0xCBE9F0FF),
          ],
          stops: <double>[0.0, 0.58, 1.0],
        ),
        border: Border.all(color: AppColors.borderStrong),
        boxShadow: const <BoxShadow>[
          ...AppShadows.surface,
          BoxShadow(
            color: Color(0x33253F72),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      );
    case AppCardVariant.panel:
      return BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0x40FF7B1F),
            Color(0x3866D364),
            Color(0x473B7BFF),
          ],
        ),
        border:
            Border.all(color: AppColors.borderStrong.withValues(alpha: 0.7)),
        boxShadow: const <BoxShadow>[
          ...AppShadows.surface,
          BoxShadow(
            color: Color(0x2D0F2A60),
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      );
    case AppCardVariant.plain:
      return BoxDecoration(
        borderRadius: radius,
        color: AppColors.surfaceStrong.withValues(alpha: 0.94),
        border: Border.all(color: AppColors.border),
      );
  }
}
