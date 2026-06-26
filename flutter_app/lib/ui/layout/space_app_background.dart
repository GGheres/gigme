import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// SpaceAppBackground represents the reusable cosmic background layer.
class SpaceAppBackground extends StatelessWidget {
  /// SpaceAppBackground handles the shared background image layer.
  const SpaceAppBackground({super.key});

  static const String _assetPath = 'assets/images/admin/panel_background.jpeg';

  /// build renders the widget tree for this component.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? AppColors.backgroundDeep : AppColors.backgroundSoft;
    final imageOpacity = isDark ? 0.26 : 0.08;
    final overlayColors = isDark
        ? <Color>[
            AppColors.backgroundDeep.withValues(alpha: 0.24),
            AppColors.backgroundDeep.withValues(alpha: 0.72),
            AppColors.backgroundDeep.withValues(alpha: 0.9),
          ]
        : <Color>[
            AppColors.backgroundSoft.withValues(alpha: 0.88),
            const Color(0xFFF7F9FE).withValues(alpha: 0.94),
            const Color(0xFFFDFEFF).withValues(alpha: 0.98),
          ];

    return DecoratedBox(
      decoration: BoxDecoration(color: baseColor),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: imageOpacity,
            child: Image.asset(
              _assetPath,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          if (!isDark)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.35),
                    radius: 1.05,
                    colors: <Color>[
                      AppColors.primary.withValues(alpha: 0.06),
                      AppColors.secondary.withValues(alpha: 0.03),
                      Colors.transparent,
                    ],
                    stops: const <double>[0, 0.45, 1],
                  ),
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: overlayColors,
                stops: const <double>[0, 0.45, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
