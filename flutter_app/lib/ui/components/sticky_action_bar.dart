import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_card.dart';

/// StickyActionBar represents sticky action bar.

class StickyActionBar extends StatelessWidget {
  /// StickyActionBar handles sticky action bar.
  const StickyActionBar({
    required this.primaryAction,
    this.secondaryAction,
    super.key,
  });

  final Widget primaryAction;
  final Widget? secondaryAction;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: AppCard(
          variant: AppCardVariant.plain,
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useColumn = constraints.maxWidth < 420;

              if (useColumn) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    primaryAction,
                    if (secondaryAction != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      secondaryAction!,
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  if (secondaryAction != null) ...[
                    Expanded(child: secondaryAction!),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Expanded(flex: 2, child: primaryAction),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
