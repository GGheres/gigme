import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/vk_auth.dart';
import '../../../integrations/telegram/telegram_web_app_bridge.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/input_field.dart';
import '../../../ui/components/section_card.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_spacing.dart';
import '../application/auth_controller.dart';
import '../application/auth_state.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final TextEditingController _initDataController = TextEditingController();
  bool _standaloneHelperLaunchAttempted = false;

  @override
  void dispose() {
    _initDataController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authController = ref.watch(authControllerProvider);
    final state = authController.state;
    final config = ref.watch(appConfigProvider);
    final standaloneHelperUri = _standaloneHelperUri(config);
    final vkLoginUri = _vkLoginUri(config);
    _scheduleStandaloneHelperAutoLaunch(
      state: state,
      config: config,
      standaloneHelperUri: standaloneHelperUri,
    );

    if (config.authMode == AuthMode.telegramWeb) {
      return _buildTelegramWebScreen(
        state: state,
        config: config,
        standaloneHelperUri: standaloneHelperUri,
        vkLoginUri: vkLoginUri,
      );
    }

    return AppScaffold(
      title: 'Вход',
      subtitle: vkLoginUri == null
          ? 'Авторизация в SPACE через Telegram'
          : 'Авторизация в SPACE через Telegram или VK',
      showBackgroundDecor: true,
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            children: [
              SectionCard(
                title: vkLoginUri == null ? 'Telegram Login' : 'Web Login',
                subtitle: _subtitleForMode(config.authMode),
                child: _buildStandaloneContent(
                  state: state,
                  config: config,
                  standaloneHelperUri: standaloneHelperUri,
                  vkLoginUri: vkLoginUri,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelegramWebScreen({
    required AuthState state,
    required AppConfig config,
    required Uri? standaloneHelperUri,
    required Uri? vkLoginUri,
  }) {
    final error = (state.error ?? '').trim();
    final canUseStandaloneHelper = standaloneHelperUri != null;
    final canUseVkLogin = vkLoginUri != null;

    return AppScaffold(
      title: 'Вход',
      subtitle: canUseVkLogin
          ? 'Быстрый вход через Telegram или VK'
          : 'Быстрый вход через Telegram',
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            children: [
              SectionCard(
                title: 'SPACE',
                subtitle: _subtitleForMode(config.authMode),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.status == AuthStatus.loading)
                      const LoadingState(
                        title: 'Проверяем сессию',
                        subtitle: 'Идет авторизация через Telegram',
                      )
                    else ...[
                      if (error.isNotEmpty) ...[
                        ErrorState(
                          message: error,
                          onRetry: () =>
                              ref.read(authControllerProvider).retryAuth(),
                          retryLabel: 'Повторить вход',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      PrimaryButton(
                        label: 'Повторить Telegram Login',
                        onPressed: () =>
                            ref.read(authControllerProvider).retryAuth(),
                        icon: const Icon(Icons.telegram_rounded),
                      ),
                      if (canUseStandaloneHelper) ...[
                        const SizedBox(height: AppSpacing.xs),
                        SecondaryButton(
                          label: 'Открыть Telegram Login',
                          outline: true,
                          onPressed: () async {
                            if (kIsWeb) {
                              final opened = TelegramWebAppBridge.openPopup(
                                standaloneHelperUri.toString(),
                              );
                              if (!opened) {
                                TelegramWebAppBridge.redirect(
                                  standaloneHelperUri.toString(),
                                );
                              }
                              return;
                            }
                            await launchUrl(
                              standaloneHelperUri,
                              mode: LaunchMode.platformDefault,
                            );
                          },
                        ),
                      ],
                      if (canUseVkLogin) ...[
                        const SizedBox(height: AppSpacing.xs),
                        SecondaryButton(
                          label: 'Войти через VK',
                          outline: true,
                          icon: const Icon(Icons.open_in_new_rounded),
                          onPressed: () async {
                            await _openWebAuthUri(vkLoginUri);
                          },
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandaloneContent({
    required AuthState state,
    required AppConfig config,
    required Uri? standaloneHelperUri,
    required Uri? vkLoginUri,
  }) {
    final error = (state.error ?? '').trim();

    if (state.status == AuthStatus.loading) {
      return const SizedBox(
        height: 180,
        child: LoadingState(
          title: 'Выполняем вход',
          subtitle: 'Проверяем данные Telegram',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error.isNotEmpty) ...[
          ErrorState(
            message: error,
            onRetry: () => ref.read(authControllerProvider).retryAuth(),
            retryLabel: 'Повторить',
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        PrimaryButton(
          label: config.authMode == AuthMode.telegramWeb
              ? 'Повторить Telegram Login'
              : 'Повторить авторизацию',
          onPressed: () => ref.read(authControllerProvider).retryAuth(),
          icon: const Icon(Icons.telegram_rounded),
        ),
        if (vkLoginUri != null) ...[
          const SizedBox(height: AppSpacing.xs),
          SecondaryButton(
            label: 'Войти через VK',
            outline: true,
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () async {
              await _openWebAuthUri(vkLoginUri);
            },
          ),
        ],
        if (config.authMode == AuthMode.standalone) ...[
          const SizedBox(height: AppSpacing.sm),
          InputField(
            controller: _initDataController,
            minLines: 3,
            maxLines: 8,
            label: 'Telegram initData',
            hint: 'Вставьте initData после входа в helper',
          ),
          const SizedBox(height: AppSpacing.xs),
          SecondaryButton(
            label: 'Войти с initData',
            onPressed: () {
              final initData = _initDataController.text.trim();
              if (initData.isEmpty) return;
              ref.read(authControllerProvider).loginWithTelegram(initData);
            },
            outline: true,
          ),
          if (standaloneHelperUri != null) ...[
            const SizedBox(height: AppSpacing.xs),
            SecondaryButton(
              label: 'Открыть auth helper',
              outline: true,
              onPressed: () async {
                await launchUrl(
                  standaloneHelperUri,
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Поток: открыть helper -> получить deep link с initData -> войти в SPACE.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  String _subtitleForMode(AuthMode mode) {
    switch (mode) {
      case AuthMode.telegramWeb:
        return 'Mode A: Telegram Web auth via initData';
      case AuthMode.standalone:
        return 'Mode B: standalone auth via deep link + initData';
    }
  }

  Uri? _vkLoginUri(AppConfig config) {
    if (!kIsWeb) return null;
    final appId = config.vkAppId.trim();
    if (appId.isEmpty) return null;

    final current = Uri.base;
    final next = (current.queryParameters['next'] ?? '').trim();
    final state = next.isEmpty ? AppRoutes.appRoot : next;
    final redirect = current.replace(
      path: AppRoutes.auth,
      queryParameters: const <String, String>{},
      fragment: '',
    );
    final redirectUri = Uri.parse(_withoutFragment(redirect));
    return buildVkOAuthAuthorizeUri(
      appId: appId,
      redirectUri: redirectUri,
      state: state,
    );
  }

  Future<void> _openWebAuthUri(Uri? uri) async {
    if (uri == null) return;

    if (kIsWeb) {
      TelegramWebAppBridge.redirect(uri.toString());
      return;
    }

    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  Uri? _standaloneHelperUri(AppConfig config) {
    final base = _resolveStandaloneHelperBaseUri(
      rawStandaloneAuthUrl: config.standaloneAuthUrl,
      apiUrl: config.apiUrl,
    );
    if (base == null) return null;

    final redirectUri = _effectiveStandaloneRedirectUri(config);
    if (redirectUri.isEmpty) return base;

    final query = <String, String>{
      ...base.queryParameters,
      'redirect_uri': redirectUri,
    };
    return base.replace(queryParameters: query);
  }

  Uri? _resolveStandaloneHelperBaseUri({
    required String rawStandaloneAuthUrl,
    required String apiUrl,
  }) {
    final raw = rawStandaloneAuthUrl.trim();
    if (raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    final absolute = parsed.hasScheme ? parsed : Uri.base.resolveUri(parsed);
    return _applyApiPrefixIfNeeded(helperUri: absolute, apiUrl: apiUrl);
  }

  Uri _applyApiPrefixIfNeeded({
    required Uri helperUri,
    required String apiUrl,
  }) {
    final helperSegments = <String>[
      for (final segment in helperUri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    if (helperSegments.length < 2) return helperUri;

    final tailIsAuthStandalone =
        helperSegments[helperSegments.length - 2].toLowerCase() == 'auth' &&
            helperSegments.last.toLowerCase() == 'standalone';
    if (!tailIsAuthStandalone) return helperUri;

    final apiUri = Uri.tryParse(apiUrl.trim());
    if (apiUri == null) return helperUri;
    final apiSegments = <String>[
      for (final segment in apiUri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    if (apiSegments.isEmpty) return helperUri;

    final startsWithApiPrefix = helperSegments.length >= apiSegments.length &&
        _segmentsMatch(
          left: helperSegments.take(apiSegments.length),
          right: apiSegments,
        );
    if (startsWithApiPrefix) return helperUri;

    return helperUri.replace(
      pathSegments: <String>[...apiSegments, ...helperSegments],
    );
  }

  bool _segmentsMatch({
    required Iterable<String> left,
    required List<String> right,
  }) {
    final leftList = left.toList(growable: false);
    if (leftList.length != right.length) return false;
    for (var i = 0; i < right.length; i++) {
      if (leftList[i].toLowerCase() != right[i].toLowerCase()) {
        return false;
      }
    }
    return true;
  }

  String _effectiveStandaloneRedirectUri(AppConfig config) {
    if (kIsWeb && config.authMode == AuthMode.telegramWeb) {
      final current = Uri.base;
      if (current.path == AppRoutes.auth) {
        return _withoutFragment(current);
      }
      return Uri(
        path: AppRoutes.auth,
        queryParameters: current.queryParameters,
      ).toString();
    }
    return config.standaloneRedirectUri.trim();
  }

  String _withoutFragment(Uri uri) {
    final raw = uri.toString();
    final hashIndex = raw.indexOf('#');
    if (hashIndex < 0) {
      return raw;
    }
    return raw.substring(0, hashIndex);
  }

  void _scheduleStandaloneHelperAutoLaunch({
    required AuthState state,
    required AppConfig config,
    required Uri? standaloneHelperUri,
  }) {
    if (_standaloneHelperLaunchAttempted) return;
    if (kIsWeb) return;
    if (config.authMode != AuthMode.standalone) return;
    if (standaloneHelperUri == null) return;
    if (state.status != AuthStatus.unauthenticated) return;

    _standaloneHelperLaunchAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await launchUrl(standaloneHelperUri,
          mode: LaunchMode.externalApplication);
    });
  }
}
