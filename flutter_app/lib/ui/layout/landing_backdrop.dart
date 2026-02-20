import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class LandingBackdrop extends StatelessWidget {
  const LandingBackdrop({super.key});

  static const String _backgroundVideoAssetPath =
      'assets/videos/landing/IMG_9645.MP4';

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(child: _LandingBackdropVideo()),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _LandingAuroraPainter()),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _LandingNearDecorPainter()),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: _LandingEdgeVignette(),
          ),
        ),
      ],
    );
  }
}

class _LandingBackdropVideo extends StatefulWidget {
  const _LandingBackdropVideo();

  @override
  State<_LandingBackdropVideo> createState() => _LandingBackdropVideoState();
}

class _LandingBackdropVideoState extends State<_LandingBackdropVideo> {
  VideoPlayerController? _controller;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeVideo());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    final controller = VideoPlayerController.asset(
      LandingBackdrop._backgroundVideoAssetPath,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
    } catch (error) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _initError = error);
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _initError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _initError != null) {
      return const DecoratedBox(
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
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _LandingEdgeVignette extends StatelessWidget {
  const _LandingEdgeVignette();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Color(0x8A010611),
                  Color(0x41010611),
                  Color(0x00010611),
                  Color(0x41010611),
                  Color(0x8A010611),
                ],
                stops: <double>[0, 0.16, 0.5, 0.84, 1],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x5A010611),
                  Color(0x00010611),
                  Color(0x00010611),
                  Color(0x77010611),
                ],
                stops: <double>[0, 0.2, 0.74, 1],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LandingAuroraPainter extends CustomPainter {
  const _LandingAuroraPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final blend = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0x4010CFFF),
          Color(0x2614CFA2),
          Color(0x2F4277FF),
          Color(0x00000000),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, blend);

    _orb(
      canvas: canvas,
      center: Offset(size.width * 0.12, size.height * 0.18),
      radius: size.width * 0.34,
      color: const Color(0x2E20E2FF),
    );
    _orb(
      canvas: canvas,
      center: Offset(size.width * 0.9, size.height * 0.42),
      radius: size.width * 0.38,
      color: const Color(0x3027D5B8),
    );
    _orb(
      canvas: canvas,
      center: Offset(size.width * 0.08, size.height * 0.76),
      radius: size.width * 0.28,
      color: const Color(0x222A9DFF),
    );
  }

  void _orb({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required Color color,
  }) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          color,
          color.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LandingNearDecorPainter extends CustomPainter {
  const _LandingNearDecorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final wave = Path()
      ..moveTo(0, size.height * 0.7)
      ..quadraticBezierTo(
        size.width * 0.18,
        size.height * 0.63,
        size.width * 0.35,
        size.height * 0.7,
      )
      ..quadraticBezierTo(
        size.width * 0.55,
        size.height * 0.78,
        size.width * 0.8,
        size.height * 0.71,
      )
      ..quadraticBezierTo(
        size.width * 0.91,
        size.height * 0.67,
        size.width,
        size.height * 0.72,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0x002A77FF),
          Color(0x2C194A94),
          Color(0x5F12203F),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(wave, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
