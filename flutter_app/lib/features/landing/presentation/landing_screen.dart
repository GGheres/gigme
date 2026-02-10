import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/models/landing_content.dart';
import '../../../core/models/landing_event.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_button.dart';
import '../../../ui/components/app_modal.dart';
import '../../../ui/components/app_section_header.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../../integrations/telegram/telegram_web_app_bridge.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
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
                      enableShimmer: true,
                      enableGrain: true,
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
                      loading: _loading,
                      error: _error,
                      events: _events,
                      content: _content,
                      total: _total,
                      onOpenApp: () => context.go(AppRoutes.appRoot),
                      onRefresh: _loading ? null : _load,
                      onOpenEvent: _openApp,
                      onBuy: _openTicket,
                      onShowEventDetails: _showEventSheet,
                      onOpenTelegram: () {
                        unawaited(_openExternal('https://t.me/gigme_support'));
                      },
                      onOpenEmail: () {
                        unawaited(_openExternal('mailto:hello@gigme.app'));
                      },
                      onOpenWebsite: () {
                        unawaited(_openExternal(Uri.base.origin));
                      },
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

  Future<void> _openExternal(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }

  Future<void> _openTicket(LandingEvent event) async {
    final rawUrl =
        event.ticketUrl.trim().isNotEmpty ? event.ticketUrl : event.appUrl;
    if (rawUrl.trim().isEmpty) return;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openApp(LandingEvent event) async {
    final rawUrl = event.appUrl.trim();
    if (rawUrl.isEmpty) {
      context.go(AppRoutes.appRoot);
      return;
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      context.go(AppRoutes.appRoot);
      return;
    }

    final localPath = _localAppPath(uri);
    final authStatus = ref.read(authControllerProvider).state.status;
    if (localPath != null && authStatus == AuthStatus.authenticated) {
      context.go(localPath);
      return;
    }

    final target = uri.hasScheme ? uri : Uri.base.resolveUri(uri);
    await launchUrl(target, mode: LaunchMode.platformDefault);
  }

  Future<void> _showEventSheet(LandingEvent event) async {
    await showAppModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(formatDateTime(event.startsAt)),
              if (event.addressLabel.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(event.addressLabel.trim()),
              ],
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Купить билет',
                variant: AppButtonVariant.primary,
                icon: const Icon(Icons.confirmation_number_outlined),
                expand: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(_openTicket(event));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

String? _localAppPath(Uri uri) {
  if (uri.path.isEmpty || !uri.path.startsWith(AppRoutes.appRoot)) {
    return null;
  }
  if (uri.host.isNotEmpty) {
    final current = Uri.base;
    if (uri.host != current.host || uri.scheme != current.scheme) {
      return null;
    }
  }

  var out = uri.path;
  if (uri.hasQuery) {
    out = '$out?${uri.query}';
  }
  if (uri.fragment.isNotEmpty) {
    out = '$out#${uri.fragment}';
  }
  return out;
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
  static const String backgroundAssetPath =
      'assets/images/landing/landing_bg_forest_fairies.png';

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
    required this.loading,
    required this.error,
    required this.events,
    required this.content,
    required this.total,
    required this.onOpenApp,
    required this.onRefresh,
    required this.onOpenEvent,
    required this.onBuy,
    required this.onShowEventDetails,
    required this.onOpenTelegram,
    required this.onOpenEmail,
    required this.onOpenWebsite,
  });

  final Size viewport;
  final double canvasHeight;
  final double quietZoneLeft;
  final double quietZoneWidth;
  final bool loading;
  final String? error;
  final List<LandingEvent> events;
  final LandingContent content;
  final int total;
  final VoidCallback onOpenApp;
  final Future<void> Function()? onRefresh;
  final ValueChanged<LandingEvent> onOpenEvent;
  final ValueChanged<LandingEvent> onBuy;
  final ValueChanged<LandingEvent> onShowEventDetails;
  final VoidCallback onOpenTelegram;
  final VoidCallback onOpenEmail;
  final VoidCallback onOpenWebsite;

  @override
  Widget build(BuildContext context) {
    final featuredEvent = events.isNotEmpty ? events.first : null;
    final totalParticipants = _totalParticipants(events);
    final creators = _uniqueCreators(events);

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
    final partnersTop = LandingLayoutConfig.sectionTop(
      canvasHeight: canvasHeight,
      viewportHeight: viewport.height,
      anchor: LandingLayoutConfig.sectionAnchorOffsets['partners']!,
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
                total: total,
                loading: loading,
                error: error,
                totalParticipants: totalParticipants,
                content: content,
                onOpenApp: onOpenApp,
                onRefresh: onRefresh,
                onBuyFeatured:
                    featuredEvent == null ? null : () => onBuy(featuredEvent),
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
          Positioned(
            top: partnersTop + mediaPadding.top,
            left: quietZoneLeft,
            width: quietZoneWidth,
            child: RepaintBoundary(
              child: _PartnersContactsSection(
                events: events.take(3).toList(),
                creators: creators,
                content: content,
                total: total,
                onOpenEvent: onOpenEvent,
                onBuy: onBuy,
                onShowEventDetails: onShowEventDetails,
                onOpenTelegram: onOpenTelegram,
                onOpenEmail: onOpenEmail,
                onOpenWebsite: onOpenWebsite,
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
    required this.content,
    required this.total,
    required this.loading,
    required this.error,
    required this.totalParticipants,
    required this.onOpenApp,
    required this.onRefresh,
    required this.onBuyFeatured,
  });

  final LandingEvent? featuredEvent;
  final LandingContent content;
  final int total;
  final bool loading;
  final String? error;
  final int totalParticipants;
  final VoidCallback onOpenApp;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onBuyFeatured;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1200;
    final title = content.heroTitle.trim();
    final description = content.heroDescription.trim();
    final meta = _eventMeta(featuredEvent);

    return _GlassPanel(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            maxLines: isWide ? 4 : 5,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _HeroActions(
                    total: total,
                    totalParticipants: totalParticipants,
                    openAppLabel: content.heroPrimaryCtaLabel.trim(),
                    onOpenApp: onOpenApp,
                    onRefresh: onRefresh,
                    onBuyFeatured: onBuyFeatured,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _HeroPoster(event: featuredEvent),
              ],
            )
          else ...[
            _HeroPoster(event: featuredEvent),
            const SizedBox(height: AppSpacing.sm),
            _HeroActions(
              total: total,
              totalParticipants: totalParticipants,
              openAppLabel: content.heroPrimaryCtaLabel.trim(),
              onOpenApp: onOpenApp,
              onRefresh: onRefresh,
              onBuyFeatured: onBuyFeatured,
            ),
          ],
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
    required this.onOpenApp,
    required this.onRefresh,
    required this.onBuyFeatured,
  });

  final int total;
  final int totalParticipants;
  final String openAppLabel;
  final VoidCallback onOpenApp;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onBuyFeatured;

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
              onPressed: onOpenApp,
            ),
            if (onBuyFeatured != null)
              AppButton(
                label: 'Купить билет',
                variant: AppButtonVariant.outline,
                icon: const Icon(Icons.confirmation_number_outlined),
                onPressed: onBuyFeatured,
              ),
            AppButton(
              label: 'Обновить',
              variant: AppButtonVariant.ghost,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: onRefresh == null
                  ? null
                  : () {
                      unawaited(onRefresh!.call());
                    },
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
  const _HeroPoster({required this.event});

  final LandingEvent? event;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 1200;
    final width = isNarrow ? double.infinity : 230.0;
    final height = isNarrow ? 210.0 : 286.0;
    final hasImage = (event?.thumbnailUrl ?? '').trim().isNotEmpty;

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage)
              Image.network(
                event!.thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, _, __) => const _PosterFallback(),
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

class _PartnersContactsSection extends StatelessWidget {
  const _PartnersContactsSection({
    required this.events,
    required this.creators,
    required this.content,
    required this.total,
    required this.onOpenEvent,
    required this.onBuy,
    required this.onShowEventDetails,
    required this.onOpenTelegram,
    required this.onOpenEmail,
    required this.onOpenWebsite,
  });

  final List<LandingEvent> events;
  final List<String> creators;
  final LandingContent content;
  final int total;
  final ValueChanged<LandingEvent> onOpenEvent;
  final ValueChanged<LandingEvent> onBuy;
  final ValueChanged<LandingEvent> onShowEventDetails;
  final VoidCallback onOpenTelegram;
  final VoidCallback onOpenEmail;
  final VoidCallback onOpenWebsite;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: content.partnersTitle.trim(),
            subtitle: content.partnersDescription.trim(),
            titleColor: Colors.white,
            subtitleColor: Colors.white.withValues(alpha: 0.84),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (creators.isEmpty)
            const SizedBox.shrink()
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: creators
                  .take(10)
                  .map(
                    (creator) => AppBadge(
                      label: creator,
                      variant: AppBadgeVariant.info,
                      textStyle: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.white),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppButton(
                label: 'Telegram',
                variant: AppButtonVariant.outline,
                icon: const Icon(Icons.telegram_rounded),
                onPressed: onOpenTelegram,
              ),
              AppButton(
                label: 'Email',
                variant: AppButtonVariant.outline,
                icon: const Icon(Icons.mail_outline_rounded),
                onPressed: onOpenEmail,
              ),
              AppButton(
                label: 'Сайт',
                variant: AppButtonVariant.secondary,
                icon: const Icon(Icons.public_rounded),
                onPressed: onOpenWebsite,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (events.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.info.withValues(alpha: 0.35)),
                color: AppColors.backgroundDeep.withValues(alpha: 0.30),
              ),
              child: Text(
                'События скоро появятся в этом блоке.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
              ),
            )
          else
            ...events.map(
              (event) => _LandingEventCompactCard(
                event: event,
                onOpenEvent: () => onOpenEvent(event),
                onBuy: () => onBuy(event),
                onShowDetails: () => onShowEventDetails(event),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Divider(color: AppColors.info.withValues(alpha: 0.35)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '© ${DateTime.now().year} ${content.footerText.trim()}. '
            'Опубликовано событий: $total.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white.withValues(alpha: 0.82)),
          ),
        ],
      ),
    );
  }
}

