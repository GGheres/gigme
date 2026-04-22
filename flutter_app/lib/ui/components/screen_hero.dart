import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// Compact chip-like metric for [ScreenHero].
class ScreenHeroMetric {
  const ScreenHeroMetric({
    required this.label,
    required this.value,
    this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? accent;
}

/// Page-leading header with title, optional subtitle, inline metrics and
/// trailing actions. Replaces ad-hoc "title + Row of buttons" blocks at the
/// top of admin screens.
class ScreenHero extends StatelessWidget {
  const ScreenHero({
    required this.title,
    this.subtitle,
    this.metrics = const <ScreenHeroMetric>[],
    this.trailing = const <Widget>[],
    this.leadingIcon,
    this.padding,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<ScreenHeroMetric> metrics;
  final List<Widget> trailing;
  final IconData? leadingIcon;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSubtitle = (subtitle ?? '').trim().isNotEmpty;

    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon,
                    size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasSubtitle) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: trailing,
                ),
              ],
            ],
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final metric in metrics) _MetricChip(metric: metric),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.metric});

  final ScreenHeroMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = metric.accent ?? theme.colorScheme.primary;
    final bg = accent.withValues(alpha: isDark ? 0.18 : 0.10);
    final border = accent.withValues(alpha: isDark ? 0.40 : 0.25);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (metric.icon != null) ...[
            Icon(metric.icon, size: 14, color: accent),
            const SizedBox(width: AppSpacing.xxs + 2),
          ],
          Text(
            metric.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            metric.value,
            style: theme.textTheme.labelMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience factory for default "primary" accent.
ScreenHeroMetric heroMetric(String label, String value,
        {IconData? icon, Color? accent}) =>
    ScreenHeroMetric(
      label: label,
      value: value,
      icon: icon,
      accent: accent ?? AppColors.primary,
    );
