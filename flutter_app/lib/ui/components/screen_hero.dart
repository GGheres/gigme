import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_badge.dart';
import 'app_section_header.dart';

/// ScreenHero represents screen hero.

class ScreenHero extends StatelessWidget {
  /// ScreenHero handles screen hero.
  const ScreenHero({
    required this.title,
    this.subtitle,
    this.trailing,
    this.statusBadge,
    this.summary = const <AppBadge>[],
    this.actions = const <Widget>[],
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? statusBadge;
  final List<AppBadge> summary;
  final List<Widget> actions;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final hasSummary = summary.isNotEmpty;
    final hasActions = actions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: title,
          subtitle: subtitle,
          trailing: trailing,
          padding: EdgeInsets.zero,
        ),
        if (statusBadge != null || hasSummary || hasActions)
          const SizedBox(height: AppSpacing.sm),
        if (statusBadge != null) ...[
          statusBadge!,
          if (hasSummary || hasActions) const SizedBox(height: AppSpacing.sm),
        ],
        if (hasSummary) ...[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: summary,
          ),
          if (hasActions) const SizedBox(height: AppSpacing.sm),
        ],
        if (hasActions)
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: actions,
          ),
      ],
    );
  }
}
