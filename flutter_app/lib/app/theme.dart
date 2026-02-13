import 'package:flutter/material.dart';

import '../ui/theme/app_theme.dart';

ThemeData buildGigMeTheme() {
  final theme = buildAppTheme();
  return theme.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
  );
}
