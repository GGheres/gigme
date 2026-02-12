import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ui/theme/app_theme.dart';

ThemeData buildGigMeTheme() {
  final theme = buildAppTheme();
  if (kIsWeb) {
    return theme;
  }
  return theme.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
  );
}
