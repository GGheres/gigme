import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appThemeModeProvider =

    /// ThemeMode handles theme mode.
    StateNotifierProvider<AppThemeModeController, ThemeMode>(
  (ref) => AppThemeModeController(),
);

/// AppThemeModeController represents app theme mode controller.

class AppThemeModeController extends StateNotifier<ThemeMode> {
  /// AppThemeModeController handles app theme mode controller.
  AppThemeModeController() : super(ThemeMode.system);

  /// cycleMode handles cycle mode.

  void cycleMode() {
    switch (state) {
      case ThemeMode.system:
        state = ThemeMode.light;
      case ThemeMode.light:
        state = ThemeMode.dark;
      case ThemeMode.dark:
        state = ThemeMode.system;
    }
  }

  /// setMode sets mode.

  void setMode(ThemeMode mode) {
    state = mode;
  }
}
