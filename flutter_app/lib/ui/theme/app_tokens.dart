import 'package:flutter/material.dart';

/// AppDurations represents app durations.

class AppDurations {
  /// AppDurations handles app durations.
  const AppDurations._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 250);
}

/// AppMotionCurves represents app motion curves.

class AppMotionCurves {
  /// AppMotionCurves handles app motion curves.
  const AppMotionCurves._();

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;
}

/// AppTouchTargets represents app touch targets.

class AppTouchTargets {
  /// AppTouchTargets handles app touch targets.
  const AppTouchTargets._();

  static const double minSize = 44;
}
