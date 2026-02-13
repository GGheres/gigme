import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appThemeModeProvider =
    StateNotifierProvider<AppThemeModeController, ThemeMode>(
  (ref) => AppThemeModeController(),
);

class AppThemeModeController extends StateNotifier<ThemeMode> {
  AppThemeModeController() : super(ThemeMode.system);

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

  void setMode(ThemeMode mode) {
    state = mode;
  }
}
