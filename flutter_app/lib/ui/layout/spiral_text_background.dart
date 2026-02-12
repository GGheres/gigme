import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum Quality {
  high,
  medium,
  low,
}

class SpiralTextBackground extends StatefulWidget {
  const SpiralTextBackground({
    super.key,
    this.text = defaultText,
    this.bandHeight = 420,
    this.baseFontSize = 32,
    this.fontWeight = FontWeight.w600,
    this.fontFamily,
    this.spiralTurns = 4.5,
    this.spiralSpacing = 22,
    this.rotationSpeed = 0.12,
    this.opacity = 0.22,
    this.color = Colors.white,
    this.parallax = true,
    this.bubbleRate = 2.0,
    this.bubbleStrength = 0.45,
    this.bubbleMinRadius = 0.04,
    this.bubbleMaxRadius = 0.16,
    this.quality = Quality.high,
  });

  static const String defaultText =
      'SPACE EVENТ 31 - 3 AUG THE BEST PARTY OF MY LIFE LOVE DANCE ART SUMMER';

  final String text;
  final double bandHeight;
  final double baseFontSize;
  final FontWeight fontWeight;
  final String? fontFamily;
  final double spiralTurns;
  final double spiralSpacing;
  final double rotationSpeed;
  final double opacity;
  final Color color;
  final bool parallax;
  final double bubbleRate;
  final double bubbleStrength;
  final double bubbleMinRadius;
  final double bubbleMaxRadius;
  final Quality quality;

  @override
  State<SpiralTextBackground> createState() => _SpiralTextBackgroundState();
}

