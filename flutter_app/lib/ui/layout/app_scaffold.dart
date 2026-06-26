import 'package:flutter/material.dart';

import '../components/app_section_header.dart';
import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';

/// AppScaffold represents app scaffold.

class AppScaffold extends StatelessWidget {
  /// AppScaffold handles app scaffold.
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
    this.bottomSheet,
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
  final Widget? bottomSheet;

  /// build renders the widget tree for this component.

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
      bottomSheet: bottomSheet,
      backgroundColor:
          backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      body: body,
    );
  }
}
