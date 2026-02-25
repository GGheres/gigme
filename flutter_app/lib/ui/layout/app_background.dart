import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// AppBackground represents app background.

class AppBackground extends StatelessWidget {
  /// AppBackground handles app background.
  const AppBackground({
    required this.child,
    super.key,
  });

  final Widget child;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppColors.appBackgroundGradientWide
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFFF8FAFF),
                      Color(0xFFF2F6FF),
                      Color(0xFFF8FBFF),
                    ],
                    stops: <double>[0.0, 0.45, 1.0],
                  ),
          ),
        ),
        const Positioned(
          top: -140,
          left: -90,
          width: 330,
          height: 330,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    Color(0x554562F5),
                    Color(0x004562F5),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Positioned(
          right: -130,
          bottom: -170,
          width: 380,
          height: 380,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    Color(0x4436CFC8),
                    Color(0x0036CFC8),
                  ],
                ),
              ),
            ),
          ),
        ),
        ColoredBox(
          color: isDark
              ? Colors.black.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.02),
        ),
        child,
      ],
    );
  }
}
