import 'package:flutter/foundation.dart';

enum AuthMode {
  telegramWeb,
  standalone,
}

class AppConfig {
  AppConfig({
    required this.apiUrl,
    required this.botUsername,
    required this.vkAppId,
    required this.authMode,
    required this.standaloneAuthUrl,
    required this.standaloneRedirectUri,
    required this.enablePush,
    required this.adminTelegramIds,
    required this.paymentPhoneNumber,
    required this.paymentUsdtWallet,
    required this.paymentUsdtNetwork,
    required this.paymentUsdtMemo,
    required this.paymentQrData,
  });

  final String apiUrl;
  final String botUsername;
  final String vkAppId;
  final AuthMode authMode;
  final String standaloneAuthUrl;
  final String standaloneRedirectUri;
  final bool enablePush;
  final Set<int> adminTelegramIds;
  final String paymentPhoneNumber;
  final String paymentUsdtWallet;
  final String paymentUsdtNetwork;
  final String paymentUsdtMemo;
  final String paymentQrData;

  bool get isTelegramWebMode => authMode == AuthMode.telegramWeb;

  static AppConfig fromEnvironment() {
    const envApiUrl = String.fromEnvironment('API_URL', defaultValue: '');
    const rawBotUsername =
        String.fromEnvironment('BOT_USERNAME', defaultValue: '');
    const rawVkAppId = String.fromEnvironment('VK_APP_ID', defaultValue: '');
    const rawAuthMode = String.fromEnvironment('AUTH_MODE', defaultValue: '');
    const rawStandaloneAuthUrl =
        String.fromEnvironment('STANDALONE_AUTH_URL', defaultValue: '');
    const rawStandaloneRedirectUri = String.fromEnvironment(
        'STANDALONE_REDIRECT_URI',
        defaultValue: 'gigme://auth');
    const rawEnablePush =
        String.fromEnvironment('ENABLE_PUSH', defaultValue: 'false');
    const rawAdminTelegramIds =
        String.fromEnvironment('ADMIN_TELEGRAM_IDS', defaultValue: '');
    const rawPaymentPhone =
        String.fromEnvironment('PAYMENT_PHONE_NUMBER', defaultValue: '');
    const rawPaymentUsdtWallet =
        String.fromEnvironment('PAYMENT_USDT_WALLET', defaultValue: '');
    const rawPaymentUsdtNetwork =
        String.fromEnvironment('PAYMENT_USDT_NETWORK', defaultValue: 'TRC20');
    const rawPaymentUsdtMemo =
        String.fromEnvironment('PAYMENT_USDT_MEMO', defaultValue: '');
    const rawPaymentQrData =
        String.fromEnvironment('PAYMENT_QR_DATA', defaultValue: '');
    const defaultApiUrl = kIsWeb ? '/api' : 'https://spacefestival.fun/api';
    final rawApiUrl = envApiUrl.trim().isEmpty ? defaultApiUrl : envApiUrl;
    final apiUrl = _normalizeApiUrl(rawApiUrl);
    final standaloneRedirectUri = rawStandaloneRedirectUri.trim().isEmpty
        ? 'gigme://auth'
        : rawStandaloneRedirectUri.trim();

    return AppConfig(
      apiUrl: apiUrl,
      botUsername: rawBotUsername.trim(),
      vkAppId: rawVkAppId.trim(),
      authMode: _resolveAuthMode(rawAuthMode),
      standaloneAuthUrl: _resolveStandaloneAuthUrl(
        rawStandaloneAuthUrl: rawStandaloneAuthUrl,
        normalizedApiUrl: apiUrl,
      ),
      standaloneRedirectUri: standaloneRedirectUri,
      enablePush: rawEnablePush.toLowerCase().trim() == 'true',
      adminTelegramIds: _parseAdminIds(rawAdminTelegramIds),
      paymentPhoneNumber: rawPaymentPhone.trim(),
      paymentUsdtWallet: rawPaymentUsdtWallet.trim(),
      paymentUsdtNetwork: rawPaymentUsdtNetwork.trim(),
      paymentUsdtMemo: rawPaymentUsdtMemo.trim(),
      paymentQrData: rawPaymentQrData.trim(),
    );
  }

  static AuthMode _resolveAuthMode(String rawAuthMode) {
    final mode = rawAuthMode.toLowerCase().trim();
    if (mode == 'standalone') return AuthMode.standalone;
    if (mode == 'telegram_web') {
      // Telegram Web initData does not exist on native mobile.
      return kIsWeb ? AuthMode.telegramWeb : AuthMode.standalone;
    }
    return kIsWeb ? AuthMode.telegramWeb : AuthMode.standalone;
  }

  static String _resolveStandaloneAuthUrl({
    required String rawStandaloneAuthUrl,
    required String normalizedApiUrl,
  }) {
    final explicit = rawStandaloneAuthUrl.trim();
    if (explicit.isNotEmpty) {
      return _normalizeApiUrl(explicit);
    }

    final apiUri = Uri.tryParse(normalizedApiUrl);
    if (apiUri == null || apiUri.scheme.isEmpty || apiUri.host.isEmpty) {
      return '';
    }

    final pathSegments = <String>[
      for (final segment in apiUri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    if (pathSegments.isNotEmpty && pathSegments.last.toLowerCase() == 'api') {
      pathSegments.addAll(const ['auth', 'standalone']);
    } else {
      pathSegments.addAll(const ['api', 'auth', 'standalone']);
    }

    final resolved = apiUri.replace(
      pathSegments: pathSegments,
      queryParameters: const <String, String>{},
    );
    final raw = resolved.toString();
    final hashIndex = raw.indexOf('#');
    if (hashIndex < 0) {
      return raw;
    }
    return raw.substring(0, hashIndex);
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