class _SpiralTextBackgroundState extends State<SpiralTextBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _shaderAssetPath = 'assets/shaders/bubble_warp.frag';
  static const int _maxBubbleSlots = 24;
  static const int _bubbleStride = 6;
  static const int _uniformFloatCount = 9 + (_maxBubbleSlots * _bubbleStride);

  final math.Random _random = math.Random();
  final List<Bubble> _bubbles = <Bubble>[];
  final Float32List _uniforms = Float32List(_uniformFloatCount);

  late final Ticker _ticker;

  Duration? _lastTick;
  double _timeSec = 0;
  double _spawnBudget = 0;

  Offset _pointerTarget = Offset.zero;
  Offset _pointerSmoothed = Offset.zero;

  ui.Image? _spiralImage;
  _SpiralCacheSignature? _cacheSignature;
  int _cacheGeneration = 0;
  bool _cacheRenderInProgress = false;

  ui.FragmentShader? _fragmentShader;
  bool _shaderLoadAttempted = false;

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    _reduceMotion = _isReducedMotionEnabled();
    unawaited(_loadShader());
    _syncTickerState();
  }

  @override
  void didUpdateWidget(covariant SpiralTextBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    final cacheInputsChanged = oldWidget.text != widget.text ||
        oldWidget.baseFontSize != widget.baseFontSize ||
        oldWidget.fontWeight != widget.fontWeight ||
        oldWidget.fontFamily != widget.fontFamily ||
        oldWidget.spiralTurns != widget.spiralTurns ||
        oldWidget.spiralSpacing != widget.spiralSpacing ||
        oldWidget.color != widget.color ||
        oldWidget.quality != widget.quality ||
        oldWidget.bandHeight != widget.bandHeight;

    if (cacheInputsChanged) {
      _invalidateCache();
    }

    if (!widget.parallax) {
      _pointerTarget = Offset.zero;
    }

    _syncTickerState();
  }

  @override
  void didChangeAccessibilityFeatures() {
    final next = _isReducedMotionEnabled();
    if (next == _reduceMotion) return;

    _reduceMotion = next;
    if (_reduceMotion) {
      _ticker.stop();
      _lastTick = null;
      _timeSec = 0;
      _spawnBudget = 0;
      _bubbles.clear();
      _pointerTarget = Offset.zero;
      _pointerSmoothed = Offset.zero;
      setState(() {});
      return;
    }

    _syncTickerState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _fragmentShader = null;
    _spiralImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : media.size.width;
        final height = widget.bandHeight.clamp(120.0, 1200.0);
        final size = Size(width, height);

        _ensureSpiralCache(
            size: size, devicePixelRatio: media.devicePixelRatio);
        _packUniforms(size: size);

        return SizedBox(
          width: width,
          height: height,
          child: MouseRegion(
            opaque: false,
            onHover: widget.parallax && !_reduceMotion
                ? (event) =>
                    _onPointerMove(position: event.localPosition, size: size)
                : null,
            onExit: widget.parallax
                ? (_) {
                    _pointerTarget = Offset.zero;
                  }
                : null,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  isComplex: true,
                  willChange: !_reduceMotion,
                  painter: _SpiralTextBackgroundPainter(
                    image: _spiralImage,
                    shader: _fragmentShader,
                    uniforms: _uniforms,
                    useShader: _spiralImage != null &&
                        _fragmentShader != null &&
                        !_reduceMotion,
                    rotation: _timeSec * widget.rotationSpeed,
                    opacity: widget.opacity,
                    parallax: _pointerSmoothed,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isReducedMotionEnabled() {
    return WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
  }

  void _syncTickerState() {
    if (_reduceMotion) return;
    if (_ticker.isActive) return;
    _lastTick = null;
    _ticker.start();
  }

  Future<void> _loadShader() async {
    if (_shaderLoadAttempted) return;
    _shaderLoadAttempted = true;

    try {
      final program = await ui.FragmentProgram.fromAsset(_shaderAssetPath);
      if (!mounted) return;
      setState(() {
        _fragmentShader = program.fragmentShader();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fragmentShader = null;
      });
    }
  }

  void _invalidateCache() {
    _cacheSignature = null;
    _cacheGeneration += 1;
    _cacheRenderInProgress = false;
    _spiralImage?.dispose();
    _spiralImage = null;
  }

  void _ensureSpiralCache({
    required Size size,
    required double devicePixelRatio,
  }) {
    if (size.isEmpty) return;

    final qualityScale = widget.quality.resolutionScale;
    final targetDpr = (math.min(devicePixelRatio, 2.0) * qualityScale)
        .clamp(0.6, 2.0)
        .toDouble();

    final signature = _SpiralCacheSignature(
      width: size.width,
      height: size.height,
      pixelRatio: targetDpr,
      text: widget.text,
      baseFontSize: widget.baseFontSize,
      fontWeight: widget.fontWeight,
      fontFamily: widget.fontFamily,
      spiralTurns: widget.spiralTurns,
      spiralSpacing: widget.spiralSpacing,
      color: widget.color,
    );

    if (_cacheSignature == signature) {
      if (_spiralImage != null || _cacheRenderInProgress) {
        return;
      }
    }

    _cacheSignature = signature;
    _cacheRenderInProgress = true;
    final generation = ++_cacheGeneration;
    unawaited(_renderSpiralCache(signature: signature, generation: generation));
  }

  Future<void> _renderSpiralCache({
    required _SpiralCacheSignature signature,
    required int generation,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(signature.pixelRatio, signature.pixelRatio);

      final painter = SpiralPainter(
        text: signature.text,
        baseFontSize: signature.baseFontSize,
        fontWeight: signature.fontWeight,
        fontFamily: signature.fontFamily,
        spiralTurns: signature.spiralTurns,
        spiralSpacing: signature.spiralSpacing,
        color: signature.color,
      );
      painter.paint(canvas, signature.size);

      final picture = recorder.endRecording();
      final image = await picture.toImage(
        signature.widthPx,
        signature.heightPx,
      );

      if (!mounted || generation != _cacheGeneration) {
        image.dispose();
        return;
      }

      final previous = _spiralImage;
      setState(() {
        _spiralImage = image;
        _cacheRenderInProgress = false;
      });
      previous?.dispose();
    } catch (_) {
      if (mounted && generation == _cacheGeneration) {
        setState(() {
          _cacheRenderInProgress = false;
        });
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (_reduceMotion) return;

    final prev = _lastTick;
    _lastTick = elapsed;
    if (prev == null) {
      setState(() {});
      return;
    }

    final rawDt =
        (elapsed - prev).inMicroseconds / Duration.microsecondsPerSecond;
    final dt = rawDt.clamp(0.0, 0.050);
    _timeSec += dt;

    final parallaxLerp = (dt * 7.0).clamp(0.0, 1.0);
    _pointerSmoothed = Offset.lerp(
          _pointerSmoothed,
          widget.parallax ? _pointerTarget : Offset.zero,
          parallaxLerp,
        ) ??
        Offset.zero;

    _advanceBubbles(dt);
    setState(() {});
  }

  void _advanceBubbles(double dt) {
    final maxBubbles = widget.quality.maxBubbleCount;

    for (var i = _bubbles.length - 1; i >= 0; i--) {
      final bubble = _bubbles[i];
      bubble.age += dt;
      bubble.position += bubble.velocity * dt;

      final expired = bubble.age > bubble.life;
      final outOfBounds = bubble.position.dx < -0.2 ||
          bubble.position.dx > 1.2 ||
          bubble.position.dy < -0.2 ||
          bubble.position.dy > 1.2;
      if (expired || outOfBounds) {
        _bubbles.removeAt(i);
      }
    }

    _spawnBudget += widget.bubbleRate.clamp(0.0, 10.0) * dt;
    final spawnCount = _spawnBudget.floor();
    if (spawnCount > 0) {
      _spawnBudget -= spawnCount;
      for (var i = 0; i < spawnCount; i++) {
        if (_bubbles.length >= maxBubbles) {
          _bubbles.removeAt(0);
        }
        _bubbles.add(_spawnBubble());
      }
    }
  }

  Bubble _spawnBubble() {
    final centerBias =
        (_random.nextDouble() + _random.nextDouble() + _random.nextDouble()) /
            3;
    final y = (0.26 + (centerBias * 0.48)).clamp(0.04, 0.96);
    final x = _random.nextDouble();

    final minRadius = widget.bubbleMinRadius.clamp(0.01, 0.25);
    final maxRadius = widget.bubbleMaxRadius.clamp(0.02, 0.30);
    final radius = _lerp(
      math.min(minRadius, maxRadius),
      math.max(minRadius, maxRadius),
      _random.nextDouble(),
    );

    final strength = widget.bubbleStrength.clamp(0.0, 1.0) *
        _lerp(0.72, 1.18, _random.nextDouble());

    final speed = _lerp(0.008, 0.038, _random.nextDouble());
    final angle = _random.nextDouble() * math.pi * 2;
    final velocity = Offset(
      math.cos(angle) * speed,
      math.sin(angle) * speed * 0.75,
    );

    return Bubble(
      position: Offset(x, y),
      velocity: velocity,
      radius: radius,
      strength: strength,
      age: 0,
      life: _lerp(1.5, 3.5, _random.nextDouble()),
    );
  }

  void _onPointerMove({
    required Offset position,
    required Size size,
  }) {
    if (size.width <= 0 || size.height <= 0) return;

    final nx = ((position.dx / size.width) - 0.5) * 2;
    final ny = ((position.dy / size.height) - 0.5) * 2;
    _pointerTarget = Offset(
      nx.clamp(-1.0, 1.0),
      ny.clamp(-1.0, 1.0),
    );
  }

  void _packUniforms({required Size size}) {
    _uniforms[0] = size.width;
    _uniforms[1] = size.height;
    _uniforms[2] = _timeSec;
    _uniforms[3] = _timeSec * widget.rotationSpeed;
    _uniforms[4] = _pointerSmoothed.dx;
    _uniforms[5] = _pointerSmoothed.dy;
    _uniforms[6] = widget.opacity.clamp(0.0, 1.0);
    _uniforms[7] = _bubbles.length.toDouble();
    _uniforms[8] = widget.bubbleStrength.clamp(0.0, 1.0);

    var cursor = 9;
    for (var i = 0; i < _maxBubbleSlots; i++) {
      if (i < _bubbles.length) {
        final bubble = _bubbles[i];
        _uniforms[cursor++] = bubble.position.dx;
        _uniforms[cursor++] = bubble.position.dy;
        _uniforms[cursor++] = bubble.radius;
        _uniforms[cursor++] = bubble.strength;
        _uniforms[cursor++] = bubble.age;
        _uniforms[cursor++] = bubble.life;
      } else {
        _uniforms[cursor++] = 0;
        _uniforms[cursor++] = 0;
        _uniforms[cursor++] = 0;
        _uniforms[cursor++] = 0;
        _uniforms[cursor++] = 0;
        _uniforms[cursor++] = 1;
      }
    }
  }
}

class Bubble {
  Bubble({
    required this.position,
    required this.velocity,
    required this.radius,
    required this.strength,
    required this.age,
    required this.life,
  });

  Offset position;
  Offset velocity;
  double radius;
  double strength;
  double age;
  double life;
}

class _SpiralTextBackgroundPainter extends CustomPainter {
  const _SpiralTextBackgroundPainter({
    required this.image,
    required this.shader,
    required this.uniforms,
    required this.useShader,
    required this.rotation,
    required this.opacity,
    required this.parallax,
  });

  final ui.Image? image;
  final ui.FragmentShader? shader;
  final Float32List uniforms;
  final bool useShader;
  final double rotation;
  final double opacity;
  final Offset parallax;

  @override
  void paint(Canvas canvas, Size size) {
    final imageValue = image;
    if (imageValue == null || size.isEmpty) return;

    final shaderValue = shader;
    if (useShader && shaderValue != null) {
      shaderValue.setImageSampler(0, imageValue);
      for (var i = 0; i < uniforms.length; i++) {
        shaderValue.setFloat(i, uniforms[i]);
      }

      final paint = Paint()..shader = shaderValue;
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }

    final center = size.center(Offset.zero);
    final srcRect = Rect.fromLTWH(
      0,
      0,
      imageValue.width.toDouble(),
      imageValue.height.toDouble(),
    );
    const drawScale = 1.34;
    final dstRect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * drawScale,
      height: size.height * drawScale,
    );

    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Colors.white.withValues(alpha: opacity);

    canvas.save();
    canvas.translate(
      center.dx + (parallax.dx * size.width * 0.02),
      center.dy + (parallax.dy * size.height * 0.02),
    );
    canvas.rotate(rotation);
    canvas.drawImageRect(imageValue, srcRect, dstRect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpiralTextBackgroundPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.shader != shader ||
        oldDelegate.useShader != useShader ||
        oldDelegate.rotation != rotation ||
        oldDelegate.opacity != opacity ||
        oldDelegate.parallax != parallax;
  }
}

class SpiralPainter extends CustomPainter {
  const SpiralPainter({
    required this.text,
    required this.baseFontSize,
    required this.fontWeight,
    required this.fontFamily,
    required this.spiralTurns,
    required this.spiralSpacing,
    required this.color,
  });

  final String text;
  final double baseFontSize;
  final FontWeight fontWeight;
  final String? fontFamily;
  final double spiralTurns;
  final double spiralSpacing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return;

    final runs = <_SpiralTextRun>[];
    for (var i = 0; i < words.length; i++) {
      final segment = i == words.length - 1 ? '${words[i]}   ' : '${words[i]} ';
      final paragraph = _buildParagraph(segment);
      runs.add(_SpiralTextRun(
          paragraph: paragraph, width: paragraph.maxIntrinsicWidth));
    }

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius =
        math.sqrt((size.width * size.width) + (size.height * size.height)) *
            0.62;
    final turns = spiralTurns.clamp(1.0, 12.0);
    final thetaMax = turns * math.pi * 2;
    final b = spiralSpacing.clamp(8.0, 56.0);
    final r0 = (baseFontSize * 1.4).clamp(20.0, 84.0);

    for (var arm = 0; arm < 2; arm++) {
      final phase = arm * math.pi;
      var theta = 0.0;
      var runIndex = arm % runs.length;

      while (theta <= thetaMax) {
        final radius = r0 + (b * theta);
        if (radius - baseFontSize > maxRadius) {
          break;
        }

        final t = theta + phase;
        final point = Offset(
          center.dx + (radius * math.cos(t)),
          center.dy + (radius * math.sin(t)),
        );

        final dx = (b * math.cos(t)) - (radius * math.sin(t));
        final dy = (b * math.sin(t)) + (radius * math.cos(t));
        final tangentAngle = math.atan2(dy, dx);

        final run = runs[runIndex];
        canvas.save();
        canvas.translate(point.dx, point.dy);
        canvas.rotate(tangentAngle);
        canvas.drawParagraph(
          run.paragraph,
          Offset(-(run.width / 2), -baseFontSize * 0.58),
        );
        canvas.restore();

        final ds = run.width + (baseFontSize * 0.22);
        final denom =
            math.sqrt((radius * radius) + (b * b)).clamp(1.0, double.infinity);
        final dTheta = (ds / denom).clamp(0.012, 0.82);
        theta += dTheta;
        runIndex = (runIndex + 1) % runs.length;
      }
    }
  }

  ui.Paragraph _buildParagraph(String segment) {
    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: TextDirection.ltr,
        fontSize: baseFontSize,
        fontWeight: fontWeight,
        fontFamily: fontFamily,
        maxLines: 1,
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontSize: baseFontSize,
          fontWeight: fontWeight,
          fontFamily: fontFamily,
          letterSpacing: baseFontSize * 0.045,
        ),
      )
      ..addText(segment);

    final paragraph = paragraphBuilder.build();
    paragraph.layout(const ui.ParagraphConstraints(width: 10000));
    return paragraph;
  }

  @override
  bool shouldRepaint(covariant SpiralPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.baseFontSize != baseFontSize ||
        oldDelegate.fontWeight != fontWeight ||
        oldDelegate.fontFamily != fontFamily ||
        oldDelegate.spiralTurns != spiralTurns ||
        oldDelegate.spiralSpacing != spiralSpacing ||
        oldDelegate.color != color;
  }
}

class _SpiralTextRun {
  const _SpiralTextRun({
    required this.paragraph,
    required this.width,
  });

  final ui.Paragraph paragraph;
  final double width;
}

class _SpiralCacheSignature {
  const _SpiralCacheSignature({
    required this.width,
    required this.height,
    required this.pixelRatio,
    required this.text,
    required this.baseFontSize,
    required this.fontWeight,
    required this.fontFamily,
    required this.spiralTurns,
    required this.spiralSpacing,
    required this.color,
  });

  final double width;
  final double height;
  final double pixelRatio;
  final String text;
  final double baseFontSize;
  final FontWeight fontWeight;
  final String? fontFamily;
  final double spiralTurns;
  final double spiralSpacing;
  final Color color;

  Size get size => Size(width, height);

  int get widthPx => math.max(1, (width * pixelRatio).round());
  int get heightPx => math.max(1, (height * pixelRatio).round());

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _SpiralCacheSignature &&
        other.widthPx == widthPx &&
        other.heightPx == heightPx &&
        other.text == text &&
        other.baseFontSize == baseFontSize &&
        other.fontWeight == fontWeight &&
        other.fontFamily == fontFamily &&
        other.spiralTurns == spiralTurns &&
        other.spiralSpacing == spiralSpacing &&
        other.color == color;
  }

  @override
  int get hashCode {
    return Object.hash(
      widthPx,
      heightPx,
      text,
      baseFontSize,
      fontWeight,
      fontFamily,
      spiralTurns,
      spiralSpacing,
      color,
    );
  }
}

extension on Quality {
  double get resolutionScale {
    switch (this) {
      case Quality.high:
        return 1.0;
      case Quality.medium:
        return 0.84;
      case Quality.low:
        return 0.68;
    }
  }

  int get maxBubbleCount {
    switch (this) {
      case Quality.high:
        return 24;
      case Quality.medium:
        return 16;
      case Quality.low:
        return 10;
    }
  }
}

double _lerp(double a, double b, double t) {
  return a + ((b - a) * t);
}
