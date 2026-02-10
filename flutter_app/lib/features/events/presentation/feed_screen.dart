import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/constants/event_filters.dart';
import '../../../core/widgets/premium_loading_view.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby feed'),
        actions: [
          IconButton(
            onPressed: () => ref.read(locationControllerProvider).refresh(),
            tooltip: 'Refresh location',
            icon: const Icon(Icons.my_location_outlined),
          ),
          IconButton(
            onPressed: () => ref
                .read(eventsControllerProvider)
                .refresh(center: location.state.center),
            tooltip: 'Refresh feed',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
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
          if (location.state.permissionDenied)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text('Location denied. Using default center.'),
            ),
          if ((state.error ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: showLoader
                ? const PremiumLoadingView(
                    text: 'NEARBY FEED • LOADING • ',
                    subtitle: 'Загружаем события рядом',
                  )
                : RefreshIndicator(
                    onRefresh: () => ref
                        .read(eventsControllerProvider)
                        .refresh(center: location.state.center),
                    child: FeedList(
                      items: state.feed,
                      referencePoint: location.state.userLocation,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilterChip(
                selected: nearbyOnly,
                label: const Text('Nearby 100 km'),
                onSelected: (_) => onToggleNearby(),
              ),
              const Spacer(),
              if (activeFilters.isNotEmpty)
                TextButton(
                  onPressed: onClearFilters,
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: kEventFilters
                  .map(
                    (filter) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: activeFilters.contains(filter.id),
                        label: Text('${filter.icon} ${filter.label}'),
                        onSelected: (_) => onToggleFilter(filter.id),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
