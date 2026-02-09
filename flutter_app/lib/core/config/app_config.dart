import 'package:flutter/foundation.dart';

enum AuthMode {
  telegramWeb,
  standalone,
}

class AppConfig {
  AppConfig({
    required this.apiUrl,
    required this.botUsername,
    required this.authMode,
    required this.standaloneAuthUrl,
    required this.standaloneRedirectUri,
    required this.enablePush,
    required this.adminTelegramIds,
  });

  final String apiUrl;
  final String botUsername;
  final AuthMode authMode;
  final String standaloneAuthUrl;
  final String standaloneRedirectUri;
  final bool enablePush;
  final Set<int> adminTelegramIds;

  bool get isTelegramWebMode => authMode == AuthMode.telegramWeb;

  static AppConfig fromEnvironment() {
    const rawApiUrl = String.fromEnvironment('API_URL', defaultValue: '/api');
    const rawBotUsername = String.fromEnvironment('BOT_USERNAME', defaultValue: '');
    const rawAuthMode = String.fromEnvironment('AUTH_MODE', defaultValue: 'telegram_web');
    const rawStandaloneAuthUrl = String.fromEnvironment('STANDALONE_AUTH_URL', defaultValue: '');
    const rawStandaloneRedirectUri = String.fromEnvironment('STANDALONE_REDIRECT_URI', defaultValue: 'gigme://auth');
    const rawEnablePush = String.fromEnvironment('ENABLE_PUSH', defaultValue: 'false');
    const rawAdminTelegramIds = String.fromEnvironment('ADMIN_TELEGRAM_IDS', defaultValue: '');

    return AppConfig(
      apiUrl: _normalizeApiUrl(rawApiUrl),
      botUsername: rawBotUsername.trim(),
      authMode: rawAuthMode.toLowerCase().trim() == 'standalone'
          ? AuthMode.standalone
          : AuthMode.telegramWeb,
      standaloneAuthUrl: rawStandaloneAuthUrl.trim(),
      standaloneRedirectUri: rawStandaloneRedirectUri.trim(),
      enablePush: rawEnablePush.toLowerCase().trim() == 'true',
      adminTelegramIds: _parseAdminIds(rawAdminTelegramIds),
    );
  }

  static String _normalizeApiUrl(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');
    final origin = _webOrigin();

    if (trimmed.isEmpty) {
      return origin;
    }

    if (trimmed.startsWith('/')) {
      if (origin.isEmpty) return trimmed;
      return '$origin$trimmed';
    }

    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed);
    if (hasScheme) {
      return trimmed.replaceAll(RegExp(r'/+$'), '');
    }

    if (trimmed.startsWith('localhost') || trimmed.startsWith('127.0.0.1')) {
      return 'http://$trimmed';
    }

    return 'https://${trimmed.replaceAll(RegExp(r'^/+'), '')}';
  }

  static String _webOrigin() {
    if (!kIsWeb) return '';
    final base = Uri.base;
    if (base.scheme.isEmpty || base.host.isEmpty) return '';
    final port = base.hasPort &&
            !((base.scheme == 'http' && base.port == 80) ||
                (base.scheme == 'https' && base.port == 443))
        ? ':${base.port}'
        : '';
    return '${base.scheme}://${base.host}$port';
  }

  static Set<int> _parseAdminIds(String value) {
    final out = <int>{};
    for (final piece in value.split(',')) {
      final parsed = int.tryParse(piece.trim());
      if (parsed != null && parsed > 0) {
        out.add(parsed);
      }
    }
    return out;
  }
}
