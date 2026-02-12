import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({
    required this.child,
    super.key,
  });

  static const String mobileBackgroundAsset =
      'assets/images/backgrounds/app_cosmic_bg.png';

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        Image.asset(
          mobileBackgroundAsset,
          fit: BoxFit.cover,
        ),
        ColoredBox(
          color: Colors.black.withValues(alpha: 0.2),
        ),
        child,
      ],
    );
  }
}
