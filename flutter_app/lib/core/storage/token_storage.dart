import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../utils/json_utils.dart';

class PersistedAuthSession {
  const PersistedAuthSession({
    required this.token,
    required this.user,
  });

  factory PersistedAuthSession.fromJson(dynamic json) {
    final map = asMap(json);
    return PersistedAuthSession(
      token: asString(map['accessToken']).trim(),
      user: User.fromJson(map['user']),
    );
  }

  final String token;
  final User user;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'accessToken': token,
      'user': user.toJson(),
    };
  }
}

class TokenStorage {
  static const _tokenKey = 'gigme_access_token';
  static const _sessionKey = 'gigme_auth_session';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<String?> readToken() async {
    final session = await readSession();
    if (session != null && session.token.isNotEmpty) {
      return session.token;
    }

    return _readString(_tokenKey);
  }

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

  Future<void> writeToken(String token) async {
    await _writeString(_tokenKey, token);
  }

  Future<void> writeSession({
    required String token,
    required User user,
  }) async {
    final session = PersistedAuthSession(token: token, user: user);
    await _writeString(_sessionKey, jsonEncode(session.toJson()));
    await _writeString(_tokenKey, token);
  }

  Future<void> clearToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
      await prefs.remove(_tokenKey);
      return;
    }
    await _secureStorage.delete(key: _sessionKey);
    await _secureStorage.delete(key: _tokenKey);
  }

  Future<String?> _readString(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    return _secureStorage.read(key: key);
  }

  Future<void> _writeString(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
      return;
    }
    await _secureStorage.write(key: key, value: value);
  }

  Future<void> _remove(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    }
    await _secureStorage.delete(key: key);
  }
}
