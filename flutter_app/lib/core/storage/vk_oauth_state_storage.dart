import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// VkOAuthStateStorage represents vk o auth state storage.

class VkOAuthStateStorage {
  static const _stateKey = 'gigme_vk_oauth_state';

  /// readState reads state.

  Future<String?> readState() async {
    if (!kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_stateKey);
  }

  /// writeState writes state.

  Future<void> writeState(String state) async {
    if (!kIsWeb) return;
    final trimmed = state.trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_stateKey);
      return;
    }
    await prefs.setString(_stateKey, trimmed);
  }

  /// clearState handles clear state.

  Future<void> clearState() async {
    if (!kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_stateKey);
  }
}

final vkOAuthStateStorageProvider =

    /// VkOAuthStateStorage handles vk o auth state storage.
    Provider<VkOAuthStateStorage>((ref) => VkOAuthStateStorage());
