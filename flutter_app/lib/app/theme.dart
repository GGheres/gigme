import 'package:flutter/material.dart';

import '../ui/theme/app_theme.dart';

/// buildGigMeLightTheme builds gig me light theme.

ThemeData buildGigMeLightTheme() {
  final theme = buildAppTheme(brightness: Brightness.light);
  return theme.copyWith(scaffoldBackgroundColor: Colors.transparent);
}

/// buildGigMeDarkTheme builds gig me dark theme.

ThemeData buildGigMeDarkTheme() {
  final theme = buildAppTheme(brightness: Brightness.dark);
  return theme.copyWith(scaffoldBackgroundColor: Colors.transparent);
}
