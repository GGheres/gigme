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

    final shouldRenderBackdrop = showBackgroundDecor && !kIsWeb;

    return Scaffold(
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      backgroundColor: backgroundColor ?? Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (shouldRenderBackdrop) const _ScaffoldBackdrop(),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppColors.appBackgroundGradientWide
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFFF8FAFF),
                      Color(0xFFF3F7FF),
                      Color(0xFFF9FBFF),
                    ],
                  ),
          ),
        ),
        Positioned(
          top: -120,
          left: -80,
          width: 300,
          height: 300,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    (isDark ? AppColors.primary : AppColors.secondary)
                        .withValues(alpha: 0.24),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -160,
          right: -130,
          width: 360,
          height: 360,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    (isDark ? AppColors.secondary : AppColors.primary)
                        .withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isDark)
          Positioned(
            top: 84,
            right: -36,
            width: 180,
            height: 180,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      AppColors.accentPurple.withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ColoredBox(
          color: isDark
              ? Colors.black.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.02),
        ),
      ],
    );
  }
}