class _LandingEventCompactCard extends StatelessWidget {
  const _LandingEventCompactCard({
    required this.event,
    required this.onOpenEvent,
    required this.onBuy,
    required this.onShowDetails,
  });

  final LandingEvent event;
  final VoidCallback onOpenEvent;
  final VoidCallback onBuy;
  final VoidCallback onShowDetails;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
        color: AppColors.backgroundDeep.withValues(alpha: 0.36),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              formatDateTime(event.startsAt),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white.withValues(alpha: 0.82)),
            ),
            if (event.addressLabel.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                event.addressLabel.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.74)),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(
              event.description.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                AppButton(
                  label: 'Подробнее',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  icon: const Icon(Icons.info_outline_rounded),
                  onPressed: onShowDetails,
                ),
                AppButton(
                  label: 'Билет',
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  icon: const Icon(Icons.confirmation_number_outlined),
                  onPressed: onBuy,
                ),
                AppButton(
                  label: 'Открыть в app',
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.sm,
                  onPressed: onOpenEvent,
                ),
              ],
            ),
          ],
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
        const DecoratedBox(
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
        ),
        _ParallaxLayer(
          scrollOffset: scrollOffset,
          factor: LandingLayoutConfig.parallaxFactor(
            layer: 'farStars',
            reduceMotion: reduceMotion,
          ),
          overflow: overflow,
          child: Image.asset(
            LandingLayoutConfig.backgroundAssetPath,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            filterQuality: FilterQuality.medium,
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

List<String> _uniqueCreators(List<LandingEvent> events) {
  final unique = <String>{};
  for (final event in events) {
    final creator = event.creatorName.trim();
    if (creator.isNotEmpty) {
      unique.add(creator);
    }
  }
  return unique.toList();
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
