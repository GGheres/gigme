import 'package:flutter/material.dart';

import '../ui/theme/app_theme.dart';

/// buildGigMeLightTheme builds gig me light theme.

ThemeData buildGigMeLightTheme() {
  return buildAppTheme(brightness: Brightness.light);
}

/// buildGigMeDarkTheme builds gig me dark theme.

ThemeData buildGigMeDarkTheme() {
  return buildAppTheme(brightness: Brightness.dark);
}
