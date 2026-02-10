import 'package:flutter/material.dart';

class AppDivider extends StatelessWidget {
  const AppDivider({
    this.space = 12,
    this.indent = 0,
    this.endIndent = 0,
    super.key,
  });

  final double space;
  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: space),
      child: Divider(indent: indent, endIndent: endIndent),
    );
  }
}
