import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';

/// Responsive container for filter controls + primary actions.
///
/// On narrow screens fields stack vertically; from tablet up they flow in a
/// single row. Actions always trail the fields.
class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({
    required this.fields,
    this.actions = const <Widget>[],
    this.padding,
    super.key,
  });

  final List<Widget> fields;
  final List<Widget> actions;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < AppBreakpoints.xsMax;

    final resolvedPadding = padding ??
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        );

    if (isCompact) {
      return Padding(
        padding: resolvedPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xs),
              fields[i],
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: resolvedPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            Expanded(child: fields[i]),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            ...actions,
          ],
        ],
      ),
    );
  }
}
