import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// Status chip descriptor used inside [AdminListItem].
class AdminListItemStatus {
  const AdminListItemStatus({
    required this.label,
    required this.foreground,
    required this.tint,
  });

  final String label;
  final Color foreground;
  final Color tint;
}

/// Unified admin list row: tappable card with title, multi-line subtitle,
/// optional trailing primary value (price etc.), status chip and icon actions.
class AdminListItem extends StatelessWidget {
  const AdminListItem({
    required this.title,
    this.subtitleLines = const <String>[],
    this.status,
    this.trailingValue,
    this.actions = const <Widget>[],
    this.onTap,
    this.leading,
    this.margin,
    super.key,
  });

  final String title;
  final List<String> subtitleLines;
  final AdminListItemStatus? status;
  final String? trailingValue;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final Widget? leading;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    final borderColor =
        isDark ? AppColors.darkBorder : AppColors.border;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitleLines.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitleLines.join('\n'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.xs),
            Row(mainAxisSize: MainAxisSize.min, children: actions),
          ],
          if (status != null || (trailingValue ?? '').isNotEmpty) ...[
            const SizedBox(width: AppSpacing.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status != null) _StatusChip(status: status!),
                if ((trailingValue ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    trailingValue!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: content),
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AdminListItemStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs + 2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: status.tint,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: status.foreground.withValues(alpha: 0.45)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.foreground,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
