// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

const _vkOAuthWindowNamePrefix = 'gigme_vk_oauth_state:';

/// readVkOAuthWindowNameState reads vk oauth state from window.name on web.
String? readVkOAuthWindowNameState() {
  try {
    final raw = (html.window.name ?? '').trim();
    if (raw.isEmpty || !raw.startsWith(_vkOAuthWindowNamePrefix)) {
      return null;
    }
    final value = raw.substring(_vkOAuthWindowNamePrefix.length).trim();
    if (value.isEmpty) return null;
    return value;
  } catch (_) {
    return null;
  }
}

/// writeVkOAuthWindowNameState writes vk oauth state into window.name on web.
void writeVkOAuthWindowNameState(String state) {
  try {
    final trimmed = state.trim();
    if (trimmed.isEmpty) {
      clearVkOAuthWindowNameState();
      return;
    }
    html.window.name = '$_vkOAuthWindowNamePrefix$trimmed';
  } catch (_) {
    // Ignore browser restrictions and keep SharedPreferences fallback.
  }
}

/// clearVkOAuthWindowNameState clears vk oauth state from window.name on web.
void clearVkOAuthWindowNameState() {
  try {
    final raw = (html.window.name ?? '').trim();
    if (raw.startsWith(_vkOAuthWindowNamePrefix)) {
      html.window.name = '';
    }
  } catch (_) {
    // Ignore browser restrictions and keep SharedPreferences fallback.
  }
}
