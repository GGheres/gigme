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

    return AppScaffold(
      title: 'Nearby feed',
      subtitle: 'Discover events around your current location',
      showBackgroundDecor: false,
      titleColor: Colors.white,
      subtitleColor: Colors.white70,
      trailing: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          AppButton(
            label: 'Location',
            size: AppButtonSize.sm,
            variant: AppButtonVariant.outline,
            icon: const Icon(Icons.my_location_outlined),
            tooltip: 'Refresh location',
            onPressed: () => ref.read(locationControllerProvider).refresh(),
          ),
          AppButton(
            label: 'Refresh',
            size: AppButtonSize.sm,
            variant: AppButtonVariant.secondary,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh feed',
            onPressed: () {
              unawaited(
                ref.read(eventsControllerProvider).refresh(
                      center: location.state.center,
                    ),
              );
            },
          ),
        ],
      ),
      child: Column(
        children: [
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
            const AppCard(
              variant: AppCardVariant.panel,
              child: Row(
                children: [
                  Icon(Icons.gps_off_rounded),
                  SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text('Location denied. Using a default map center.'),
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
                  Expanded(child: Text(state.error!)),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Expanded(
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
        ],
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
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppBadge(
                label: nearbyOnly ? 'Nearby only' : 'All regions',
                variant:
                    nearbyOnly ? AppBadgeVariant.accent : AppBadgeVariant.ghost,
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
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: onClearFilters,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SingleChildScrollView(
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
        ],
      ),
    );
  }
}
