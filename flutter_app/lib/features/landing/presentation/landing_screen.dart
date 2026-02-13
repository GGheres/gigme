import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../app/routes.dart';
import '../../../core/models/landing_content.dart';
import '../../../core/models/landing_event.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../core/utils/event_media_url_utils.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_button.dart';
import '../../../ui/components/app_modal.dart';
import '../../../ui/components/app_section_header.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../../integrations/telegram/telegram_web_app_bridge.dart';
import '../data/landing_repository.dart';

class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({super.key});

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController =
      ScrollController(keepScrollOffset: false);
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0);
  late final AnimationController _matrixPulseController;
  bool _didForceInitialTop = false;

  bool _loading = false;
  String? _error;
  List<LandingEvent> _events = <LandingEvent>[];
  int _total = 0;
  LandingContent _content = LandingContent.defaults();

  @override
  void initState() {
    super.initState();
    _matrixPulseController = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (LandingLayoutConfig.effectsTimelineSec * 1000).round(),
      ),
    )..repeat();
    if (kIsWeb) {
      TelegramWebAppBridge.readyAndExpand();
    }
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _forceScrollTop();
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollOffset.dispose();
    _matrixPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = LandingLayoutConfig.shouldReduceMotion(context);
    final apiUrl = ref.watch(appConfigProvider).apiUrl;

    return AppScaffold(
      fullBleed: true,
      safeArea: false,
      showBackgroundDecor: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final canvasHeight =
              LandingLayoutConfig.canvasHeight(viewport: viewport);
          final quietZoneWidth =
              LandingLayoutConfig.quietZoneWidth(viewport.width);
          final quietZoneLeft = LandingLayoutConfig.quietZoneLeft(
            screenWidth: viewport.width,
            quietZoneWidth: quietZoneWidth,
          );

          return RefreshIndicator(
            onRefresh: _load,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: _scrollPhysicsForContext(context),
              child: SizedBox(
                height: canvasHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    BreathingTextFrame(
                      text: LandingLayoutConfig.frameTickerText,
                      timeline: _matrixPulseController,
                      reduceMotion: reduceMotion,
                      enableShimmer: false,
                      enableGrain: false,
                      child: _LandingParallaxCanvas(
                        scrollOffset: _scrollOffset,
                        canvasHeight: canvasHeight,
                        viewport: viewport,
                        quietZoneLeft: quietZoneLeft,
                        quietZoneWidth: quietZoneWidth,
                        reduceMotion: reduceMotion,
                      ),
                    ),
                    _LandingForeground(
                      viewport: viewport,
                      canvasHeight: canvasHeight,
                      quietZoneLeft: quietZoneLeft,
                      quietZoneWidth: quietZoneWidth,
                      apiUrl: apiUrl,
                      loading: _loading,
                      error: _error,
                      events: _events,
                      content: _content,
                      total: _total,
                      onOpenApp: () => unawaited(_openApp()),
                      onBuy: (event) => unawaited(_openTicket(event)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final next = _scrollController.offset;
    if ((_scrollOffset.value - next).abs() < 0.5) return;
    _scrollOffset.value = next;
  }

  ScrollPhysics _scrollPhysicsForContext(BuildContext context) {
    final isTelegramWeb = kIsWeb && TelegramWebAppBridge.isAvailable();
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    if (isTelegramWeb && isIOS) {
      return const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(parent: ClampingScrollPhysics()),
      );
    }
    return const AlwaysScrollableScrollPhysics(
      parent: ClampingScrollPhysics(),
    );
  }

  void _forceScrollTop() {
    if (!mounted) return;
    if (_didForceInitialTop) return;
    _didForceInitialTop = true;

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _scrollOffset.value = 0;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repository = ref.read(landingRepositoryProvider);
      final response = await repository.listEvents(limit: 100, offset: 0);
      final content = await repository.getContent();
      if (!mounted) return;
      setState(() {
        _events = response.items;
        _total = response.total;
        _content = content;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openTicket(LandingEvent event) async {
    final nextLocation = AppRoutes.event(event.id);
    final authState = await _resolveAuthStateForAction();
    if (!mounted) return;
    if (authState.status == AuthStatus.loading) {
      _showMessage('Проверяем сессию. Попробуйте еще раз через секунду.');
      return;
    }
    if (_shouldPromptTelegramLogin(authState)) {
      await _showTelegramLoginModal(nextLocation: nextLocation);
      return;
    }
    context.push(nextLocation);
  }

  Future<void> _openApp() async {
    final authState = await _resolveAuthStateForAction();
    if (!mounted) return;
    if (authState.status == AuthStatus.loading) {
      _showMessage('Проверяем сессию. Попробуйте еще раз через секунду.');
      return;
    }
    if (_shouldPromptTelegramLogin(authState)) {
      await _showTelegramLoginModal(nextLocation: AppRoutes.appRoot);
      return;
    }
    context.go(AppRoutes.appRoot);
  }

  bool _shouldPromptTelegramLogin(AuthState authState) {
    if (!kIsWeb) return false;
    return authState.status == AuthStatus.unauthenticated;
  }

  Future<AuthState> _resolveAuthStateForAction() async {
    final controller = ref.read(authControllerProvider);
    final current = controller.state;
    if (current.status != AuthStatus.loading) {
      return current;
    }

    final completer = Completer<AuthState>();
    void listener() {
      final next = controller.state;
      if (next.status == AuthStatus.loading) return;
      if (!completer.isCompleted) {
        completer.complete(next);
      }
    }

    controller.addListener(listener);
    try {
      return await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => controller.state,
      );
    } finally {
      controller.removeListener(listener);
    }
  }

  Future<void> _showTelegramLoginModal({
    required String nextLocation,
  }) async {
    final loginUri = _telegramLoginUri(nextLocation: nextLocation);
    if (loginUri == null) {
      _showMessage(
          'Telegram login недоступен. Проверьте настройки BOT_USERNAME/STANDALONE_AUTH_URL.');
      return;
    }

    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AppModal(
          title: 'Login via Telegram',
          subtitle:
              'Чтобы продолжить, войдите через Telegram. После входа вы вернетесь в приложение.',
          onClose: () => Navigator.of(dialogContext).pop(),
          body: Text(
            'Нажмите кнопку ниже, завершите вход и вы вернетесь в SPACE уже авторизованным пользователем.',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
          actions: [
            AppButton(
              label: 'Login via Telegram',
              variant: AppButtonVariant.primary,
              icon: const Icon(Icons.telegram_rounded),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(_openTelegramLogin(loginUri));
              },
            ),
            AppButton(
              label: 'Отмена',
              variant: AppButtonVariant.ghost,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  Uri? _telegramLoginUri({
    required String nextLocation,
  }) {
    final config = ref.read(appConfigProvider);
    final helperUrl = config.standaloneAuthUrl.trim();
    final helperBase = Uri.tryParse(helperUrl);
    if (helperBase != null && helperUrl.isNotEmpty) {
      final redirect = Uri.base.replace(
        path: AppRoutes.auth,
        queryParameters: {'next': nextLocation},
        fragment: '',
      );
      return helperBase.replace(
        queryParameters: {
          ...helperBase.queryParameters,
          'redirect_uri': redirect.toString(),
        },
      );
    }

    final bot = config.botUsername.trim().replaceAll('@', '');
    if (bot.isEmpty) return null;
    final startApp = _startAppFromNext(nextLocation);
    if (startApp == null) {
      return Uri.parse('https://t.me/$bot');
    }
    return Uri.parse(
      'https://t.me/$bot?startapp=${Uri.encodeComponent(startApp)}',
    );
  }

  String? _startAppFromNext(String nextLocation) {
    final uri = Uri.tryParse(nextLocation);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    if (segments.length < 3) return null;
    if (segments[0] != 'space_app' || segments[1] != 'event') return null;
    final eventId = int.tryParse(segments[2]);
    if (eventId == null || eventId <= 0) return null;
    return 'e_$eventId';
  }

  Future<void> _openTelegramLogin(Uri uri) async {
    if (kIsWeb) {
      TelegramWebAppBridge.redirect(uri.toString());
      return;
    }
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
    );
    if (!opened) {
      _showMessage('Could not open Telegram login');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class LandingLayoutConfig {
  const LandingLayoutConfig._();

  static const double desktopBreakpoint = 1100;
  static const double tabletBreakpoint = 720;

  static const Map<String, double> parallaxFactors = <String, double>{
    'farStars': 0.10,
    'auroraMidLayer': 0.18,
    'nearDecor': 0.26,
  };
  static const Map<String, double> reducedParallaxFactors = <String, double>{
    'farStars': 0.03,
    'auroraMidLayer': 0.06,
    'nearDecor': 0.08,
  };

  static const Map<String, double> quietZoneWidthRules = <String, double>{
    'desktopFactor': 0.46,
    'desktopMax': 720,
    'tabletFactor': 0.90,
    'mobileFactor': 0.92,
  };

  static const double overlayOpacity = 0.46;

  static const Map<String, double> sectionAnchorOffsets = <String, double>{
    'hero': 0.05,
    'about': 0.38,
    'partners': 0.69,
  };

  static const double desktopCanvasScreens = 3;
  static const double tabletCanvasScreens = 3;
  static const double mobileCanvasScreens = 3;
  static const double glassBlurSigma = 14;
  static const double parallaxOverflowViewportFactor = 0.72;
  static const double effectsTimelineSec = 120;
  static const double globalBreathPeriodSec = 4.8;
  static const double tickerSpeedPxPerSec = 32;
  static const double shimmerSpeedPxPerSec = 44;
  static const double waveSpeed = 96;
  static const double waveSigma = 150;
  static const double waveGlowBoost = 0.68;
  static const double waveOpacityBoost = 0.18;
  static const double grainOpacity = 0.05;
  static const double grainFps = 6;
  static const bool forceReduceMotion = false;
  static const String frameTickerText =
      'SPACE • EVENT • 31–3 AUG • SPACE • EVENT • ';
  static const String backgroundVideoAssetPath =
      'assets/videos/landing/IMG_9645.MP4';

  static bool isDesktop(double width) => width >= desktopBreakpoint;
  static bool isTablet(double width) =>
      width >= tabletBreakpoint && width < desktopBreakpoint;

  static bool shouldReduceMotion(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final userPrefersReduced = (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    return forceReduceMotion || userPrefersReduced;
  }

  static double parallaxFactor({
    required String layer,
    required bool reduceMotion,
  }) {
    final source = reduceMotion ? reducedParallaxFactors : parallaxFactors;
    return source[layer] ?? 0;
  }

  static double canvasHeight({
    required Size viewport,
  }) {
    if (isDesktop(viewport.width)) {
      return viewport.height * desktopCanvasScreens;
    }
    if (isTablet(viewport.width)) {
      return viewport.height * tabletCanvasScreens;
    }
    return viewport.height * mobileCanvasScreens;
  }

  static double quietZoneWidth(double screenWidth) {
    if (isDesktop(screenWidth)) {
      return math.min(
        quietZoneWidthRules['desktopMax']!,
        screenWidth * quietZoneWidthRules['desktopFactor']!,
      );
    }
    if (isTablet(screenWidth)) {
      return screenWidth * quietZoneWidthRules['tabletFactor']!;
    }
    return screenWidth * quietZoneWidthRules['mobileFactor']!;
  }

  static double quietZoneLeft({
    required double screenWidth,
    required double quietZoneWidth,
  }) {
    final centered = (screenWidth - quietZoneWidth) / 2;
    if (!isDesktop(screenWidth)) {
      return centered.clamp(12.0, screenWidth - quietZoneWidth - 12.0);
    }
    final shifted = centered - (screenWidth * 0.035);
    return shifted.clamp(16.0, screenWidth - quietZoneWidth - 16.0);
  }

  static double sectionTop({
    required double canvasHeight,
    required double viewportHeight,
    required double anchor,
  }) {
    return (canvasHeight * anchor) + (viewportHeight * 0.02);
  }
}

class _LandingForeground extends StatelessWidget {
  const _LandingForeground({
    required this.viewport,
    required this.canvasHeight,
    required this.quietZoneLeft,
    required this.quietZoneWidth,
    required this.apiUrl,
    required this.loading,
    required this.error,
    required this.events,
    required this.content,
    required this.total,
    required this.onOpenApp,
    required this.onBuy,
  });

  final Size viewport;
  final double canvasHeight;
  final double quietZoneLeft;
  final double quietZoneWidth;
  final String apiUrl;
  final bool loading;
  final String? error;
  final List<LandingEvent> events;
  final LandingContent content;
  final int total;
  final VoidCallback onOpenApp;
  final ValueChanged<LandingEvent> onBuy;

  @override
  Widget build(BuildContext context) {
    final featuredEvent = events.isNotEmpty ? events.first : null;
    final heroPrimaryLabel = content.heroPrimaryCtaLabel.trim().toLowerCase();
    final heroCtaIsTicket = heroPrimaryLabel.contains('билет');
    final totalParticipants = _totalParticipants(events);

    final mediaPadding = MediaQuery.of(context).padding;
    final heroTop = LandingLayoutConfig.sectionTop(
      canvasHeight: canvasHeight,
      viewportHeight: viewport.height,
      anchor: LandingLayoutConfig.sectionAnchorOffsets['hero']!,
    );
    final aboutTop = LandingLayoutConfig.sectionTop(
      canvasHeight: canvasHeight,
      viewportHeight: viewport.height,
      anchor: LandingLayoutConfig.sectionAnchorOffsets['about']!,
    );

    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: heroTop + mediaPadding.top,
            left: quietZoneLeft,
            width: quietZoneWidth,
            child: RepaintBoundary(
              child: _HeroSection(
                featuredEvent: featuredEvent,
                apiUrl: apiUrl,
                total: total,
                loading: loading,
                error: error,
                totalParticipants: totalParticipants,
                content: content,
                onPrimaryAction: featuredEvent != null && heroCtaIsTicket
                    ? () => onBuy(featuredEvent)
                    : onOpenApp,
                onOpenApp: onOpenApp,
              ),
            ),
          ),
          Positioned(
            top: aboutTop + mediaPadding.top,
            left: quietZoneLeft,
            width: quietZoneWidth,
            child: RepaintBoundary(
              child: _AboutSection(
                events: events,
                content: content,
                total: total,
                totalParticipants: totalParticipants,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.featuredEvent,
    required this.apiUrl,
    required this.content,
    required this.total,
    required this.loading,
    required this.error,
    required this.totalParticipants,
    required this.onPrimaryAction,
    required this.onOpenApp,
  });

  final LandingEvent? featuredEvent;
  final String apiUrl;
  final LandingContent content;
  final int total;
  final bool loading;
  final String? error;
  final int totalParticipants;
  final VoidCallback onPrimaryAction;
  final VoidCallback onOpenApp;

  @override
  Widget build(BuildContext context) {
    final title = content.heroTitle.trim();
    final description = content.heroDescription.trim();
    final meta = _eventMeta(featuredEvent);

    return _GlassPanel(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroPoster(event: featuredEvent, apiUrl: apiUrl),
          const SizedBox(height: AppSpacing.md),
          AppBadge(
            label: content.heroEyebrow.trim(),
            variant: AppBadgeVariant.info,
            textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  letterSpacing: 1.4,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppSectionHeader(
            title: title,
            subtitle: meta,
            titleColor: Colors.white,
            subtitleColor: Colors.white.withValues(alpha: 0.82),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            description,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          _HeroActions(
            total: total,
            totalParticipants: totalParticipants,
            openAppLabel: content.heroPrimaryCtaLabel.trim(),
            onPrimaryAction: onPrimaryAction,
            onOpenApp: onOpenApp,
          ),
          if (loading) ...[
            const SizedBox(height: AppSpacing.sm),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if ((error ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.danger.withValues(alpha: 0.55)),
              ),
              child: Text(
                error!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions({
    required this.total,
    required this.totalParticipants,
    required this.openAppLabel,
    required this.onPrimaryAction,
    required this.onOpenApp,
  });

  final int total;
  final int totalParticipants;
  final String openAppLabel;
  final VoidCallback onPrimaryAction;
  final VoidCallback onOpenApp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            AppButton(
              label: openAppLabel,
              variant: AppButtonVariant.secondary,
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: onPrimaryAction,
            ),
            AppButton(
              label: 'SPACE APP',
              variant: AppButtonVariant.primary,
              icon: const Icon(Icons.rocket_launch_rounded),
              onPressed: onOpenApp,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            AppBadge(label: '$total Событий', variant: AppBadgeVariant.neutral),
            AppBadge(
              label: '$totalParticipants Участников',
              variant: AppBadgeVariant.neutral,
            ),
            const AppBadge(
              label: 'Формат: Live + Digital',
              variant: AppBadgeVariant.ghost,
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroPoster extends StatelessWidget {
  const _HeroPoster({required this.event, required this.apiUrl});

  final LandingEvent? event;
  final String apiUrl;

  @override
  Widget build(BuildContext context) {
    final fallbackImage = (event?.thumbnailUrl ?? '').trim();
    final proxyImage = buildEventMediaProxyUrl(
      apiUrl: apiUrl,
      eventId: event?.id ?? 0,
      index: 0,
    );
    final imageUrl = proxyImage.isNotEmpty ? proxyImage : fallbackImage;
    final fallbackUrl = proxyImage.isNotEmpty ? fallbackImage : '';
    final hasImage = imageUrl.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.info.withValues(alpha: 0.78),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.info.withValues(alpha: 0.42),
            blurRadius: 28,
            spreadRadius: 1.4,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.16),
            blurRadius: 10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, __) {
                    if (fallbackUrl.isNotEmpty && fallbackUrl != imageUrl) {
                      return Image.network(
                        fallbackUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, _, __) =>
                            const _PosterFallback(),
                      );
                    }
                    return const _PosterFallback();
                  },
                )
              else
                const _PosterFallback(),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: <Color>[Color(0xB3040A17), Color(0x00040A17)],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Text(
                  (event?.addressLabel ?? '').trim().isEmpty
                      ? 'Главная сцена'
                      : event!.addressLabel.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF21305D),
            Color(0xFF0D6A7A),
            Color(0xFF1A1F3F)
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 48),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({
    required this.events,
    required this.content,
    required this.total,
    required this.totalParticipants,
  });

  final List<LandingEvent> events;
  final LandingContent content;
  final int total;
  final int totalParticipants;

  @override
  Widget build(BuildContext context) {
    final description = content.aboutDescription.trim();
    final earliest = _earliestDate(events);
    final uniqueLocations = _uniqueLocations(events);

    return _GlassPanel(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: content.aboutTitle.trim(),
            subtitle: description,
            titleColor: Colors.white,
            subtitleColor: Colors.white.withValues(alpha: 0.85),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _HighlightTile(
                icon: Icons.event_available_rounded,
                title: '$total',
                subtitle: 'Опубликованных событий',
              ),
              _HighlightTile(
                icon: Icons.group_rounded,
                title: '$totalParticipants',
                subtitle: 'Подтвержденных участников',
              ),
              _HighlightTile(
                icon: Icons.location_on_outlined,
                title: '$uniqueLocations',
                subtitle: 'Локаций в программе',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
              color: AppColors.backgroundDeep.withValues(alpha: 0.32),
            ),
            child: Text(
              earliest == null
                  ? 'Расписание скоро появится'
                  : 'Ближайший старт: ${formatDateTime(earliest)}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.info.withValues(alpha: 0.30)),
          color: AppColors.backgroundDeep.withValues(alpha: 0.32),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.info.withValues(alpha: 0.9)),
              const SizedBox(height: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.86)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LandingParallaxCanvas extends StatelessWidget {
  const _LandingParallaxCanvas({
    required this.scrollOffset,
    required this.canvasHeight,
    required this.viewport,
    required this.quietZoneLeft,
    required this.quietZoneWidth,
    required this.reduceMotion,
  });

  final ValueListenable<double> scrollOffset;
  final double canvasHeight;
  final Size viewport;
  final double quietZoneLeft;
  final double quietZoneWidth;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final overflow =
        viewport.height * LandingLayoutConfig.parallaxOverflowViewportFactor;

    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: _LandingVideoBackground(),
          ),
        ),
        _ParallaxLayer(
          scrollOffset: scrollOffset,
          factor: LandingLayoutConfig.parallaxFactor(
            layer: 'auroraMidLayer',
            reduceMotion: reduceMotion,
          ),
          overflow: overflow,
          child: const CustomPaint(painter: _AuroraPainter()),
        ),
        _ParallaxLayer(
          scrollOffset: scrollOffset,
          factor: LandingLayoutConfig.parallaxFactor(
            layer: 'nearDecor',
            reduceMotion: reduceMotion,
          ),
          overflow: overflow,
          child: const CustomPaint(painter: _NearDecorPainter()),
        ),
        const Positioned.fill(
          child: IgnorePointer(child: _EdgeVignette()),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: quietZoneLeft - 56,
          width: quietZoneWidth + 112,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    Color(0x00030A18),
                    Color(0x29030A18),
                    Color(0x33030A18),
                    Color(0x29030A18),
                    Color(0x00030A18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LandingVideoBackground extends StatefulWidget {
  const _LandingVideoBackground();

  @override
  State<_LandingVideoBackground> createState() =>
      _LandingVideoBackgroundState();
}

class _LandingVideoBackgroundState extends State<_LandingVideoBackground> {
  VideoPlayerController? _controller;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeVideo());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    final controller = VideoPlayerController.asset(
      LandingLayoutConfig.backgroundVideoAssetPath,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
    } catch (error) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _initError = error);
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _initError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _initError != null) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF060B1D),
              Color(0xFF040814),
              Color(0xFF050A16),
            ],
            stops: <double>[0, 0.45, 1],
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class BreathingTextFrame extends StatelessWidget {
  // Example:
  // BreathingTextFrame(
  //   text: "SPACE • EVENT • 31–3 AUG • SPACE • EVENT • ",
  //   enableShimmer: true,
  //   enableGrain: true,
  //   timeline: controller,
  //   reduceMotion: false,
  //   child: HeroSection(...),
  // )
  const BreathingTextFrame({
    required this.text,
    required this.timeline,
    required this.reduceMotion,
    required this.enableShimmer,
    required this.enableGrain,
    required this.child,
    super.key,
  });

  final String text;
  final Animation<double> timeline;
  final bool reduceMotion;
  final bool enableShimmer;
  final bool enableGrain;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: child),
        if (enableGrain)
          const Positioned.fill(
            child: IgnorePointer(
              child: _AnimatedGrainOverlay(
                opacity: LandingLayoutConfig.grainOpacity,
                fps: LandingLayoutConfig.grainFps,
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: timeline,
              builder: (context, _) {
                final timeSec =
                    timeline.value * LandingLayoutConfig.effectsTimelineSec;
                return RepaintBoundary(
                  child: CustomPaint(
                    painter: _BreathingFramePainter(
                      text: text,
                      timeSec: timeSec,
                      enableShimmer: enableShimmer,
                      reduceMotion: reduceMotion,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedGrainOverlay extends StatefulWidget {
  const _AnimatedGrainOverlay({
    required this.opacity,
    required this.fps,
  });

  final double opacity;
  final double fps;

  @override
  State<_AnimatedGrainOverlay> createState() => _AnimatedGrainOverlayState();
}

class _AnimatedGrainOverlayState extends State<_AnimatedGrainOverlay> {
  final List<ui.Image> _frames = <ui.Image>[];
  Timer? _timer;
  int _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareFrames());
  }

  @override
  void didUpdateWidget(covariant _AnimatedGrainOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fps != widget.fps && _frames.isNotEmpty) {
      _startTicker();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _prepareFrames() async {
    // Keep grain cheap: pre-generate small frames once and just cycle them.
    const frameCount = 8;
    const frameSize = 256;
    final generated = <ui.Image>[];

    for (var i = 0; i < frameCount; i++) {
      final image = await _generateNoiseImage(
        frameSize: frameSize,
        seed: 7919 + (i * 271),
      );
      generated.add(image);
    }

    if (!mounted) return;
    setState(() {
      _frames
        ..clear()
        ..addAll(generated);
      _frameIndex = 0;
    });
    _startTicker();
  }

  Future<ui.Image> _generateNoiseImage({
    required int frameSize,
    required int seed,
  }) {
    final rnd = math.Random(seed);
    final pixelCount = frameSize * frameSize;
    final bytes = Uint8List(pixelCount * 4);

    for (var i = 0; i < pixelCount; i++) {
      final value = 106 + rnd.nextInt(128);
      final idx = i * 4;
      bytes[idx] = value;
      bytes[idx + 1] = value;
      bytes[idx + 2] = value;
      bytes[idx + 3] = 255;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      frameSize,
      frameSize,
      ui.PixelFormat.rgba8888,
      completer.complete,
      rowBytes: frameSize * 4,
    );
    return completer.future;
  }

  void _startTicker() {
    _timer?.cancel();
    final fps = widget.fps.clamp(1.0, 12.0);
    final interval = Duration(milliseconds: (1000 / fps).round());
    _timer = Timer.periodic(interval, (_) {
      if (!mounted || _frames.isEmpty) return;
      setState(() {
        _frameIndex = (_frameIndex + 1) % _frames.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_frames.isEmpty) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: _GrainOverlayPainter(
          image: _frames[_frameIndex],
          opacity: widget.opacity,
          frameIndex: _frameIndex,
        ),
      ),
    );
  }
}

class _GrainOverlayPainter extends CustomPainter {
  const _GrainOverlayPainter({
    required this.image,
    required this.opacity,
    required this.frameIndex,
  });

  final ui.Image image;
  final double opacity;
  final int frameIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    final scale = math.max(size.width / imageWidth, size.height / imageHeight);
    final drawWidth = imageWidth * scale * 1.06;
    final drawHeight = imageHeight * scale * 1.06;
    final driftX = math.sin(frameIndex * 0.9) * 6;
    final driftY = math.cos(frameIndex * 0.7) * 6;

    final dst = Rect.fromLTWH(
      ((size.width - drawWidth) / 2) + driftX,
      ((size.height - drawHeight) / 2) + driftY,
      drawWidth,
      drawHeight,
    );
    final src = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    final paint = Paint()
      ..blendMode = BlendMode.softLight
      ..filterQuality = FilterQuality.low
      ..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 0.12));
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant _GrainOverlayPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.opacity != opacity ||
        oldDelegate.frameIndex != frameIndex;
  }
}

class _ParallaxLayer extends StatelessWidget {
  const _ParallaxLayer({
    required this.scrollOffset,
    required this.factor,
    required this.overflow,
    required this.child,
  });

  final ValueListenable<double> scrollOffset;
  final double factor;
  final double overflow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: -overflow,
      bottom: -overflow,
      child: ValueListenableBuilder<double>(
        valueListenable: scrollOffset,
        builder: (context, value, staticChild) {
          final dy = _clampedParallaxOffset(
            scrollOffset: value,
            factor: factor,
            overflow: overflow,
          );
          return Transform.translate(
            offset: Offset(0, dy),
            child: staticChild,
          );
        },
        child: RepaintBoundary(child: child),
      ),
    );
  }
}

class _EdgeVignette extends StatelessWidget {
  const _EdgeVignette();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Color(0x8A010611),
                  Color(0x41010611),
                  Color(0x00010611),
                  Color(0x41010611),
                  Color(0x8A010611),
                ],
                stops: <double>[0, 0.16, 0.5, 0.84, 1],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x5A010611),
                  Color(0x00010611),
                  Color(0x00010611),
                  Color(0x77010611),
                ],
                stops: <double>[0, 0.2, 0.74, 1],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final blend = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0x4010CFFF),
          Color(0x2614CFA2),
          Color(0x2F4277FF),
          Color(0x00000000),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, blend);

    _orb(
      canvas: canvas,
      center: Offset(size.width * 0.12, size.height * 0.18),
      radius: size.width * 0.34,
      color: const Color(0x2E20E2FF),
    );
    _orb(
      canvas: canvas,
      center: Offset(size.width * 0.9, size.height * 0.42),
      radius: size.width * 0.38,
      color: const Color(0x3027D5B8),
    );
    _orb(
      canvas: canvas,
      center: Offset(size.width * 0.08, size.height * 0.76),
      radius: size.width * 0.28,
      color: const Color(0x222A9DFF),
    );
  }

  void _orb({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required Color color,
  }) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          color,
          color.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NearDecorPainter extends CustomPainter {
  const _NearDecorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final wave = Path()
      ..moveTo(0, size.height * 0.7)
      ..quadraticBezierTo(
        size.width * 0.18,
        size.height * 0.63,
        size.width * 0.35,
        size.height * 0.7,
      )
      ..quadraticBezierTo(
        size.width * 0.55,
        size.height * 0.78,
        size.width * 0.8,
        size.height * 0.71,
      )
      ..quadraticBezierTo(
        size.width * 0.91,
        size.height * 0.67,
        size.width,
        size.height * 0.72,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0x002A77FF),
          Color(0x2C194A94),
          Color(0x5F12203F),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(wave, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BreathingFramePainter extends CustomPainter {
  const _BreathingFramePainter({
    required this.text,
    required this.timeSec,
    required this.enableShimmer,
    required this.reduceMotion,
  });

  static const int _intensitySteps = 12;
  static final Map<String, _FramePathData> _framePathCache =
      <String, _FramePathData>{};
  static final Map<String, double> _glyphWidthCache = <String, double>{};
  static final Map<String, TextPainter> _glyphPainterCache =
      <String, TextPainter>{};

  final String text;
  final double timeSec;
  final bool enableShimmer;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final frame = _resolveFramePath(size);
    final breath = _breathValue(timeSec);

    _drawCornerAccents(
      canvas: canvas,
      frame: frame,
      breath: breath,
      timeSec: timeSec,
    );
    _drawFrameStroke(
      canvas: canvas,
      frame: frame,
      breath: breath,
    );
    if (enableShimmer && !reduceMotion) {
      _drawShimmerStroke(
        canvas: canvas,
        frame: frame,
        timeSec: timeSec,
      );
    }
    _drawTickerText(
      canvas: canvas,
      frame: frame,
      breath: breath,
    );
  }

  void _drawCornerAccents({
    required Canvas canvas,
    required _FramePathData frame,
    required double breath,
    required double timeSec,
  }) {
    final corners = <Offset>[
      frame.rect.topLeft,
      frame.rect.topRight,
      frame.rect.bottomRight,
      frame.rect.bottomLeft,
    ];
    final radius = (math.min(frame.rect.width, frame.rect.height) * 0.09)
        .clamp(24.0, 56.0);

    for (var i = 0; i < corners.length; i++) {
      final pulse =
          0.58 + (0.42 * (0.5 + (0.5 * math.sin((timeSec * 0.9) + (i * 0.8)))));
      final accentAlpha = (0.015 + (0.05 * breath * pulse)).clamp(0.0, 0.09);
      final rect = Rect.fromCircle(center: corners[i], radius: radius);
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          corners[i],
          radius,
          <Color>[
            const Color(0xFF9BFFE3).withValues(alpha: accentAlpha),
            const Color(0x00000000),
          ],
        );
      canvas.drawRect(rect, paint);
    }
  }

  void _drawFrameStroke({
    required Canvas canvas,
    required _FramePathData frame,
    required double breath,
  }) {
    final glowAlpha = (0.10 + (0.18 * breath)).clamp(0.0, 0.38);
    final lineAlpha = (0.28 + (0.26 * breath)).clamp(0.0, 0.82);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.6)
      ..color = const Color(0xFF6FDEC0).withValues(alpha: glowAlpha);
    canvas.drawPath(frame.path, glowPaint);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = const Color(0xFFC8FFEE).withValues(alpha: lineAlpha);
    canvas.drawPath(frame.path, linePaint);
  }

  void _drawShimmerStroke({
    required Canvas canvas,
    required _FramePathData frame,
    required double timeSec,
  }) {
    final shimmerProgress =
        ((timeSec * LandingLayoutConfig.shimmerSpeedPxPerSec) % frame.length) /
            frame.length;
    final shimmerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.3)
      ..shader = SweepGradient(
        transform: GradientRotation(shimmerProgress * math.pi * 2),
        colors: const <Color>[
          Color(0x001FE5A3),
          Color(0x4228E8AE),
          Color(0x9DE8FFF7),
          Color(0x4228E8AE),
          Color(0x001FE5A3),
        ],
        stops: const <double>[0.0, 0.14, 0.22, 0.30, 1.0],
      ).createShader(frame.rect);
    canvas.drawPath(frame.path, shimmerPaint);
  }

  void _drawTickerText({
    required Canvas canvas,
    required _FramePathData frame,
    required double breath,
  }) {
    final sourceText =
        text.trim().isEmpty ? LandingLayoutConfig.frameTickerText : text;
    final glyphs = sourceText.split('');
    if (glyphs.isEmpty) return;

    final fontSize = (math.min(frame.rect.width, frame.rect.height) * 0.019)
        .clamp(10.0, 14.5);
    final spacing = (fontSize * 0.34).clamp(3.0, 6.0);

    var patternLength = 0.0;
    for (final glyph in glyphs) {
      patternLength += _glyphWidth(glyph: glyph, fontSize: fontSize) + spacing;
    }
    if (patternLength <= 0) return;

    final textSpeed =
        reduceMotion ? 0.0 : LandingLayoutConfig.tickerSpeedPxPerSec;
    var cursor =
        textSpeed == 0 ? 0.0 : -((timeSec * textSpeed) % patternLength);
    if (cursor > 0) cursor -= patternLength;

    // Traveling wave and shimmer move independently from the text crawl speed.
    final waveCenter = reduceMotion
        ? 0.0
        : ((timeSec * LandingLayoutConfig.waveSpeed) % frame.length);
    final shimmerCenter = (reduceMotion || !enableShimmer)
        ? 0.0
        : ((timeSec * LandingLayoutConfig.shimmerSpeedPxPerSec) % frame.length);
    final waveSigma = LandingLayoutConfig.waveSigma.clamp(50.0, 260.0);
    final shimmerSigma = waveSigma * 0.72;

    final maxCursor = frame.length + patternLength;
    while (cursor < maxCursor) {
      for (final glyph in glyphs) {
        final glyphWidth = _glyphWidth(glyph: glyph, fontSize: fontSize);
        final glyphCenter = cursor + (glyphWidth * 0.5);
        cursor += glyphWidth + spacing;

        if (glyphCenter < 0 || glyphCenter > frame.length) {
          continue;
        }

        final tangent = frame.metric.getTangentForOffset(glyphCenter);
        if (tangent == null) {
          continue;
        }

        final wave = reduceMotion
            ? 0.0
            : _gaussianOnLoop(
                s: glyphCenter,
                center: waveCenter,
                length: frame.length,
                sigma: waveSigma,
              );
        final shimmer = (reduceMotion || !enableShimmer)
            ? 0.0
            : _gaussianOnLoop(
                s: glyphCenter,
                center: shimmerCenter,
                length: frame.length,
                sigma: shimmerSigma,
              );

        final localGlow = (0.14 +
                (0.24 * breath) +
                (wave * LandingLayoutConfig.waveGlowBoost) +
                (shimmer * 0.30))
            .clamp(0.0, 1.0);
        final localOpacity = (0.22 +
                (0.24 * breath) +
                (wave * LandingLayoutConfig.waveOpacityBoost) +
                (shimmer * 0.16))
            .clamp(0.0, 1.0);

        final glowPainter = _glyphPainter(
          glyph: glyph,
          fontSize: fontSize,
          intensityBin: (localGlow * _intensitySteps).round(),
          glowPass: true,
        );
        final textPainter = _glyphPainter(
          glyph: glyph,
          fontSize: fontSize,
          intensityBin: (localOpacity * _intensitySteps).round(),
          glowPass: false,
        );

        final yOffset = -fontSize * 0.66;
        canvas.save();
        canvas.translate(tangent.position.dx, tangent.position.dy);
        canvas.rotate(tangent.angle);
        glowPainter.paint(canvas, Offset(-(glowPainter.width / 2), yOffset));
        textPainter.paint(canvas, Offset(-(textPainter.width / 2), yOffset));
        canvas.restore();
      }
    }
  }

  _FramePathData _resolveFramePath(Size size) {
    final inset = (size.shortestSide * 0.026).clamp(14.0, 30.0);
    final radius = (size.shortestSide * 0.035).clamp(18.0, 36.0);
    final key = [
      size.width.toStringAsFixed(1),
      size.height.toStringAsFixed(1),
      inset.toStringAsFixed(1),
      radius.toStringAsFixed(1),
    ].join(':');

    final cached = _framePathCache[key];
    if (cached != null) {
      return cached;
    }

    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - (inset * 2),
      size.height - (inset * 2),
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final metric = path.computeMetrics(forceClosed: true).first;
    final out = _FramePathData(
      rect: rect,
      path: path,
      metric: metric,
      length: metric.length,
    );
    _framePathCache[key] = out;
    if (_framePathCache.length > 20) {
      _framePathCache.remove(_framePathCache.keys.first);
    }
    return out;
  }

  TextPainter _glyphPainter({
    required String glyph,
    required double fontSize,
    required int intensityBin,
    required bool glowPass,
  }) {
    final clampedBin = intensityBin.clamp(0, _intensitySteps);
    final key = [
      glyph,
      fontSize.toStringAsFixed(2),
      clampedBin,
      glowPass ? 1 : 0,
    ].join('|');
    final cached = _glyphPainterCache[key];
    if (cached != null) {
      return cached;
    }

    final intensity = clampedBin / _intensitySteps;
    final base = glowPass ? const Color(0xFF3ACF9E) : const Color(0xFF2EB282);
    final highlight =
        glowPass ? const Color(0xFFEEFFF9) : const Color(0xFFD6FFF1);
    final alpha = glowPass
        ? (0.08 + (0.70 * intensity)).clamp(0.0, 1.0)
        : (0.26 + (0.68 * intensity)).clamp(0.0, 1.0);
    final color = Color.lerp(base, highlight, intensity)!
        .withValues(alpha: alpha.toDouble());

    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontWeight: glowPass ? FontWeight.w600 : FontWeight.w500,
          fontSize: fontSize,
          height: 1.0,
          shadows: glowPass
              ? [
                  Shadow(
                    color: color.withValues(
                      alpha: (0.16 + (0.42 * intensity)).clamp(0.0, 1.0),
                    ),
                    blurRadius: 6 + (8 * intensity),
                  ),
                ]
              : const <Shadow>[],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: fontSize * 1.8);

    _glyphPainterCache[key] = painter;
    if (_glyphPainterCache.length > 1400) {
      _glyphPainterCache.remove(_glyphPainterCache.keys.first);
    }
    return painter;
  }

  double _glyphWidth({
    required String glyph,
    required double fontSize,
  }) {
    final key = '$glyph|${fontSize.toStringAsFixed(2)}';
    final cached = _glyphWidthCache[key];
    if (cached != null) {
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w500,
          fontSize: fontSize,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: fontSize * 1.8);
    _glyphWidthCache[key] = painter.width;
    if (_glyphWidthCache.length > 320) {
      _glyphWidthCache.remove(_glyphWidthCache.keys.first);
    }
    return painter.width;
  }

  double _breathValue(double timeSeconds) {
    final phase =
        (timeSeconds / LandingLayoutConfig.globalBreathPeriodSec) * math.pi * 2;
    return 0.5 + (0.5 * math.sin(phase));
  }

  double _gaussianOnLoop({
    required double s,
    required double center,
    required double length,
    required double sigma,
  }) {
    if (sigma <= 0 || length <= 0) return 0;
    final absDistance = (s - center).abs();
    final d = math.min(absDistance, length - absDistance);
    final denom = 2 * sigma * sigma;
    return math.exp(-(d * d) / denom);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! _BreathingFramePainter ||
        oldDelegate.text != text ||
        oldDelegate.enableShimmer != enableShimmer ||
        oldDelegate.reduceMotion != reduceMotion ||
        (oldDelegate.timeSec - timeSec).abs() > 0.0001;
  }
}

class _FramePathData {
  const _FramePathData({
    required this.rect,
    required this.path,
    required this.metric,
    required this.length,
  });

  final Rect rect;
  final Path path;
  final ui.PathMetric metric;
  final double length;
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    required this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(24);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LandingLayoutConfig.glassBlurSigma,
          sigmaY: LandingLayoutConfig.glassBlurSigma,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: AppColors.backgroundDeep
                .withValues(alpha: LandingLayoutConfig.overlayOpacity),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.42),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

double _clampedParallaxOffset({
  required double scrollOffset,
  required double factor,
  required double overflow,
}) {
  final shift = scrollOffset * factor;
  if (shift < 0) return 0;
  if (shift > overflow) return overflow;
  return shift;
}

int _totalParticipants(List<LandingEvent> events) {
  var total = 0;
  for (final event in events) {
    total += event.participantsCount;
  }
  return total;
}

int _uniqueLocations(List<LandingEvent> events) {
  final unique = <String>{};
  for (final event in events) {
    final address = event.addressLabel.trim();
    if (address.isNotEmpty) {
      unique.add(address);
    }
  }
  return unique.length;
}

DateTime? _earliestDate(List<LandingEvent> events) {
  DateTime? out;
  for (final event in events) {
    final startsAt = event.startsAt;
    if (startsAt == null) continue;
    if (out == null || startsAt.isBefore(out)) {
      out = startsAt;
    }
  }
  return out;
}

String _eventMeta(LandingEvent? event) {
  if (event == null) return 'Новый цикл фестиваля уже открыт';
  final date = formatDateTime(event.startsAt);
  final address = event.addressLabel.trim();
  if (address.isEmpty) return date;
  return '$date • $address';
}
