import 'package:flutter/material.dart';

import 'action_buttons.dart';
import 'app_card.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// LoadingState represents loading state.

class LoadingState extends StatelessWidget {
  /// LoadingState handles loading state.
  const LoadingState({
    this.title = 'Загрузка',
    this.subtitle = 'Подождите пару секунд',
    this.compact = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool compact;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indicator = SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(
        strokeWidth: 2.4,
        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
      ),
    );
    if (compact) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          indicator,
          const SizedBox(width: AppSpacing.sm),
          Text(subtitle),
        ],
      );
    }

    return _StateShell(
      icon: _StateIconBubble(
        icon: indicator,
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.14),
      ),
      title: title,
      subtitle: subtitle,
    );
  }
}

/// EmptyState represents empty state.

class EmptyState extends StatelessWidget {
  /// EmptyState handles empty state.
  const EmptyState({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.inbox_rounded,
    super.key,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAction = (actionLabel ?? '').trim().isNotEmpty && onAction != null;
    return _StateShell(
      icon: _StateIconBubble(
        icon: Icon(
          icon,
          size: 24,
          color: theme.colorScheme.onSurface,
        ),
        backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.18),
      ),
      title: title,
      subtitle: subtitle,
      action: hasAction
          ? SecondaryButton(
              label: actionLabel!,
              onPressed: onAction,
              outline: true,
            )
          : null,
    );
  }
}

/// ErrorState represents error state.

class ErrorState extends StatelessWidget {
  /// ErrorState handles error state.
  const ErrorState({
    required this.message,
    this.onRetry,
    this.retryLabel = 'Повторить',
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _StateShell(
      icon: _StateIconBubble(
        icon: Icon(
          Icons.error_outline_rounded,
          size: 24,
          color: theme.colorScheme.error,
        ),
        backgroundColor: AppColors.danger.withValues(alpha: 0.12),
      ),
      title: 'Что-то пошло не так',
      subtitle: message,
      action: onRetry == null
          ? null
          : PrimaryButton(
              label: retryLabel,
              onPressed: onRetry,
            ),
    );
  }
}

/// _StateShell represents state shell.

class _StateShell extends StatelessWidget {
  /// _StateShell handles state shell.
  const _StateShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final Widget? action;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(subtitle, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// _StateIconBubble represents state icon bubble.

class _StateIconBubble extends StatelessWidget {
  /// _StateIconBubble handles state icon bubble.
  const _StateIconBubble({
    required this.icon,
    required this.backgroundColor,
  });

  final Widget icon;
  final Color backgroundColor;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }
}
