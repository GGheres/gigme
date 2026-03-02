import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// PsychedelicQrCard represents a stylized QR container with event caption.

class PsychedelicQrCard extends StatelessWidget {
  /// PsychedelicQrCard handles stylized qr container.
  const PsychedelicQrCard({
    required this.data,
    this.caption = 'Space 31-3 aug  2026',
    this.size = 220,
    super.key,
  });

  final String data;
  final String caption;
  final double size;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cardRadius = BorderRadius.circular(20);

    return Container(
      constraints: BoxConstraints(minWidth: size + (AppSpacing.md * 2)),
      decoration: BoxDecoration(
        borderRadius: cardRadius,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 28,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: cardRadius,
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(
                painter: _PsychedelicBackdropPainter(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: CustomPaint(
                        painter: _PsychedelicQrPainter(data: data),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// _PsychedelicBackdropPainter paints a neon abstract pattern behind QR.

class _PsychedelicBackdropPainter extends CustomPainter {
  /// _PsychedelicBackdropPainter handles neon abstract pattern.
  const _PsychedelicBackdropPainter();

  /// paint draws custom background for QR container.

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFF0A1331),
          Color(0xFF33104B),
          Color(0xFF075A72),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    _drawBlob(
      canvas,
      center: Offset(size.width * 0.18, size.height * 0.22),
      radius: size.width * 0.55,
      colors: const <Color>[
        Color(0x88986DFF),
        Color(0x008E6EFF),
      ],
    );
    _drawBlob(
      canvas,
      center: Offset(size.width * 0.84, size.height * 0.24),
      radius: size.width * 0.48,
      colors: const <Color>[
        Color(0x88FF5A9D),
        Color(0x00FF5A9D),
      ],
    );
    _drawBlob(
      canvas,
      center: Offset(size.width * 0.62, size.height * 0.85),
      radius: size.width * 0.68,
      colors: const <Color>[
        Color(0x8860F4D5),
        Color(0x0060F4D5),
      ],
    );

    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen;
    const lineCount = 14;

    for (var line = 0; line < lineCount; line++) {
      final progress = line / (lineCount - 1);
      final baseY = size.height * progress;
      final hue = ((progress * 280) + 35) % 360;
      final amplitude = 7.0 + ((line % 5) * 2.6);
      final frequency = 2.5 + ((line % 3) * 0.5);

      wavePaint
        ..strokeWidth = 1.4 + ((line % 3) * 0.5)
        ..color = HSVColor.fromAHSV(0.34, hue, 0.78, 1).toColor();

      final path = Path()..moveTo(0, baseY);
      for (var x = 0.0; x <= size.width; x += 10) {
        final phase = (x / size.width) * (math.pi * frequency);
        final wave = math.sin(phase + (progress * math.pi * 4.4));
        final y = baseY + (wave * amplitude);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, wavePaint);
    }
  }

  /// _drawBlob paints a smooth radial glow.

  void _drawBlob(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required List<Color> colors,
  }) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: colors,
        stops: const <double>[0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  /// shouldRepaint indicates whether the painter needs a repaint.

  @override
  bool shouldRepaint(covariant _PsychedelicBackdropPainter oldDelegate) {
    return false;
  }
}

/// _PsychedelicQrPainter paints QR modules with a psychedelic color pattern.

class _PsychedelicQrPainter extends CustomPainter {
  /// _PsychedelicQrPainter handles psychedelic qr rendering.
  _PsychedelicQrPainter({required this.data})
      : _result = QrValidator.validate(
          data: data,
          version: QrVersions.auto,
          errorCorrectionLevel: QrErrorCorrectLevel.H,
        );

  static const int _finderPatternLimit = 7;
  final String data;
  final QrValidationResult _result;

  /// paint draws the QR code with psychedelic modules.

  @override
  void paint(Canvas canvas, Size size) {
    final qrCode = _result.qrCode;
    if (!_result.isValid || qrCode == null || size.shortestSide <= 0) {
      return;
    }

    final image = QrImage(qrCode);
    final moduleCount = image.moduleCount;
    final shortest = size.shortestSide;
    final pixelSize = shortest / moduleCount;
    final insetX = (size.width - (pixelSize * moduleCount)) / 2;
    final insetY = (size.height - (pixelSize * moduleCount)) / 2;

    final backgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final modulePaint = Paint()..style = PaintingStyle.fill;

    for (var x = 0; x < moduleCount; x++) {
      for (var y = 0; y < moduleCount; y++) {
        if (!image.isDark(y, x)) {
          continue;
        }

        modulePaint.color = _moduleColor(
          x: x,
          y: y,
          moduleCount: moduleCount,
          isFinder: _isFinderPatternPosition(
            x: x,
            y: y,
            moduleCount: moduleCount,
          ),
        );

        final left = insetX + (x * pixelSize);
        final top = insetY + (y * pixelSize);
        canvas.drawRect(
          Rect.fromLTWH(left, top, pixelSize, pixelSize),
          modulePaint,
        );
      }
    }
  }

  /// _moduleColor returns a per-module psychedelic color.

  Color _moduleColor({
    required int x,
    required int y,
    required int moduleCount,
    required bool isFinder,
  }) {
    if (isFinder) {
      return const Color(0xFF080808);
    }

    final nx = x / moduleCount;
    final ny = y / moduleCount;
    final radial =
        math.sqrt(((nx - 0.5) * (nx - 0.5)) + ((ny - 0.5) * (ny - 0.5)));
    final wave = ((math.sin((nx * 12.8) + (ny * 7.1)) +
                math.cos((ny * 13.6) - (nx * 5.4))) *
            0.5) +
        0.5;
    final hue = (((nx * 230) + (ny * 140) + (wave * 70)) % 360).toDouble();
    final saturation = (0.86 - (radial * 0.22)).clamp(0.62, 0.9);
    final value = (0.3 + (wave * 0.24) - (radial * 0.05)).clamp(0.22, 0.48);
    return HSVColor.fromAHSV(1, hue, saturation, value).toColor();
  }

  /// _isFinderPatternPosition checks whether module belongs to finder patterns.

  bool _isFinderPatternPosition({
    required int x,
    required int y,
    required int moduleCount,
  }) {
    final inTopLeft = y < _finderPatternLimit && x < _finderPatternLimit;
    final inTopRight =
        y < _finderPatternLimit && x >= moduleCount - _finderPatternLimit;
    final inBottomLeft =
        y >= moduleCount - _finderPatternLimit && x < _finderPatternLimit;
    return inTopLeft || inTopRight || inBottomLeft;
  }

  /// shouldRepaint indicates whether the painter needs a repaint.

  @override
  bool shouldRepaint(covariant _PsychedelicQrPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
