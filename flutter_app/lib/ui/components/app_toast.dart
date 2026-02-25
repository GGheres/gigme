import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// AppToastTone represents app toast tone.

enum AppToastTone {
  info,
  success,
  warning,
  error,
}

/// AppToast represents app toast.

class AppToast {
  /// AppToast handles app toast.
  const AppToast._();

  /// show handles internal show behavior.

  static void show(
    BuildContext context, {
    required String message,
    AppToastTone tone = AppToastTone.info,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _backgroundFor(tone),
      ),
    );
  }

  /// _backgroundFor handles background for.

  static Color _backgroundFor(AppToastTone tone) {
    switch (tone) {
      case AppToastTone.info:
        return AppColors.info;
      case AppToastTone.success:
        return AppColors.success;
      case AppToastTone.warning:
        return AppColors.warning;
      case AppToastTone.error:
        return AppColors.danger;
    }
  }
}
