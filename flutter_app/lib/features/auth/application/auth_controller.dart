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

/// AuthController represents auth controller.

class AuthController extends ChangeNotifier {
  /// AuthController authenticates controller.
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

  /// state exposes the current state value.
  AuthState get state => _state;

  StartupLink _startupLink = const StartupLink();

  /// startupLink handles startup link.
  StartupLink get startupLink => _startupLink;
  bool _startupLinkConsumed = false;
  StreamSubscription<Uri>? _standaloneLinkSub;
  bool _standaloneListenerStarted = false;
  Uri? _launchUri;

  bool _initialized = false;

  /// initialize handles internal initialize behavior.

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

    final restoredFromSession = await _restorePersistedSession();
    if (restoredFromSession) {
      return;
    }

    final restoredFromLegacyToken = await _restoreLegacyTokenSession();
    if (restoredFromLegacyToken) {
      return;
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
      final initData = await _resolveTelegramInitDataOrSaved();
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
    final initData = await _resolveTelegramInitDataOrSaved();
    if (initData != null && initData.isNotEmpty) {
      await loginWithTelegram(initData);
      return;
    }

    _state = AuthState.unauthenticated(
      error: 'Use standalone auth helper or paste initData to continue.',
    );
    notifyListeners();
  }

  /// loginWithTelegram handles login with telegram.

