import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/constants/event_filters.dart';
import '../../../core/network/providers.dart';
import '../../../core/widgets/premium_loading_view.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_button.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_spacing.dart';
import '../application/events_controller.dart';
import '../application/location_controller.dart';
import 'widgets/feed_list.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _loadedOnce = false;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsControllerProvider);
    final location = ref.watch(locationControllerProvider);
    final config = ref.watch(appConfigProvider);

    if (!_loadedOnce && !location.state.loading) {
      _loadedOnce = true;
      unawaited(
        ref.read(eventsControllerProvider).refresh(
              center: location.state.center,
              forceLoading: true,
            ),
      );
    }

    final state = events.state;
    final showLoader = state.loading && state.feed.isEmpty;
    final featuredCount = state.feed.where((event) => event.isFeatured).length;

    return AppScaffold(
      title: 'Nearby feed',
      subtitle: 'Landing-style discovery around your current location',
      showBackgroundDecor: true,
      titleColor: Colors.white,
      subtitleColor: Colors.white70,
      child: Column(
        children: [
          _FeedHeroPanel(
            feedCount: state.feed.length,
            featuredCount: featuredCount,
            nearbyOnly: state.nearbyOnly,
            loading: state.loading,
            onRefreshLocation: () =>
                ref.read(locationControllerProvider).refresh(),
            onRefreshFeed: () {
              unawaited(
                ref.read(eventsControllerProvider).refresh(
                      center: location.state.center,
                    ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _FilterBar(
            activeFilters: state.activeFilters,
            nearbyOnly: state.nearbyOnly,
            onToggleNearby: () {
              ref
                  .read(eventsControllerProvider)
                  .setNearbyOnly(!state.nearbyOnly);
              unawaited(ref
                  .read(eventsControllerProvider)
                  .refresh(center: location.state.center));
            },
            onToggleFilter: (filterId) {
              ref.read(eventsControllerProvider).toggleFilter(filterId);
              unawaited(ref
                  .read(eventsControllerProvider)
                  .refresh(center: location.state.center));
            },
            onClearFilters: () {
              ref.read(eventsControllerProvider).clearFilters();
              unawaited(ref
                  .read(eventsControllerProvider)
                  .refresh(center: location.state.center));
            },
          ),
          if (location.state.permissionDenied) ...[
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              variant: AppCardVariant.panel,
              child: Row(
                children: [
                  const Icon(Icons.gps_off_rounded, color: Colors.white),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Location denied. Using a default map center.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.86),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if ((state.error ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              variant: AppCardVariant.panel,
              child: Row(
                children: [
                  const AppBadge(
                    label: 'Error',
                    variant: AppBadgeVariant.danger,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: AppCard(
              variant: AppCardVariant.panel,
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: showLoader
                  ? const PremiumLoadingView(
                      text: 'NEARBY FEED • LOADING • ',
                      subtitle: 'Загружаем события рядом',
                    )
                  : AppCard(
                      padding: EdgeInsets.zero,
                      child: RefreshIndicator(
                        onRefresh: () => ref
                            .read(eventsControllerProvider)
                            .refresh(center: location.state.center),
                        child: FeedList(
                          items: state.feed,
                          referencePoint: location.state.userLocation,
                          apiUrl: config.apiUrl,
                          eventAccessKeys: events.eventAccessKeys,
                          onTap: (event) {
                            final key = events.accessKeyFor(event.id,
                                fallback: event.accessKey);
                            final uri = Uri(
                              path: AppRoutes.event(event.id),
                              queryParameters: {
                                if (key.isNotEmpty) 'key': key,
                              },
                            );
                            context.push(uri.toString());
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedHeroPanel extends StatelessWidget {
  const _FeedHeroPanel({
    required this.feedCount,
    required this.featuredCount,
    required this.nearbyOnly,
    required this.loading,
    required this.onRefreshLocation,
    required this.onRefreshFeed,
  });

  final int feedCount;
  final int featuredCount;
  final bool nearbyOnly;
  final bool loading;
  final VoidCallback onRefreshLocation;
  final VoidCallback onRefreshFeed;

  @override
  Widget build(BuildContext context) {
    final infoTextColor = Colors.white.withValues(alpha: 0.84);

    return AppCard(
      variant: AppCardVariant.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'City Pulse',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  letterSpacing: 0.4,
                ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Подборка ближайших событий с динамикой как на лендинге.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: infoTextColor,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _HeroStatPill(label: 'Events', value: '$feedCount'),
              _HeroStatPill(label: 'Featured', value: '$featuredCount'),
              _HeroStatPill(
                label: 'Mode',
                value: nearbyOnly ? 'Nearby' : 'All',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppButton(
                label: 'Location',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.secondary,
                icon: const Icon(Icons.my_location_outlined),
                tooltip: 'Refresh location',
                onPressed: onRefreshLocation,
              ),
              AppButton(
                label: 'Refresh',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.primary,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh feed',
                onPressed: onRefreshFeed,
              ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroStatPill extends StatelessWidget {
  const _HeroStatPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.76),
                  ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              value,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.activeFilters,
    required this.nearbyOnly,
    required this.onToggleNearby,
    required this.onToggleFilter,
    required this.onClearFilters,
  });

  final List<String> activeFilters;
  final bool nearbyOnly;
  final VoidCallback onToggleNearby;
  final ValueChanged<String> onToggleFilter;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      variant: AppCardVariant.panel,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppBadge(
                label: nearbyOnly ? 'Nearby only' : 'All regions',
                variant: nearbyOnly
                    ? AppBadgeVariant.accent
                    : AppBadgeVariant.neutral,
              ),
              const SizedBox(width: AppSpacing.xs),
              AppBadge(
                label: '${activeFilters.length}/$kMaxEventFilters active',
                variant: AppBadgeVariant.neutral,
              ),
              const Spacer(),
              if (activeFilters.isNotEmpty || nearbyOnly)
                AppButton(
                  label: 'Clear',
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  onPressed: onClearFilters,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Theme(
            data: theme.copyWith(
              chipTheme: theme.chipTheme.copyWith(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                selectedColor: AppColors.secondary.withValues(alpha: 0.34),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                labelStyle: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    selected: nearbyOnly,
                    label: const Text('Nearby 100 km'),
                    onSelected: (_) => onToggleNearby(),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  ...kEventFilters.map(
                    (filter) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: FilterChip(
                        selected: activeFilters.contains(filter.id),
                        label: Text('${filter.icon} ${filter.label}'),
                        onSelected: (_) => onToggleFilter(filter.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
