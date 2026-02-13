import 'package:flutter/material.dart';

class AppDurations {
  const AppDurations._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 250);
}

class AppMotionCurves {
  const AppMotionCurves._();

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;
}

class AppTouchTargets {
  const AppTouchTargets._();

  static const double minSize = 44;
}
