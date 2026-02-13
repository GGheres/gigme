import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../components/app_section_header.dart';
import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.maxContentWidth,
    this.contentPadding,
    this.showBackgroundDecor = true,
    this.scrollable = false,
    this.fullBleed = false,
    this.safeArea = true,
    this.backgroundColor,
    this.titleColor,
    this.subtitleColor,
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final double? maxContentWidth;
  final EdgeInsetsGeometry? contentPadding;
  final bool showBackgroundDecor;
  final bool scrollable;
  final bool fullBleed;
  final bool safeArea;
  final Color? backgroundColor;
  final Color? titleColor;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final resolvedPadding =
        contentPadding ?? AppBreakpoints.pagePaddingFor(width);
    final resolvedMaxWidth =
        maxContentWidth ?? AppBreakpoints.maxContentWidthFor(width);

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((title ?? '').trim().isNotEmpty)
          AppSectionHeader(
            title: title!,
            subtitle: subtitle,
            trailing: trailing,
            titleColor: titleColor,
            subtitleColor: subtitleColor,
          ),
        if ((title ?? '').trim().isNotEmpty)
          const SizedBox(height: AppSpacing.xs),
        Expanded(child: child),
      ],
    );

    if (scrollable) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((title ?? '').trim().isNotEmpty)
            AppSectionHeader(
              title: title!,
              subtitle: subtitle,
              trailing: trailing,
              titleColor: titleColor,
              subtitleColor: subtitleColor,
            ),
          if ((title ?? '').trim().isNotEmpty)
            const SizedBox(height: AppSpacing.sm),
          child,
        ],
      );
      content = SingleChildScrollView(child: content);
    }

    Widget body = content;
    if (!fullBleed) {
      body = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: resolvedMaxWidth),
          child: Padding(padding: resolvedPadding, child: body),
        ),
      );
    }

    if (safeArea) {
      body = SafeArea(child: body);
    }

    return Scaffold(
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      backgroundColor: backgroundColor ??
          (kIsWeb ? AppColors.background : Colors.transparent),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (showBackgroundDecor) const _ScaffoldBackdrop(),
          body,
        ],
      ),
    );
  }
}

class _ScaffoldBackdrop extends StatelessWidget {
  const _ScaffoldBackdrop();

  @override
  Widget build(BuildContext context) {
    const dimmerAlpha = kIsWeb ? 0.24 : 0.18;

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFF1A3560),
                Color(0xFF0A1635),
                Color(0xFF060B1A),
              ],
              stops: <double>[0.0, 0.5, 1.0],
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _BackdropConstellationPainter(),
            ),
          ),
        ),
        const Positioned(
          top: -120,
          left: -72,
          width: 280,
          height: 280,
          child: IgnorePointer(
            child: _BackdropGlow(
              colors: <Color>[
                Color(0x663B7BFF),
                Color(0x0066D364),
              ],
            ),
          ),
        ),
        const Positioned(
          bottom: -140,
          right: -120,
          width: 360,
          height: 360,
          child: IgnorePointer(
            child: _BackdropGlow(
              colors: <Color>[
                Color(0x66FF7B1F),
                Color(0x006A4CFF),
              ],
            ),
          ),
        ),
        const Positioned(
          top: 180,
          right: -70,
          width: 220,
          height: 220,
          child: IgnorePointer(
            child: _BackdropGlow(
              colors: <Color>[
                Color(0x3E66D364),
                Color(0x003B7BFF),
              ],
            ),
          ),
        ),
        ColoredBox(
          color: Colors.black.withValues(alpha: dimmerAlpha),
        ),
      ],
    );
  }
}

class _BackdropGlow extends StatelessWidget {
  const _BackdropGlow({
    required this.colors,
  });

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: colors,
          stops: const <double>[0.0, 1.0],
        ),
      ),
    );
  }
}

class _BackdropConstellationPainter extends CustomPainter {
  const _BackdropConstellationPainter();

  static const List<Offset> _starAnchors = <Offset>[
    Offset(0.11, 0.13),
    Offset(0.32, 0.08),
    Offset(0.57, 0.17),
    Offset(0.78, 0.11),
    Offset(0.22, 0.32),
    Offset(0.45, 0.29),
    Offset(0.67, 0.38),
    Offset(0.86, 0.31),
    Offset(0.13, 0.57),
    Offset(0.36, 0.62),
    Offset(0.59, 0.53),
    Offset(0.82, 0.67),
    Offset(0.27, 0.83),
    Offset(0.51, 0.88),
    Offset(0.73, 0.79),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const step = 82.0;

    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final starPaint = Paint()..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..strokeWidth = 0.9;

    Offset anchorAt(int index) {
      final source = _starAnchors[index];
      return Offset(source.dx * size.width, source.dy * size.height);
    }

    for (var i = 0; i < _starAnchors.length; i++) {
      final anchor = anchorAt(i);
      final alpha = i.isEven ? 0.42 : 0.26;
      starPaint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(anchor, i.isEven ? 1.8 : 1.2, starPaint);
    }

    for (var i = 0; i < _starAnchors.length - 1; i += 3) {
      canvas.drawLine(anchorAt(i), anchorAt(i + 1), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropConstellationPainter oldDelegate) {
    return false;
  }
}
