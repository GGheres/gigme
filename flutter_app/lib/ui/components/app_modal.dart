import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';

/// T handles internal t behavior.

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: AppColors.textPrimary.withValues(alpha: 0.55),
    builder: builder,
  );
}

/// T handles internal t behavior.

Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useSafeArea = true,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: useSafeArea,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    backgroundColor: AppColors.surfaceStrong,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
    ),
    builder: builder,
  );
}

/// AppModal represents app modal.

class AppModal extends StatelessWidget {
  /// AppModal handles app modal.
  const AppModal({
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const <Widget>[],
    this.onClose,
    this.constraints,
    this.scrollBody = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final BoxConstraints? constraints;
  final bool scrollBody;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final dialogContent = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: scrollBody
          ? Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ModalHeader(
                  title: title,
                  subtitle: subtitle,
                  onClose: onClose,
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: SingleChildScrollView(child: body),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: actions,
                  ),
                ],
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ModalHeader(
                  title: title,
                  subtitle: subtitle,
                  onClose: onClose,
                ),
                const SizedBox(height: AppSpacing.md),
                body,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: actions,
                  ),
                ],
              ],
            ),
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xxl),
      ),
      child: constraints == null
          ? dialogContent
          : ConstrainedBox(
              constraints: constraints!,
              child: dialogContent,
            ),
    );
  }
}

/// _ModalHeader represents modal header.

class _ModalHeader extends StatelessWidget {
  /// _ModalHeader handles modal header.
  const _ModalHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if ((subtitle ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        if (onClose != null)
          AppButton(
            label: 'Закрыть',
            size: AppButtonSize.sm,
            variant: AppButtonVariant.ghost,
            icon: const Icon(Icons.close_rounded),
            onPressed: onClose,
          ),
      ],
    );
  }
}
