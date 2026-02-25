import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';
import '../network/api_paths.dart';

/// PushNotificationService represents push notification service.

class PushNotificationService {
  bool _initialized = false;
  bool _initializing = false;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<String>? _onTokenRefreshSub;

  /// initialize handles internal initialize behavior.

  Future<void> initialize({
    required AppConfig config,
    required String accessToken,
    required ApiClient apiClient,
  }) async {
    if (_initialized) return;
    if (_initializing) return;
    if (!config.enablePush) return;
    if (config.authMode != AuthMode.standalone) return;
    if (accessToken.trim().isEmpty) return;

    _initializing = true;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if ((token ?? '').isNotEmpty) {
        try {
          await _syncToken(
            apiClient: apiClient,
            accessToken: accessToken,
            fcmToken: token!,
          );
          debugPrint('FCM token synced');
        } catch (error) {
          debugPrint('FCM token sync failed: $error');
        }
      }

      _onTokenRefreshSub = messaging.onTokenRefresh.listen((newToken) {
        unawaited(
          _syncToken(
            apiClient: apiClient,
            accessToken: accessToken,
            fcmToken: newToken,
          )
              .then((_) => debugPrint('FCM token refreshed and synced'))
              .catchError((error) =>
                  debugPrint('FCM token refresh sync failed: $error')),
        );
      });

      _onMessageSub = FirebaseMessaging.onMessage.listen((message) {
        debugPrint('Push foreground message: ${message.messageId}');
      });

      _initialized = true;
    } catch (error) {
      debugPrint('Push init skipped: $error');
    } finally {
      _initializing = false;
    }
  }

  /// dispose releases resources held by this instance.

  Future<void> dispose() async {
    await _onMessageSub?.cancel();
    await _onTokenRefreshSub?.cancel();
  }

  /// _syncToken handles sync token.

  Future<void> _syncToken({
    required ApiClient apiClient,
    required String accessToken,
    required String fcmToken,
  }) {
    final platform = _platformName();
    final appVersion =
        const String.fromEnvironment('APP_VERSION', defaultValue: '').trim();

    return apiClient.post<void>(
      ApiPaths.mePushToken,
      token: accessToken,
      body: <String, dynamic>{
        'token': fcmToken,
        'platform': platform,
        if (appVersion.isNotEmpty) 'appVersion': appVersion,
      },
      decoder: (_) {},
    );
  }

  /// _platformName handles platform name.

  String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'web';
    }
  }
}
