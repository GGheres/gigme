import 'package:flutter/material.dart';

/// AppDivider represents app divider.

class AppDivider extends StatelessWidget {
  /// AppDivider handles app divider.
  const AppDivider({
    this.space = 12,
    this.indent = 0,
    this.endIndent = 0,
    super.key,
  });

  final double space;
  final double indent;
  final double endIndent;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: space),
      child: Divider(indent: indent, endIndent: endIndent),
    );
  }
}
