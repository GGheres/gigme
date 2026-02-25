import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../utils/json_utils.dart';

/// PersistedAuthSession represents persisted auth session.

class PersistedAuthSession {
  /// PersistedAuthSession handles persisted auth session.
  const PersistedAuthSession({
    required this.token,
    required this.user,
  });

  /// PersistedAuthSession handles persisted auth session.

  factory PersistedAuthSession.fromJson(dynamic json) {
    final map = asMap(json);
    return PersistedAuthSession(
      token: asString(map['accessToken']).trim(),
      user: User.fromJson(map['user']),
    );
  }

  final String token;
  final User user;

  /// toJson handles to json.

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'accessToken': token,
      'user': user.toJson(),
    };
  }
}

/// TokenStorage represents token storage.

class TokenStorage {
  static const _tokenKey = 'gigme_access_token';
  static const _sessionKey = 'gigme_auth_session';
  static const _telegramInitDataKey = 'gigme_telegram_init_data';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// readToken reads token.

  Future<String?> readToken() async {
    final session = await readSession();
    if (session != null && session.token.isNotEmpty) {
      return session.token;
    }

    return _readString(_tokenKey);
  }

  /// readSession reads session.

  Future<PersistedAuthSession?> readSession() async {
    final raw = await _readString(_sessionKey);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      final session = PersistedAuthSession.fromJson(decoded);
      if (session.token.isEmpty) {
        await _remove(_sessionKey);
        return null;
      }
      return session;
    } catch (_) {
      await _remove(_sessionKey);
      return null;
    }
  }

  /// writeToken writes token.

  Future<void> writeToken(String token) async {
    await _writeString(_tokenKey, token);
  }

  /// readTelegramInitData reads telegram init data.

  Future<String?> readTelegramInitData() async {
    final raw = await _readString(_telegramInitDataKey);
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    return value;
  }

  /// writeTelegramInitData writes telegram init data.

  Future<void> writeTelegramInitData(String initData) async {
    final value = initData.trim();
    if (value.isEmpty) {
      await _remove(_telegramInitDataKey);
      return;
    }
    await _writeString(_telegramInitDataKey, value);
  }

  /// clearTelegramInitData handles clear telegram init data.

  Future<void> clearTelegramInitData() async {
    await _remove(_telegramInitDataKey);
  }

  /// writeSession writes session.

  Future<void> writeSession({
    required String token,
    required User user,
  }) async {
    final session = PersistedAuthSession(token: token, user: user);
    await _writeString(_sessionKey, jsonEncode(session.toJson()));
    await _writeString(_tokenKey, token);
  }

  /// clearToken handles clear token.

  Future<void> clearToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
      await prefs.remove(_tokenKey);
      await prefs.remove(_telegramInitDataKey);
      return;
    }
    await _secureStorage.delete(key: _sessionKey);
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _telegramInitDataKey);
  }

  /// _readString reads string.

  Future<String?> _readString(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    return _secureStorage.read(key: key);
  }

  /// _writeString writes string.

  Future<void> _writeString(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
      return;
    }
    await _secureStorage.write(key: key, value: value);
  }

  /// _remove removes stored data.

  Future<void> _remove(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    }
    await _secureStorage.delete(key: key);
  }
}
