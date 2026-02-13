import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFF152D55),
                Color(0xFF0A1635),
                Color(0xFF060B1A),
              ],
              stops: <double>[0.0, 0.56, 1.0],
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
                    Color(0x663B7BFF),
                    Color(0x006A4CFF),
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
                    Color(0x55FF7B1F),
                    Color(0x0066D364),
                  ],
                ),
              ),
            ),
          ),
        ),
        ColoredBox(
          color: Colors.black.withValues(alpha: 0.26),
        ),
        child,
      ],
    );
  }
}
