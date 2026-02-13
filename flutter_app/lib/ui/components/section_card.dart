import 'package:flutter/material.dart';

import 'app_card.dart';
import '../theme/app_spacing.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.variant = AppCardVariant.surface,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final AppCardVariant variant;

  @override
  Widget build(BuildContext context) {
    final subtitleText = (subtitle ?? '').trim();
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    final subtitleStyle = Theme.of(context).textTheme.bodySmall;

    return AppCard(
      variant: variant,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: titleStyle)),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitleText.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(subtitleText, style: subtitleStyle),
          ],
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}
