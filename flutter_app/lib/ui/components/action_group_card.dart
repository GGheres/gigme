import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'section_card.dart';

/// ActionGroupCard represents action group card.

class ActionGroupCard extends StatelessWidget {
  /// ActionGroupCard handles action group card.
  const ActionGroupCard({
    required this.title,
    required this.actions,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            actions[index],
            if (index < actions.length - 1)
              const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}
