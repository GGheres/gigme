import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import 'action_buttons.dart';
import 'app_button.dart';
import 'app_card.dart';

/// InlineStatusBannerTone represents inline banner tone.

enum InlineStatusBannerTone {
  info,
  success,
  warning,
  danger,
}

/// InlineStatusBanner represents inline status banner.

class InlineStatusBanner extends StatelessWidget {
  /// InlineStatusBanner handles inline status banner.
  const InlineStatusBanner({
    required this.message,
    this.title,
    this.tone = InlineStatusBannerTone.info,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final String? title;
  final InlineStatusBannerTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(tone, context);
    final hasAction = (actionLabel ?? '').trim().isNotEmpty && onAction != null;

    return AppCard(
      variant: AppCardVariant.plain,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: palette.border),
            ),
            alignment: Alignment.center,
            child: Icon(
              palette.icon,
              color: palette.foreground,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((title ?? '').trim().isNotEmpty) ...[
                  Text(
                    title!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: palette.titleColor,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                ],
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.messageColor,
                      ),
                ),
                if (hasAction) ...[
                  const SizedBox(height: AppSpacing.xs),
                  SecondaryButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    outline: true,
                    size: AppButtonSize.sm,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// _InlineStatusPalette represents inline status palette.

class _InlineStatusPalette {
  /// _InlineStatusPalette handles inline status palette.
  const _InlineStatusPalette({
    required this.icon,
    required this.background,
    required this.border,
    required this.foreground,
    required this.titleColor,
    required this.messageColor,
  });

  final IconData icon;
  final Color background;
  final Color border;
  final Color foreground;
  final Color titleColor;
  final Color messageColor;
}

/// _paletteFor handles palette for.

_InlineStatusPalette _paletteFor(
  InlineStatusBannerTone tone,
  BuildContext context,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final textPrimary =
      isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  final textSecondary =
      isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

  switch (tone) {
    case InlineStatusBannerTone.info:
      return _InlineStatusPalette(
        icon: Icons.info_outline_rounded,
        background: AppColors.info.withValues(alpha: 0.14),
        border: AppColors.info.withValues(alpha: 0.34),
        foreground: AppColors.info,
        titleColor: textPrimary,
        messageColor: textSecondary,
      );
    case InlineStatusBannerTone.success:
      return _InlineStatusPalette(
        icon: Icons.check_circle_outline_rounded,
        background: AppColors.success.withValues(alpha: 0.14),
        border: AppColors.success.withValues(alpha: 0.34),
        foreground: AppColors.success,
        titleColor: textPrimary,
        messageColor: textSecondary,
      );
    case InlineStatusBannerTone.warning:
      return _InlineStatusPalette(
        icon: Icons.error_outline_rounded,
        background: AppColors.warning.withValues(alpha: 0.14),
        border: AppColors.warning.withValues(alpha: 0.34),
        foreground: AppColors.warning,
        titleColor: textPrimary,
        messageColor: textSecondary,
      );
    case InlineStatusBannerTone.danger:
      return _InlineStatusPalette(
        icon: Icons.report_gmailerrorred_rounded,
        background: AppColors.danger.withValues(alpha: 0.14),
        border: AppColors.danger.withValues(alpha: 0.34),
        foreground: AppColors.danger,
        titleColor: textPrimary,
        messageColor: textSecondary,
      );
  }
}
