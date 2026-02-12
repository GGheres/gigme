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
          if (showBackgroundDecor && kIsWeb) const _ScaffoldBackdrop(),
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
    final isTall = MediaQuery.sizeOf(context).width < AppBreakpoints.smMax;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        gradient: isTall
            ? AppColors.appBackgroundGradientTall
            : AppColors.appBackgroundGradientWide,
      ),
      child: const Stack(
        fit: StackFit.expand,
        children: [
          _GlowCircle(
            alignment: Alignment(-0.84, -0.76),
            radius: 340,
            color: Color(0x664B96FF),
          ),
          _GlowCircle(
            alignment: Alignment(0.15, -0.65),
            radius: 320,
            color: Color(0x5578E1D1),
          ),
          _GlowCircle(
            alignment: Alignment(0.86, -0.25),
            radius: 300,
            color: Color(0x55FFC86E),
          ),
          _GlowCircle(
            alignment: Alignment(0.58, 0.84),
            radius: 320,
            color: Color(0x55785AD2),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({
    required this.alignment,
    required this.radius,
    required this.color,
  });

  final Alignment alignment;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: radius,
          height: radius,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
      ),
    );
  }
}
