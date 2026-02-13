import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/providers.dart';
import '../../../core/widgets/premium_loading_view.dart';
import '../../../integrations/telegram/telegram_web_app_bridge.dart';
import '../application/auth_controller.dart';
import '../application/auth_state.dart';

// TODO(ui-migration): migrate auth layout/actions fully to AppScaffold/AppButton/AppTextField tokens.
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
    _scheduleStandaloneHelperAutoLaunch(
      state: state,
      config: config,
      standaloneHelperUri: standaloneHelperUri,
    );

    if (config.authMode == AuthMode.telegramWeb) {
      return _buildTelegramWebScreen(
        state: state,
        standaloneHelperUri: standaloneHelperUri,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('SPACE Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text(
                  'SPACE',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  _subtitleForMode(config.authMode),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                if (state.status == AuthStatus.loading) ...[
                  const SizedBox(
                    height: 220,
                    child: PremiumLoadingView(
                      compact: true,
                      text: 'SIGN IN • SPACE • ',
                      subtitle: 'Signing in...',
                    ),
                  ),
                ] else ...[
                  if ((state.error ?? '').trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        state.error!,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer),
                      ),
                    ),
                  FilledButton(
                    onPressed: () =>
                        ref.read(authControllerProvider).retryAuth(),
                    child: Text(
                      config.authMode == AuthMode.telegramWeb
                          ? 'Retry Telegram Login'
                          : 'Retry from URL initData',
                    ),
                  ),
                  if (config.authMode == AuthMode.standalone) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _initDataController,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Telegram initData',
                        hintText:
                            'Paste initData here if auth helper returns it',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                      onPressed: () {
                        final initData = _initDataController.text.trim();
                        if (initData.isEmpty) return;
                        ref
                            .read(authControllerProvider)
                            .loginWithTelegram(initData);
                      },
                      child: const Text('Login with initData'),
                    ),
                    if (standaloneHelperUri != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () async {
                          await launchUrl(standaloneHelperUri,
                              mode: LaunchMode.externalApplication);
                        },
                        child: const Text('Open standalone auth helper'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'Mode B flow: open auth helper -> receive deep link with initData -> login against /auth/telegram. Backend contract is unchanged.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTelegramWebScreen({
    required AuthState state,
    required Uri? standaloneHelperUri,
  }) {
    final error = (state.error ?? '').trim();
    final canUseStandaloneHelper =
        !TelegramWebAppBridge.isAvailable() && standaloneHelperUri != null;

    return Scaffold(
      backgroundColor: kIsWeb ? Colors.black : Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    height: 240,
                    child: Center(
                      child: Text(
                        'SPACE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  if (state.status != AuthStatus.loading &&
                      error.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () =>
                          ref.read(authControllerProvider).retryAuth(),
                      child: const Text('Retry Telegram Login'),
                    ),
                    if (canUseStandaloneHelper) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () async {
                          await launchUrl(
                            standaloneHelperUri,
                            mode: LaunchMode.platformDefault,
                            webOnlyWindowName: '_self',
                          );
                        },
                        child: const Text('Login via Telegram'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
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

  Uri? _standaloneHelperUri(AppConfig config) {
    final rawUrl = config.standaloneAuthUrl.trim();
    if (rawUrl.isEmpty) return null;
    final base = Uri.tryParse(rawUrl);
    if (base == null) return null;

    final redirectUri = config.standaloneRedirectUri.trim();
    if (redirectUri.isEmpty) return base;

    final query = <String, String>{
      ...base.queryParameters,
      'redirect_uri': redirectUri,
    };
    return base.replace(queryParameters: query);
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
