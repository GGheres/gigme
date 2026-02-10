import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class PremiumLoadingView extends StatefulWidget {
  const PremiumLoadingView({
    super.key,
    this.text = 'SPACE • LOADING • ',
    this.subtitle,
    this.compact = false,
  });

  final String text;
  final String? subtitle;
  final bool compact;

  @override
  State<PremiumLoadingView> createState() => _PremiumLoadingViewState();
}

class _PremiumLoadingViewState extends State<PremiumLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _timeline;

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (_PremiumLoadingTuning.effectsTimelineSec * 1000).round(),
      ),
    )..repeat();
  }

  @override
  void dispose() {
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final shortest = math.min(
      media?.size.width ?? 320,
      media?.size.height ?? 320,
    );
    final orbitSize = (shortest *
            (widget.compact
                ? _PremiumLoadingTuning.compactOrbitScale
                : _PremiumLoadingTuning.orbitScale))
        .clamp(
      widget.compact
          ? _PremiumLoadingTuning.compactOrbitMin
          : _PremiumLoadingTuning.orbitMin,
      widget.compact
          ? _PremiumLoadingTuning.compactOrbitMax
          : _PremiumLoadingTuning.orbitMax,
    );

    return SizedBox.expand(
      child: Center(
        child: SizedBox.square(
          dimension: orbitSize,
          child: _PremiumFrameEffect(
            text: widget.text,
            timeline: _timeline,
            reduceMotion: reduceMotion,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _PremiumLoadingTuning {
  const _PremiumLoadingTuning._();

  static const double effectsTimelineSec = 120;
  static const double globalBreathPeriodSec = 4.8;
  static const double tickerSpeedPxPerSec = 24;
  static const double shimmerSpeedPxPerSec = 36;
  static const double waveSpeed = 76;
  static const double waveSigma = 150;
  static const double waveGlowBoost = 0.68;
  static const double waveOpacityBoost = 0.18;
  static const double grainOpacity = 0.0;
  static const double grainFps = 6;
  static const double orbitScale = 0.44;
  static const double compactOrbitScale = 0.56;
  static const double orbitMin = 168;
  static const double compactOrbitMin = 92;
  static const double orbitMax = 320;
  static const double compactOrbitMax = 190;
}

class _PremiumFrameEffect extends StatelessWidget {
  const _PremiumFrameEffect({
    required this.text,
    required this.timeline,
    required this.reduceMotion,
    required this.child,
  });

  final String text;
  final Animation<double> timeline;
  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: child),
        const Positioned.fill(
          child: IgnorePointer(
            child: _AnimatedGrainOverlay(
              opacity: _PremiumLoadingTuning.grainOpacity,
              fps: _PremiumLoadingTuning.grainFps,
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: timeline,
              builder: (context, _) {
                final timeSec =
                    timeline.value * _PremiumLoadingTuning.effectsTimelineSec;
                return RepaintBoundary(
                  child: CustomPaint(
                    painter: _PremiumFramePainter(
                      text: text,
                      timeSec: timeSec,
                      reduceMotion: reduceMotion,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedGrainOverlay extends StatefulWidget {
  const _AnimatedGrainOverlay({
    required this.opacity,
    required this.fps,
  });

  final double opacity;
  final double fps;

  @override
  State<_AnimatedGrainOverlay> createState() => _AnimatedGrainOverlayState();
}

class _AnimatedGrainOverlayState extends State<_AnimatedGrainOverlay> {
  final List<ui.Image> _frames = <ui.Image>[];
  Timer? _timer;
  int _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareFrames());
  }

  @override
  void didUpdateWidget(covariant _AnimatedGrainOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fps != widget.fps && _frames.isNotEmpty) {
      _startTicker();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _prepareFrames() async {
    const frameCount = 8;
    const frameSize = 256;
    final generated = <ui.Image>[];

    for (var i = 0; i < frameCount; i++) {
      generated.add(
        await _generateNoiseImage(
          frameSize: frameSize,
          seed: 7919 + (i * 271),
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _frames
        ..clear()
        ..addAll(generated);
      _frameIndex = 0;
    });
    _startTicker();
  }

  Future<ui.Image> _generateNoiseImage({
    required int frameSize,
    required int seed,
  }) {
    final rnd = math.Random(seed);
    final pixelCount = frameSize * frameSize;
    final bytes = Uint8List(pixelCount * 4);

    for (var i = 0; i < pixelCount; i++) {
      final value = 106 + rnd.nextInt(128);
      final idx = i * 4;
      bytes[idx] = value;
      bytes[idx + 1] = value;
      bytes[idx + 2] = value;
      bytes[idx + 3] = 255;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      frameSize,
      frameSize,
      ui.PixelFormat.rgba8888,
      completer.complete,
      rowBytes: frameSize * 4,
    );
    return completer.future;
  }

  void _startTicker() {
    _timer?.cancel();
    final fps = widget.fps.clamp(1.0, 12.0);
    final interval = Duration(milliseconds: (1000 / fps).round());
    _timer = Timer.periodic(interval, (_) {
      if (!mounted || _frames.isEmpty) return;
      setState(() {
        _frameIndex = (_frameIndex + 1) % _frames.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_frames.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GrainOverlayPainter(
          image: _frames[_frameIndex],
          opacity: widget.opacity,
          frameIndex: _frameIndex,
        ),
      ),
    );
  }
}

class _GrainOverlayPainter extends CustomPainter {
  const _GrainOverlayPainter({
    required this.image,
    required this.opacity,
    required this.frameIndex,
  });

  final ui.Image image;
  final double opacity;
  final int frameIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    final scale = math.max(size.width / imageWidth, size.height / imageHeight);
    final drawWidth = imageWidth * scale * 1.06;
    final drawHeight = imageHeight * scale * 1.06;
    final driftX = math.sin(frameIndex * 0.9) * 6;
    final driftY = math.cos(frameIndex * 0.7) * 6;

    final dst = Rect.fromLTWH(
      ((size.width - drawWidth) / 2) + driftX,
      ((size.height - drawHeight) / 2) + driftY,
      drawWidth,
      drawHeight,
    );
    final src = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    final paint = Paint()
      ..blendMode = BlendMode.softLight
      ..filterQuality = FilterQuality.low
      ..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 0.12));
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant _GrainOverlayPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.opacity != opacity ||
        oldDelegate.frameIndex != frameIndex;
  }
}

class _PremiumFramePainter extends CustomPainter {
  const _PremiumFramePainter({
    required this.text,
    required this.timeSec,
    required this.reduceMotion,
  });

  static const int _intensitySteps = 12;
  static final Map<String, _FramePathData> _framePathCache =
      <String, _FramePathData>{};
  static final Map<String, double> _glyphWidthCache = <String, double>{};
  static final Map<String, TextPainter> _glyphPainterCache =
      <String, TextPainter>{};

  final String text;
  final double timeSec;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final frame = _resolveFramePath(size);
    final breath = _breathValue(timeSec);
    _drawTickerText(canvas: canvas, frame: frame, breath: breath);
  }

  void _drawTickerText({
    required Canvas canvas,
    required _FramePathData frame,
    required double breath,
  }) {
    final sourceText = text.trim().isEmpty ? 'SPACE • LOADING • ' : text;
    final glyphs = sourceText.split('');
    if (glyphs.isEmpty) return;

    final fontSize = (frame.radius * 0.16).clamp(10.0, 15.0);
    final spacing = (fontSize * 0.34).clamp(3.0, 6.0);

    var patternLength = 0.0;
    for (final glyph in glyphs) {
      patternLength += _glyphWidth(glyph: glyph, fontSize: fontSize) + spacing;
    }
    if (patternLength <= 0) return;

    final textSpeed =
        reduceMotion ? 0.0 : _PremiumLoadingTuning.tickerSpeedPxPerSec;
    var cursor =
        textSpeed == 0 ? 0.0 : -((timeSec * textSpeed) % patternLength);
    if (cursor > 0) cursor -= patternLength;

    final waveCenter = reduceMotion
        ? 0.0
        : ((timeSec * _PremiumLoadingTuning.waveSpeed) % frame.length);
    final shimmerCenter = reduceMotion
        ? 0.0
        : ((timeSec * _PremiumLoadingTuning.shimmerSpeedPxPerSec) %
            frame.length);
    final waveSigma = _PremiumLoadingTuning.waveSigma.clamp(50.0, 260.0);
    final shimmerSigma = waveSigma * 0.72;

    final maxCursor = frame.length + patternLength;
    while (cursor < maxCursor) {
      for (final glyph in glyphs) {
        final glyphWidth = _glyphWidth(glyph: glyph, fontSize: fontSize);
        final glyphCenter = cursor + (glyphWidth * 0.5);
        cursor += glyphWidth + spacing;
        if (glyphCenter < 0 || glyphCenter > frame.length) {
          continue;
        }

        final tangent = frame.metric.getTangentForOffset(glyphCenter);
        if (tangent == null) continue;

        final wave = reduceMotion
            ? 0.0
            : _gaussianOnLoop(
                s: glyphCenter,
                center: waveCenter,
                length: frame.length,
                sigma: waveSigma,
              );
        final shimmer = reduceMotion
            ? 0.0
            : _gaussianOnLoop(
                s: glyphCenter,
                center: shimmerCenter,
                length: frame.length,
                sigma: shimmerSigma,
              );

        final localGlow = (0.14 +
                (0.24 * breath) +
                (wave * _PremiumLoadingTuning.waveGlowBoost) +
                (shimmer * 0.30))
            .clamp(0.0, 1.0);
        final localOpacity = (0.22 +
                (0.24 * breath) +
                (wave * _PremiumLoadingTuning.waveOpacityBoost) +
                (shimmer * 0.16))
            .clamp(0.0, 1.0);

        final glowPainter = _glyphPainter(
          glyph: glyph,
          fontSize: fontSize,
          intensityBin: (localGlow * _intensitySteps).round(),
          glowPass: true,
        );
        final textPainter = _glyphPainter(
          glyph: glyph,
          fontSize: fontSize,
          intensityBin: (localOpacity * _intensitySteps).round(),
          glowPass: false,
        );

        final yOffset = -fontSize * 0.66;
        canvas.save();
        canvas.translate(tangent.position.dx, tangent.position.dy);
        canvas.rotate(tangent.angle);
        glowPainter.paint(canvas, Offset(-(glowPainter.width / 2), yOffset));
        textPainter.paint(canvas, Offset(-(textPainter.width / 2), yOffset));
        canvas.restore();
      }
    }
  }

  _FramePathData _resolveFramePath(Size size) {
    final radius = ((size.shortestSide * 0.5) - 6).clamp(18.0, 180.0);
    final key = [
      size.width.toStringAsFixed(1),
      size.height.toStringAsFixed(1),
      radius.toStringAsFixed(1),
    ].join(':');

    final cached = _framePathCache[key];
    if (cached != null) return cached;

    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final path = Path()..addOval(rect);
    final metric = path.computeMetrics(forceClosed: true).first;
    final out = _FramePathData(
      rect: rect,
      center: center,
      radius: radius,
      path: path,
      metric: metric,
      length: metric.length,
    );
    _framePathCache[key] = out;
    if (_framePathCache.length > 20) {
      _framePathCache.remove(_framePathCache.keys.first);
    }
    return out;
  }

  TextPainter _glyphPainter({
    required String glyph,
    required double fontSize,
    required int intensityBin,
    required bool glowPass,
  }) {
    final clampedBin = intensityBin.clamp(0, _intensitySteps);
    final key = [
      glyph,
      fontSize.toStringAsFixed(2),
      clampedBin,
      glowPass ? 1 : 0,
    ].join('|');
    final cached = _glyphPainterCache[key];
    if (cached != null) return cached;

    final intensity = clampedBin / _intensitySteps;
    final base = glowPass ? const Color(0xFFBFC8D6) : const Color(0xFFCDD5E2);
    final highlight =
        glowPass ? const Color(0xFFFFFFFF) : const Color(0xFFF5F8FF);
    final alpha = glowPass
        ? (0.08 + (0.70 * intensity)).clamp(0.0, 1.0)
        : (0.26 + (0.68 * intensity)).clamp(0.0, 1.0);
    final color = Color.lerp(base, highlight, intensity)!
        .withValues(alpha: alpha.toDouble());

    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontWeight: glowPass ? FontWeight.w600 : FontWeight.w500,
          fontSize: fontSize,
          height: 1.0,
          shadows: glowPass
              ? [
                  Shadow(
                    color: color.withValues(
                      alpha: (0.16 + (0.42 * intensity)).clamp(0.0, 1.0),
                    ),
                    blurRadius: 6 + (8 * intensity),
                  ),
                ]
              : const <Shadow>[],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: fontSize * 1.8);

    _glyphPainterCache[key] = painter;
    if (_glyphPainterCache.length > 1400) {
      _glyphPainterCache.remove(_glyphPainterCache.keys.first);
    }
    return painter;
  }

  double _glyphWidth({
    required String glyph,
    required double fontSize,
  }) {
    final key = '$glyph|${fontSize.toStringAsFixed(2)}';
    final cached = _glyphWidthCache[key];
    if (cached != null) return cached;

    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w500,
          fontSize: fontSize,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: fontSize * 1.8);
    _glyphWidthCache[key] = painter.width;
    if (_glyphWidthCache.length > 320) {
      _glyphWidthCache.remove(_glyphWidthCache.keys.first);
    }
    return painter.width;
  }

  double _breathValue(double timeSeconds) {
    final phase = (timeSeconds / _PremiumLoadingTuning.globalBreathPeriodSec) *
        math.pi *
        2;
    return 0.5 + (0.5 * math.sin(phase));
  }

  double _gaussianOnLoop({
    required double s,
    required double center,
    required double length,
    required double sigma,
  }) {
    if (sigma <= 0 || length <= 0) return 0;
    final absDistance = (s - center).abs();
    final d = math.min(absDistance, length - absDistance);
    final denom = 2 * sigma * sigma;
    return math.exp(-(d * d) / denom);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! _PremiumFramePainter ||
        oldDelegate.text != text ||
        oldDelegate.reduceMotion != reduceMotion ||
        (oldDelegate.timeSec - timeSec).abs() > 0.0001;
  }
}

class _FramePathData {
  const _FramePathData({
    required this.rect,
    required this.center,
    required this.radius,
    required this.path,
    required this.metric,
    required this.length,
  });

  final Rect rect;
  final Offset center;
  final double radius;
  final Path path;
  final ui.PathMetric metric;
  final double length;
}
