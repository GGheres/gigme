import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/constants/event_filters.dart';
import '../../../core/network/providers.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_button.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_spacing.dart';
import '../application/events_controller.dart';
import '../application/location_controller.dart';
import 'widgets/feed_list.dart';

/// FeedScreen represents feed screen.

class FeedScreen extends ConsumerStatefulWidget {
  /// FeedScreen handles feed screen.
  const FeedScreen({super.key});

  /// createState creates state.

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

/// _FeedScreenState represents feed screen state.

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _loadedOnce = false;
  final Set<int> _likeLoadingIds = <int>{};

  /// build renders the widget tree for this component.

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
    return AppScaffold(
      title: 'Лента Событий',
      subtitle: 'Исследуй, создавай, присоединяйся.',
      showBackgroundDecor: true,
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.74),
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
            AppCard(
              variant: AppCardVariant.panel,
              child: Row(
                children: [
                  const Icon(Icons.gps_off_rounded, color: Colors.white),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Доступ к геолокации запрещен. Используется центр по умолчанию.',
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
                    label: 'Ошибка',
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
            child: RefreshIndicator(
              onRefresh: () => ref
                  .read(eventsControllerProvider)
                  .refresh(center: location.state.center),
              child: FeedList(
                items: state.feed,
                referencePoint:
                    location.state.userLocation ?? location.state.center,
                apiUrl: config.apiUrl,
                eventAccessKeys: events.eventAccessKeys,
                likeLoadingIds: _likeLoadingIds,
                onTap: (event) {
                  final key =
                      events.accessKeyFor(event.id, fallback: event.accessKey);
                  final uri = Uri(
                    path: AppRoutes.event(event.id),
                    queryParameters: {
                      if (key.isNotEmpty) 'key': key,
                    },
                  );
                  context.push(uri.toString());
                },
                onLikeTap: (event) async {
                  if (_likeLoadingIds.contains(event.id)) return;
                  final messenger = ScaffoldMessenger.of(context);
                  setState(() => _likeLoadingIds.add(event.id));
                  try {
                    await ref.read(eventsControllerProvider).toggleLike(
                          eventId: event.id,
                          isLiked: event.isLiked,
                          accessKey: events.accessKeyFor(
                            event.id,
                            fallback: event.accessKey,
                          ),
                        );
                  } catch (error) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('$error')),
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _likeLoadingIds.remove(event.id));
                    } else {
                      _likeLoadingIds.remove(event.id);
                    }
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// _FilterBar represents filter bar.

class _FilterBar extends StatelessWidget {
  /// _FilterBar handles filter bar.
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

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chipBackground = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : AppColors.surfaceStrong.withValues(alpha: 0.92);
    final chipSelected = isDark
        ? AppColors.secondary.withValues(alpha: 0.46)
        : AppColors.primary.withValues(alpha: 0.18);
    final chipBorder =
        isDark ? Colors.white.withValues(alpha: 0.32) : AppColors.borderStrong;
    final chipTextColor =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;

    return AppCard(
      variant: AppCardVariant.surface,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppBadge(
                label: nearbyOnly ? 'Только рядом' : 'Все регионы',
                variant: nearbyOnly
                    ? AppBadgeVariant.accent
                    : AppBadgeVariant.neutral,
              ),
              const SizedBox(width: AppSpacing.xs),
              AppBadge(
                label: '${activeFilters.length}/$kMaxEventFilters фильтров',
                variant: AppBadgeVariant.neutral,
              ),
              const Spacer(),
              if (activeFilters.isNotEmpty || nearbyOnly)
                AppButton(
                  label: 'Сбросить',
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
                backgroundColor: chipBackground,
                selectedColor: chipSelected,
                side: BorderSide(color: chipBorder),
                checkmarkColor: chipTextColor,
                labelStyle: theme.textTheme.bodySmall?.copyWith(
                  color: chipTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    selected: nearbyOnly,
                    label: const Text('Радиус 100 км'),
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
