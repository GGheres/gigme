import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/models/auth_session.dart';
import '../../../core/network/providers.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/storage/vk_oauth_state_storage.dart';
import '../../../core/utils/startup_link.dart';
import '../../../core/utils/vk_auth.dart';
import '../../../integrations/telegram/telegram_web_app_bridge.dart';
import '../data/auth_repository.dart';
import 'auth_state.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required this.config,
    required this.repository,
    required this.tokenStorage,
    required this.vkOAuthStateStorage,
  }) {
    unawaited(initialize());
  }

  final AppConfig config;
  final AuthRepository repository;
  final TokenStorage tokenStorage;
  final VkOAuthStateStorage vkOAuthStateStorage;

  AuthState _state = AuthState.loading();
  AuthState get state => _state;

  StartupLink _startupLink = const StartupLink();
  StartupLink get startupLink => _startupLink;
  bool _startupLinkConsumed = false;
  StreamSubscription<Uri>? _standaloneLinkSub;
  bool _standaloneListenerStarted = false;
  Uri? _launchUri;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _launchUri = Uri.base;

    _startupLink = StartupLinkParser.parse();

    if (kIsWeb && config.isTelegramWebMode) {
      final telegramInitData = TelegramWebAppBridge.getInitData();
      if (telegramInitData != null && telegramInitData.isNotEmpty) {
        TelegramWebAppBridge.readyAndExpand();
      }
    }

    final persistedToken = await tokenStorage.readToken();
    if (persistedToken != null && persistedToken.trim().isNotEmpty) {
      try {
        final user = await repository.getMe(persistedToken);
        _state = AuthState.authenticated(token: persistedToken, user: user);
        notifyListeners();
        await _claimPendingReferralIfNeeded(token: persistedToken);
        return;
      } catch (_) {
        await tokenStorage.clearToken();
      }
    }

    if (kIsWeb) {
      final vkLaunchParams = _resolveVkMiniAppLaunchParams();
      if (vkLaunchParams != null && vkLaunchParams.isNotEmpty) {
        await loginWithVkMiniApp(launchParams: vkLaunchParams);
        return;
      }

      final vkCodeCredentials = await _resolveVkAuthCodeCredentials();
      if (vkCodeCredentials != null) {
        await loginWithVkCode(
          code: vkCodeCredentials.code,
          state: vkCodeCredentials.state,
          deviceId: vkCodeCredentials.deviceId,
        );
        return;
      }

      final vkCredentials = _resolveVkAuthCredentials();
      if (vkCredentials != null) {
        await loginWithVk(
          accessToken: vkCredentials.accessToken,
          userId: vkCredentials.userId,
        );
        return;
      }

      final vkError = _resolveVkAuthError();
      if (vkError != null && vkError.isNotEmpty) {
        _state = AuthState.unauthenticated(error: 'VK auth failed: $vkError');
        notifyListeners();
        return;
      }
    }

    if (config.isTelegramWebMode) {
      final initData = _resolveTelegramInitData();
      if (initData == null || initData.isEmpty) {
        _state = AuthState.unauthenticated(
          error:
              'Open this app inside Telegram WebApp or pass initData for debug.',
        );
        notifyListeners();
        return;
      }

      await loginWithTelegram(initData);
      return;
    }

    await _startStandaloneLinkListener();
    final initData = _resolveTelegramInitData();
    if (initData != null && initData.isNotEmpty) {
      await loginWithTelegram(initData);
      return;
    }

    _state = AuthState.unauthenticated(
      error: 'Use standalone auth helper or paste initData to continue.',
    );
    notifyListeners();
  }

  Future<void> loginWithTelegram(String initData) async {
    _state = AuthState.loading();
    notifyListeners();

    try {
      final session = await repository.loginWithTelegram(initData);
      await tokenStorage.writeToken(session.accessToken);
      _state = AuthState.authenticated(
        token: session.accessToken,
        user: session.user,
      );
      notifyListeners();
      await _claimPendingReferralIfNeeded(token: session.accessToken);
    } catch (error) {
      _state = AuthState.unauthenticated(error: _mapVkAuthError(error));
      notifyListeners();
    }
  }

  Future<void> loginWithVk({
    required String accessToken,
    int? userId,
  }) async {
    _state = AuthState.loading();
    notifyListeners();

    try {
      final session = await repository.loginWithVk(
        accessToken: accessToken,
        userId: userId,
      );
      await tokenStorage.writeToken(session.accessToken);
      _state = AuthState.authenticated(
        token: session.accessToken,
        user: session.user,
      );
      notifyListeners();
      await _claimPendingReferralIfNeeded(token: session.accessToken);
    } catch (error) {
      _state = AuthState.unauthenticated(error: _mapVkAuthError(error));
      notifyListeners();
    }
  }

  Future<void> loginWithVkCode({
    required String code,
    required String state,
    required String deviceId,
  }) async {
    _state = AuthState.loading();
    notifyListeners();

    try {
      final session = await repository.loginWithVkCode(
        code: code,
        state: state,
        deviceId: deviceId,
      );
      await tokenStorage.writeToken(session.accessToken);
      _state = AuthState.authenticated(
        token: session.accessToken,
        user: session.user,
      );
      notifyListeners();
      await _claimPendingReferralIfNeeded(token: session.accessToken);
    } catch (error) {
      _state = AuthState.unauthenticated(error: _mapVkAuthError(error));
      notifyListeners();
    } finally {
      await vkOAuthStateStorage.clearState();
    }
  }

  Future<void> loginWithVkMiniApp({
    required String launchParams,
  }) async {
    _state = AuthState.loading();
    notifyListeners();

    try {
      final session = await repository.loginWithVkMiniApp(
        launchParams: launchParams,
      );
      await tokenStorage.writeToken(session.accessToken);
      _state = AuthState.authenticated(
        token: session.accessToken,
        user: session.user,
      );
      notifyListeners();
      await _claimPendingReferralIfNeeded(token: session.accessToken);
    } catch (error) {
      _state = AuthState.unauthenticated(error: error.toString());
      notifyListeners();
    }
  }

  Future<void> refreshMe() async {
    final token = _state.token;
    if (token == null || token.isEmpty) return;

    try {
      final user = await repository.getMe(token);
      _state = AuthState.authenticated(token: token, user: user);
      notifyListeners();
    } catch (_) {
      await logout();
    }
  }

  Future<void> logout() async {
    await tokenStorage.clearToken();
    _state = AuthState.unauthenticated();
    notifyListeners();
  }

  Future<void> applySession(AuthSession session) async {
    await tokenStorage.writeToken(session.accessToken);
    _state = AuthState.authenticated(
      token: session.accessToken,
      user: session.user,
    );
    notifyListeners();
  }

  Future<void> retryAuth() async {
    if (kIsWeb) {
      final vkLaunchParams = _resolveVkMiniAppLaunchParams();
      if (vkLaunchParams != null && vkLaunchParams.isNotEmpty) {
        await loginWithVkMiniApp(launchParams: vkLaunchParams);
        return;
      }

      final vkCodeCredentials = await _resolveVkAuthCodeCredentials();
      if (vkCodeCredentials != null) {
        await loginWithVkCode(
          code: vkCodeCredentials.code,
          state: vkCodeCredentials.state,
          deviceId: vkCodeCredentials.deviceId,
        );
        return;
      }

      final vkCredentials = _resolveVkAuthCredentials();
      if (vkCredentials != null) {
        await loginWithVk(
          accessToken: vkCredentials.accessToken,
          userId: vkCredentials.userId,
        );
        return;
      }

      final vkError = _resolveVkAuthError();
      if (vkError != null && vkError.isNotEmpty) {
        _state = AuthState.unauthenticated(error: 'VK auth failed: $vkError');
        notifyListeners();
        return;
      }
    }

    final initData = _resolveTelegramInitData();
    if (initData == null || initData.isEmpty) {
      _state = AuthState.unauthenticated(
        error: config.isTelegramWebMode
            ? 'Telegram initData not found. Open via Telegram WebApp.'
            : 'Standalone initData is missing. Open helper login URL or paste initData.',
      );
      notifyListeners();
      return;
    }
    await loginWithTelegram(initData);
  }

  Future<void> _claimPendingReferralIfNeeded({required String token}) async {
    final eventId = _startupLink.eventId;
    final refCode = _startupLink.refCode;
    if (eventId == null || eventId <= 0 || refCode == null || refCode.isEmpty) {
      return;
    }

    try {
      final claim = await repository.claimReferral(
        token: token,
        eventId: eventId,
        refCode: refCode,
      );
      if (claim.awarded &&
          _state.user != null &&
          claim.inviteeBalanceTokens > 0) {
        final updatedUser =
            _state.user!.copyWith(balanceTokens: claim.inviteeBalanceTokens);
        _state = AuthState.authenticated(token: token, user: updatedUser);
        notifyListeners();
      }
    } catch (_) {
      // Referral claim should not block the login flow.
    }
  }

  StartupLink? consumeStartupLink() {
    if (_startupLinkConsumed || !_startupLink.hasEvent) return null;
    _startupLinkConsumed = true;
    return _startupLink;
  }

  String? _resolveTelegramInitData() {
    final fromBridge = TelegramWebAppBridge.getInitData();
    if (fromBridge != null && fromBridge.isNotEmpty) return fromBridge;

    final fromLaunchUri = _extractInitDataFromUri(_launchUri);
    if (fromLaunchUri != null && fromLaunchUri.isNotEmpty) return fromLaunchUri;

    return _extractInitDataFromUri(Uri.base);
  }

  VkAuthCredentials? _resolveVkAuthCredentials() {
    final fromLaunchUri = parseVkAuthCredentialsFromUri(_launchUri);
    if (fromLaunchUri != null) return fromLaunchUri;
    return parseVkAuthCredentialsFromUri(Uri.base);
  }

  Future<VkAuthCodeCredentials?> _resolveVkAuthCodeCredentials() async {
    final fromLaunchUri = parseVkAuthCodeCredentialsFromUri(_launchUri);
    final parsedFromUri =
        fromLaunchUri ?? parseVkAuthCodeCredentialsFromUri(Uri.base);
    if (parsedFromUri == null) return null;

    final persistedState = (await vkOAuthStateStorage.readState() ?? '').trim();
    if (persistedState.isEmpty) {
      return parsedFromUri;
    }

    return VkAuthCodeCredentials(
      code: parsedFromUri.code,
      state: persistedState,
      deviceId: parsedFromUri.deviceId,
    );
  }

  String? _resolveVkMiniAppLaunchParams() {
    final fromLaunchUri = extractVkMiniAppLaunchParams(_launchUri);
    if (fromLaunchUri != null && fromLaunchUri.isNotEmpty) {
      return fromLaunchUri;
    }
    return extractVkMiniAppLaunchParams(Uri.base);
  }

  String? _resolveVkAuthError() {
    final fromLaunchUri = parseVkAuthErrorFromUri(_launchUri);
    if (fromLaunchUri != null && fromLaunchUri.isNotEmpty) {
      return fromLaunchUri;
    }
    return parseVkAuthErrorFromUri(Uri.base);
  }

  String _mapVkAuthError(Object error) {
    if (error is AppException) {
      final statusCode = error.statusCode ?? 0;
      final apiMessage = error.message.trim();
      final normalizedMessage = apiMessage.toLowerCase();

      if (statusCode == 401 && normalizedMessage == 'invalid vk auth state') {
        return 'Сессия VK входа истекла или недействительна. Нажмите "Войти через VK" снова.';
      }

      if (statusCode == 401 &&
          normalizedMessage == 'invalid vk authorization code') {
        return 'Код VK недействителен или уже использован. Запустите вход через VK заново.';
      }

      if (statusCode == 401 && normalizedMessage == 'vk user id is missing') {
        return 'VK не вернул ID пользователя. Попробуйте вход через VK еще раз.';
      }

      if (statusCode == 503 && normalizedMessage == 'vk auth is disabled') {
        return 'VK вход отключен на сервере. Добавьте VK_APP_ID/VK_APP_SECRET в backend и перезапустите API.';
      }

      if (statusCode >= 500) {
        return 'VK сервис временно недоступен. Попробуйте позже.';
      }

      if (apiMessage.isNotEmpty) {
        return apiMessage;
      }
    }

    return error.toString();
  }

  String? _extractInitDataFromUri(Uri? uri) {
    if (uri == null) return null;

    final fromQuery =
        uri.queryParameters['initData'] ?? uri.queryParameters['tgWebAppData'];
    if ((fromQuery ?? '').trim().isNotEmpty) return fromQuery!.trim();

    final fragment = uri.fragment.trim();
    if (fragment.isEmpty) return null;

    final candidates = <String>{fragment};
    final questionMarkIndex = fragment.indexOf('?');
    if (questionMarkIndex >= 0 && questionMarkIndex < fragment.length - 1) {
      candidates.add(fragment.substring(questionMarkIndex + 1));
    }

    for (final candidate in candidates) {
      try {
        final params = Uri.splitQueryString(candidate);
        final fromHash = params['initData'] ?? params['tgWebAppData'];
        if ((fromHash ?? '').trim().isNotEmpty) return fromHash!.trim();
      } catch (_) {
        // Ignore invalid hash formats and continue fallback attempts.
      }
    }

    return null;
  }

  Future<void> _startStandaloneLinkListener() async {
    if (_standaloneListenerStarted || config.isTelegramWebMode) return;
    _standaloneListenerStarted = true;

    try {
      final appLinks = AppLinks();
      final initial = await appLinks.getInitialLink();
      if (initial != null) {
        unawaited(_handleStandaloneUri(initial));
      }
      _standaloneLinkSub = appLinks.uriLinkStream.listen((uri) {
        unawaited(_handleStandaloneUri(uri));
      });
    } catch (_) {
      // Standalone deep-link listener is best-effort.
    }
  }

  Future<void> _handleStandaloneUri(Uri uri) async {
    final initData = _extractInitDataFromUri(uri);
    if (initData == null || initData.isEmpty) return;
    await loginWithTelegram(initData);
  }

  @override
  void dispose() {
    _standaloneLinkSub?.cancel();
    super.dispose();
  }
}

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  final controller = AuthController(
    config: ref.watch(appConfigProvider),
    repository: ref.watch(authRepositoryProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    vkOAuthStateStorage: ref.watch(vkOAuthStateStorageProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
