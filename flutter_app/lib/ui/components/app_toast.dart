import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum AppToastTone {
  info,
  success,
  warning,
  error,
}

class AppToast {
  const AppToast._();

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
