import 'package:flutter/material.dart';

import 'action_buttons.dart';
import 'app_card.dart';
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
    const indicator = CircularProgressIndicator(strokeWidth: 2.5);
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

    return AppCard(
      variant: AppCardVariant.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
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
    return AppCard(
      variant: AppCardVariant.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(subtitle, textAlign: TextAlign.center),
          if ((actionLabel ?? '').trim().isNotEmpty && onAction != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(
              label: actionLabel!,
              onPressed: onAction,
              outline: true,
            ),
          ],
        ],
      ),
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
    return AppCard(
      variant: AppCardVariant.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded),
          const SizedBox(height: AppSpacing.sm),
          Text('Что-то пошло не так',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: retryLabel,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
