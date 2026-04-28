import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/constants/event_filters.dart';
import '../../../core/network/providers.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_button.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/screen_hero.dart';
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
    final activeFilterCount = state.activeFilters.length;

    return AppScaffold(
      child: Column(
        children: [
          ScreenHero(
            title: 'Лента событий',
            subtitle:
                'Исследуй ближайшие встречи, открывай новые форматы и быстро переходи к созданию.',
            summary: [
              AppBadge(
                label: state.nearbyOnly ? 'Рядом с вами' : 'Все регионы',
                variant: state.nearbyOnly
                    ? AppBadgeVariant.accent
                    : AppBadgeVariant.neutral,
              ),
              AppBadge(
                label: '$activeFilterCount/$kMaxEventFilters фильтров',
                variant: activeFilterCount > 0
                    ? AppBadgeVariant.ghost
                    : AppBadgeVariant.neutral,
              ),
              AppBadge(
                label: '${state.feed.length} событий',
                variant: AppBadgeVariant.neutral,
              ),
            ],
            actions: [
              PrimaryButton(
                label: 'Создать событие',
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed: () => context.push(AppRoutes.create),
              ),
              SecondaryButton(
                label: 'Открыть карту',
                icon: const Icon(Icons.map_rounded),
                outline: true,
                onPressed: () => context.push(AppRoutes.map),
              ),
              AppButton(
                label: 'Обновить',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.md,
                onPressed: () => ref
                    .read(eventsControllerProvider)
                    .refresh(center: location.state.center),
              ),
            ],
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
            const InlineStatusBanner(
              title: 'Геолокация недоступна',
              message:
                  'Доступ к геолокации запрещен. Показываем события относительно центра по умолчанию.',
              tone: InlineStatusBannerTone.warning,
            ),
          ],
          if ((state.error ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            InlineStatusBanner(
              title: 'Не удалось обновить ленту',
              message: state.error!,
              tone: InlineStatusBannerTone.danger,
              actionLabel: 'Повторить',
              onAction: () => ref
                  .read(eventsControllerProvider)
                  .refresh(center: location.state.center),
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
                onRefresh: () => ref
                    .read(eventsControllerProvider)
                    .refresh(center: location.state.center),
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
          Text(
            'Фильтры ленты',
            style: theme.textTheme.titleSmall?.copyWith(
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Сузьте выдачу по радиусу и тематикам, чтобы быстрее найти нужный формат.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final useStackedHeader = constraints.maxWidth < 420;
              final badges = Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  AppBadge(
                    label: nearbyOnly ? 'Только рядом' : 'Все регионы',
                    variant: nearbyOnly
                        ? AppBadgeVariant.accent
                        : AppBadgeVariant.neutral,
                  ),
                  AppBadge(
                    label: '${activeFilters.length}/$kMaxEventFilters фильтров',
                    variant: AppBadgeVariant.neutral,
                  ),
                ],
              );
              final resetButton = (activeFilters.isNotEmpty || nearbyOnly)
                  ? AppButton(
                      label: 'Сбросить',
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.sm,
                      onPressed: onClearFilters,
                    )
                  : null;

              if (useStackedHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    badges,
                    if (resetButton != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      resetButton,
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: badges),
                  if (resetButton != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    resetButton,
                  ],
                ],
              );
            },
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
