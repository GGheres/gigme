import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// EventAccessKeyStore represents event access key store.

class EventAccessKeyStore {
  static const _storageKey = 'gigme_event_keys';

  /// load loads data from the underlying source.

  Future<Map<int, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return <int, String>{};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <int, String>{};
      final out = <int, String>{};
      decoded.forEach((key, value) {
        final parsedKey = int.tryParse(key.toString());
        final parsedValue = value?.toString().trim() ?? '';
        if (parsedKey != null &&
            parsedKey > 0 &&
            parsedValue.isNotEmpty &&
            parsedValue.length <= 64) {
          out[parsedKey] = parsedValue;
        }
      });
      return out;
    } catch (_) {
      return <int, String>{};
    }
  }

  /// save persists data to storage.

  Future<void> save(Map<int, String> values) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = <String, String>{};
    values.forEach((key, value) {
      final trimmed = value.trim();
      if (key > 0 && trimmed.isNotEmpty && trimmed.length <= 64) {
        clean[key.toString()] = trimmed;
      }
    });
    await prefs.setString(_storageKey, jsonEncode(clean));
  }
}
