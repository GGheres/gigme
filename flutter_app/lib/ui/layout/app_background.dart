import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0xFF060B1D),
                Color(0xFF040814),
                Color(0xFF050A16),
              ],
              stops: <double>[0, 0.45, 1],
            ),
          ),
        ),
        ColoredBox(
          color: Colors.black.withValues(alpha: 0.2),
        ),
        child,
      ],
    );
  }
}
