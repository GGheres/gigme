import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// Semantic tone for [InlineStatusBanner].
enum InlineStatusTone { info, success, warning, danger }

/// Compact in-flow banner used in place of full-screen error/info states.
///
/// Keeps the surrounding layout visible — avoids the "screen break" of a
/// standalone ErrorState when the rest of the page is still useful.
class InlineStatusBanner extends StatelessWidget {
  const InlineStatusBanner({
    required this.message,
    this.tone = InlineStatusTone.danger,
    this.title,
    this.onRetry,
    this.retryLabel = 'Повторить',
    this.onDismiss,
    this.icon,
    this.margin,
    super.key,
  });

  final String message;
  final InlineStatusTone tone;
  final String? title;
  final VoidCallback? onRetry;
  final String retryLabel;
  final VoidCallback? onDismiss;
  final IconData? icon;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final accent = _accent(tone);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = accent.withValues(alpha: isDark ? 0.18 : 0.10);
    final border = accent.withValues(alpha: isDark ? 0.45 : 0.30);
    final iconData = icon ?? _icon(tone);

    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
        );
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        );

    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, color: accent, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((title ?? '').trim().isNotEmpty) ...[
                  Text(title!, style: titleStyle),
                  const SizedBox(height: AppSpacing.xxs),
                ],
                Text(message, style: bodyStyle),
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(retryLabel),
                  ),
                ],
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: 'Закрыть',
              icon: Icon(Icons.close_rounded, color: accent),
            ),
        ],
      ),
    );
  }

  Color _accent(InlineStatusTone tone) {
    switch (tone) {
      case InlineStatusTone.info:
        return AppColors.info;
      case InlineStatusTone.success:
        return AppColors.success;
      case InlineStatusTone.warning:
        return AppColors.warning;
      case InlineStatusTone.danger:
        return AppColors.danger;
    }
  }

  IconData _icon(InlineStatusTone tone) {
    switch (tone) {
      case InlineStatusTone.info:
        return Icons.info_outline_rounded;
      case InlineStatusTone.success:
        return Icons.check_circle_outline_rounded;
      case InlineStatusTone.warning:
        return Icons.warning_amber_rounded;
      case InlineStatusTone.danger:
        return Icons.error_outline_rounded;
    }
  }
}
