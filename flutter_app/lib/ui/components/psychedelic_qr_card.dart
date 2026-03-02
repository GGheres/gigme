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
                    child: QrImageView(
                      data: data,
                      size: size,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
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
