import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/providers.dart';
import '../application/auth_controller.dart';
import '../application/auth_state.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final TextEditingController _initDataController = TextEditingController();
  WebViewController? _standaloneWebViewController;
  Uri? _standaloneWebViewUri;
  bool _standaloneWebViewLoading = false;
  bool _standaloneLoginInProgress = false;

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
    _ensureStandaloneWebViewController(
      config: config,
      standaloneHelperUri: standaloneHelperUri,
    );
    final canUseStandaloneInApp = !kIsWeb &&
        config.authMode == AuthMode.standalone &&
        standaloneHelperUri != null;

    return Scaffold(
      appBar: AppBar(title: const Text('GigMe Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text(
                  'GigMe',
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
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  const Text('Signing in...', textAlign: TextAlign.center),
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
                  if (canUseStandaloneInApp) ...[
                    const Text(
                      'Continue with Telegram inside the app. No browser switch is required.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 460,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_standaloneWebViewController != null)
                              WebViewWidget(
                                controller: _standaloneWebViewController!,
                              )
                            else
                              const ColoredBox(
                                color: Colors.white,
                                child:
                                    Center(child: CircularProgressIndicator()),
                              ),
                            if (_standaloneWebViewLoading ||
                                _standaloneLoginInProgress)
                              ColoredBox(
                                color: Colors.black.withValues(alpha: 0.12),
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: _standaloneLoginInProgress
                          ? null
                          : _reloadStandaloneWebView,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reload Telegram login'),
                    ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      title: const Text('Manual initData fallback'),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      children: [
                        TextField(
                          controller: _initDataController,
                          minLines: 3,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'Telegram initData',
                            hintText:
                                'Paste initData here if Telegram callback is blocked',
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: _standaloneLoginInProgress
                              ? null
                              : () => _submitManualInitData(),
                          child: const Text('Login with initData'),
                        ),
                      ],
                    ),
                  ] else ...[
                    FilledButton(
                      onPressed: () =>
                          ref.read(authControllerProvider).retryAuth(),
                      child: Text(
                        config.authMode == AuthMode.telegramWeb
                            ? 'Retry Telegram Login'
                            : 'Retry from URL initData',
                      ),
                    ),
                  ],
                  if (config.authMode == AuthMode.standalone &&
                      !canUseStandaloneInApp) ...[
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
                        _submitManualInitData();
                      },
                      child: const Text('Login with initData'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Mode B flow: Telegram auth helper returns initData and app signs in via /auth/telegram.',
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

  String _subtitleForMode(AuthMode mode) {
    switch (mode) {
      case AuthMode.telegramWeb:
        return 'Mode A: Telegram Web auth via initData';
      case AuthMode.standalone:
        return 'Mode B: Telegram login inside app + automatic initData exchange';
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

  void _ensureStandaloneWebViewController({
    required AppConfig config,
    required Uri? standaloneHelperUri,
  }) {
    if (kIsWeb || config.authMode != AuthMode.standalone) return;
    if (standaloneHelperUri == null) return;

    if (_standaloneWebViewController != null &&
        _standaloneWebViewUri?.toString() == standaloneHelperUri.toString()) {
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() => _standaloneWebViewLoading = true);
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _standaloneWebViewLoading = false);
          },
          onWebResourceError: (_) {
            if (!mounted) return;
            setState(() => _standaloneWebViewLoading = false);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.navigate;

            final initData = _extractInitData(uri);
            if (initData == null || initData.isEmpty) {
              return NavigationDecision.navigate;
            }
            if (!_matchesRedirectUri(
              uri: uri,
              configuredRedirectUri: config.standaloneRedirectUri,
            )) {
              return NavigationDecision.navigate;
            }

            _initDataController.text = initData;
            unawaited(_loginWithInitData(initData));
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(standaloneHelperUri);

    _standaloneWebViewController = controller;
    _standaloneWebViewUri = standaloneHelperUri;
    _standaloneWebViewLoading = true;
  }

  bool _matchesRedirectUri({
    required Uri uri,
    required String configuredRedirectUri,
  }) {
    final configured = Uri.tryParse(configuredRedirectUri.trim());
    if (configured == null || configured.scheme.isEmpty) {
      return uri.scheme.isNotEmpty &&
          uri.scheme != 'http' &&
          uri.scheme != 'https';
    }

    if (uri.scheme != configured.scheme) return false;
    if (configured.host.isNotEmpty && uri.host != configured.host) return false;

    final configuredPath = configured.path.trim();
    if (configuredPath.isNotEmpty &&
        configuredPath != '/' &&
        uri.path != configuredPath) {
      return false;
    }

    return true;
  }

  String? _extractInitData(Uri uri) {
    final fromQuery =
        uri.queryParameters['initData'] ?? uri.queryParameters['tgWebAppData'];
    if ((fromQuery ?? '').trim().isNotEmpty) {
      return fromQuery!.trim();
    }

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
        if ((fromHash ?? '').trim().isNotEmpty) {
          return fromHash!.trim();
        }
      } catch (_) {
        // Ignore invalid query fragments.
      }
    }

    return null;
  }

  Future<void> _reloadStandaloneWebView() async {
    final controller = _standaloneWebViewController;
    final uri = _standaloneWebViewUri;
    if (controller == null || uri == null) return;

    if (mounted) {
      setState(() => _standaloneWebViewLoading = true);
    }
    await controller.loadRequest(uri);
  }

  Future<void> _submitManualInitData() async {
    final initData = _initDataController.text.trim();
    if (initData.isEmpty) return;
    await _loginWithInitData(initData);
  }

  Future<void> _loginWithInitData(String initData) async {
    if (_standaloneLoginInProgress) return;
    if (mounted) {
      setState(() => _standaloneLoginInProgress = true);
    }
    try {
      await ref.read(authControllerProvider).loginWithTelegram(initData);
    } finally {
      if (mounted) {
        setState(() => _standaloneLoginInProgress = false);
      }
    }
  }
}