  Future<void> loginWithTelegram(String initData) async {
    _state = AuthState.loading();
    notifyListeners();

    try {
      final session = await repository.loginWithTelegram(initData);
      await _persistSession(session: session, telegramInitData: initData);
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

  /// loginWithVk handles login with vk.

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
      await _persistSession(session: session);
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

  /// loginWithVkCode handles login with vk code.

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
      await _persistSession(session: session);
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

  /// loginWithVkMiniApp handles login with vk mini app.

  Future<void> loginWithVkMiniApp({
    required String launchParams,
  }) async {
    _state = AuthState.loading();
    notifyListeners();

    try {
      final session = await repository.loginWithVkMiniApp(
        launchParams: launchParams,
      );
      await _persistSession(session: session);
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

  /// refreshMe handles refresh me.

  Future<void> refreshMe() async {
    final token = _state.token;
    if (token == null || token.isEmpty) return;

    try {
      final user = await repository.getMe(token);
      _state = AuthState.authenticated(token: token, user: user);
      notifyListeners();
      await tokenStorage.writeSession(token: token, user: user);
    } catch (error) {
      if (_isUnauthorizedError(error)) {
        final reloginSucceeded =
            await _reauthenticateWithStoredTelegramInitData();
        if (!reloginSucceeded) {
          await logout();
        }
      }
    }
  }

  /// logout handles internal logout behavior.

  Future<void> logout() async {
    await tokenStorage.clearToken();
    _state = AuthState.unauthenticated();
    notifyListeners();
  }

  /// applySession handles apply session.

  Future<void> applySession(AuthSession session) async {
    await _persistSession(session: session);
    _state = AuthState.authenticated(
      token: session.accessToken,
      user: session.user,
    );
    notifyListeners();
  }

  /// retryAuth handles retry auth.

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

    final initData = await _resolveTelegramInitDataOrSaved();
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

  /// _restorePersistedSession handles restore persisted session.

  Future<bool> _restorePersistedSession() async {
    final persisted = await tokenStorage.readSession();
    if (persisted == null || persisted.token.trim().isEmpty) {
      return false;
    }

    final token = persisted.token.trim();
    _state = AuthState.authenticated(token: token, user: persisted.user);
    notifyListeners();

    try {
      final user = await repository.getMe(token);
      _state = AuthState.authenticated(token: token, user: user);
      notifyListeners();
      await tokenStorage.writeSession(token: token, user: user);
      await _claimPendingReferralIfNeeded(token: token);
      return true;
    } catch (error) {
      if (_isUnauthorizedError(error)) {
        final reloginSucceeded =
            await _reauthenticateWithStoredTelegramInitData();
        if (reloginSucceeded) {
          return true;
        }
        await tokenStorage.clearToken();
        _state = AuthState.unauthenticated();
        notifyListeners();
        return false;
      }
      // Keep cached session on temporary network/API failures.
      return true;
    }
  }

  /// _restoreLegacyTokenSession handles restore legacy token session.

  Future<bool> _restoreLegacyTokenSession() async {
    final persistedToken = await tokenStorage.readToken();
    if (persistedToken == null || persistedToken.trim().isEmpty) {
      return false;
    }

    final token = persistedToken.trim();
    try {
      final user = await repository.getMe(token);
      _state = AuthState.authenticated(token: token, user: user);
      notifyListeners();
      await tokenStorage.writeSession(token: token, user: user);
      await _claimPendingReferralIfNeeded(token: token);
      return true;
    } catch (error) {
      if (_isUnauthorizedError(error)) {
        final reloginSucceeded =
            await _reauthenticateWithStoredTelegramInitData();
        if (reloginSucceeded) {
          return true;
        }
        await tokenStorage.clearToken();
      }
      return false;
    }
  }

  /// _persistSession handles persist session.

  Future<void> _persistSession({
    required AuthSession session,
    String? telegramInitData,
  }) async {
    await tokenStorage.writeSession(
      token: session.accessToken,
      user: session.user,
    );
    if (telegramInitData != null && telegramInitData.trim().isNotEmpty) {
      await tokenStorage.writeTelegramInitData(telegramInitData);
      return;
    }
    await tokenStorage.clearTelegramInitData();
  }

  /// _resolveTelegramInitDataOrSaved handles resolve telegram init data or saved.

  Future<String?> _resolveTelegramInitDataOrSaved() async {
    final fromRuntime = _resolveTelegramInitData();
    if (fromRuntime != null && fromRuntime.isNotEmpty) {
      return fromRuntime;
    }
    return tokenStorage.readTelegramInitData();
  }

  /// _reauthenticateWithStoredTelegramInitData handles reauthenticate with stored telegram init data.

  Future<bool> _reauthenticateWithStoredTelegramInitData() async {
    final initData = await tokenStorage.readTelegramInitData();
    if (initData == null || initData.isEmpty) {
      return false;
    }

    try {
      final session = await repository.loginWithTelegram(initData);
      await _persistSession(session: session, telegramInitData: initData);
      _state = AuthState.authenticated(
        token: session.accessToken,
        user: session.user,
      );
      notifyListeners();
      await _claimPendingReferralIfNeeded(token: session.accessToken);
      return true;
    } catch (_) {
      await tokenStorage.clearTelegramInitData();
      return false;
    }
  }

  /// _isUnauthorizedError reports whether unauthorized error condition is met.

  bool _isUnauthorizedError(Object error) {
    if (error is! AppException) return false;
    final statusCode = error.statusCode ?? 0;
    return statusCode == 401 || statusCode == 403;
  }

  /// _claimPendingReferralIfNeeded claims pending referral if needed.

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
        await tokenStorage.writeSession(token: token, user: updatedUser);
      }
    } catch (_) {
      // Referral claim should not block the login flow.
    }
  }

  /// consumeStartupLink handles consume startup link.

  StartupLink? consumeStartupLink() {
    if (_startupLinkConsumed || !_startupLink.hasEvent) return null;
    _startupLinkConsumed = true;
    return _startupLink;
  }

  /// _resolveTelegramInitData handles resolve telegram init data.

  String? _resolveTelegramInitData() {
    final fromBridge = TelegramWebAppBridge.getInitData();
    if (fromBridge != null && fromBridge.isNotEmpty) return fromBridge;

    final fromLaunchUri = _extractInitDataFromUri(_launchUri);
    if (fromLaunchUri != null && fromLaunchUri.isNotEmpty) return fromLaunchUri;

    return _extractInitDataFromUri(Uri.base);
  }

  /// _resolveVkAuthCredentials handles resolve vk auth credentials.

  VkAuthCredentials? _resolveVkAuthCredentials() {
    final fromLaunchUri = parseVkAuthCredentialsFromUri(_launchUri);
    if (fromLaunchUri != null) return fromLaunchUri;
    return parseVkAuthCredentialsFromUri(Uri.base);
  }

  /// _resolveVkAuthCodeCredentials handles resolve vk auth code credentials.

  Future<VkAuthCodeCredentials?> _resolveVkAuthCodeCredentials() async {
    final fromLaunchUri = parseVkAuthCodeCredentialsFromUri(_launchUri);
    final parsedFromUri =
        fromLaunchUri ?? parseVkAuthCodeCredentialsFromUri(Uri.base);
    if (parsedFromUri == null) return null;

    final stateFromUri = parsedFromUri.state.trim();
    if (stateFromUri.isNotEmpty) {
      return parsedFromUri;
    }

    final persistedState = (await vkOAuthStateStorage.readState() ?? '').trim();
    if (persistedState.isEmpty) {
      return null;
    }

    return VkAuthCodeCredentials(
      code: parsedFromUri.code,
      state: persistedState,
      deviceId: parsedFromUri.deviceId,
    );
  }

  /// _resolveVkMiniAppLaunchParams handles resolve vk mini app launch params.

  String? _resolveVkMiniAppLaunchParams() {
    final fromLaunchUri = extractVkMiniAppLaunchParams(_launchUri);
    if (fromLaunchUri != null && fromLaunchUri.isNotEmpty) {
      return fromLaunchUri;
    }
    return extractVkMiniAppLaunchParams(Uri.base);
  }

  /// _resolveVkAuthError handles resolve vk auth error.

  String? _resolveVkAuthError() {
    final fromLaunchUri = parseVkAuthErrorFromUri(_launchUri);
    if (fromLaunchUri != null && fromLaunchUri.isNotEmpty) {
      return fromLaunchUri;
    }
    return parseVkAuthErrorFromUri(Uri.base);
  }

  /// _mapVkAuthError maps vk auth error.

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

  /// _extractInitDataFromUri extracts init data from uri.

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

  /// _startStandaloneLinkListener handles start standalone link listener.

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

  /// _handleStandaloneUri handles standalone uri.

  Future<void> _handleStandaloneUri(Uri uri) async {
    final initData = _extractInitDataFromUri(uri);
    if (initData == null || initData.isEmpty) return;
    await loginWithTelegram(initData);
  }

  /// dispose releases resources held by this instance.

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
