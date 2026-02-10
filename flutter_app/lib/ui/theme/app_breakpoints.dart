import 'package:flutter/material.dart';

import 'app_spacing.dart';

enum AppViewportSize {
  xs,
  sm,
  md,
  lg,
}

class AppBreakpoints {
  const AppBreakpoints._();

  static const double xsMax = 600;
  static const double smMax = 1024;
  static const double mdMax = 1440;

  static AppViewportSize fromWidth(double width) {
    if (width < xsMax) return AppViewportSize.xs;
    if (width < smMax) return AppViewportSize.sm;
    if (width < mdMax) return AppViewportSize.md;
    return AppViewportSize.lg;
  }

  static double maxContentWidthFor(double width) {
    final size = fromWidth(width);
    switch (size) {
      case AppViewportSize.xs:
        return width;
      case AppViewportSize.sm:
        return 980;
      case AppViewportSize.md:
        return 1200;
      case AppViewportSize.lg:
        return 1280;
    }
  }

  static EdgeInsets pagePaddingFor(double width) {
    final size = fromWidth(width);
    switch (size) {
      case AppViewportSize.xs:
        return AppSpacing.pageMobile;
      case AppViewportSize.sm:
        return AppSpacing.pageTablet;
      case AppViewportSize.md:
      case AppViewportSize.lg:
        return AppSpacing.pageDesktop;
    }
  }
}

extension AppBreakpointContext on BuildContext {
  AppViewportSize get viewportSize =>
      AppBreakpoints.fromWidth(MediaQuery.sizeOf(this).width);

  bool get isXs => viewportSize == AppViewportSize.xs;
  bool get isSm => viewportSize == AppViewportSize.sm;
  bool get isMd => viewportSize == AppViewportSize.md;
  bool get isLg => viewportSize == AppViewportSize.lg;
  bool get isDesktop => isMd || isLg;
}
