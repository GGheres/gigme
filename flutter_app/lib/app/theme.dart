import 'package:flutter/material.dart';

import '../ui/theme/app_theme.dart';

ThemeData buildGigMeLightTheme() {
  final theme = buildAppTheme(brightness: Brightness.light);
  return theme.copyWith(scaffoldBackgroundColor: Colors.transparent);
}

ThemeData buildGigMeDarkTheme() {
  final theme = buildAppTheme(brightness: Brightness.dark);
  return theme.copyWith(scaffoldBackgroundColor: Colors.transparent);
}
