import 'package:flutter/material.dart';

import 'space_app_background.dart';

/// AdminPanelBackground represents the reusable admin background image layer.
class AdminPanelBackground extends StatelessWidget {
  /// AdminPanelBackground handles admin background image layer.
  const AdminPanelBackground({super.key});

  /// build renders the widget tree for this component.
  @override
  Widget build(BuildContext context) {
    return const SpaceAppBackground();
  }
}
