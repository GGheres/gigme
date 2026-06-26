import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/providers.dart';
import '../../../ui/components/inline_status_banner.dart';
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
    final state = events.state;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? AppColors.darkSurface : AppColors.backgroundSoft;

    if (!_loadedOnce && !location.state.loading) {
      _loadedOnce = true;
      final controller = ref.read(eventsControllerProvider);
      if (state.activeFilters.isNotEmpty || state.nearbyOnly) {
        controller.clearFilters();
      }
      unawaited(
        controller.refresh(
          center: location.state.center,
          forceLoading: true,
        ),
      );
    }

    return AppScaffold(
      backgroundColor: backgroundColor,
      showBackgroundDecor: false,
      child: Column(
        children: [
          if (location.state.permissionDenied) ...[
            const InlineStatusBanner(
              title: 'Геолокация недоступна',
              message:
                  'Доступ к геолокации запрещен. Показываем события относительно центра по умолчанию.',
              tone: InlineStatusBannerTone.warning,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if ((state.error ?? '').isNotEmpty) ...[
            InlineStatusBanner(
              title: 'Не удалось обновить ленту',
              message: state.error!,
              tone: InlineStatusBannerTone.danger,
              actionLabel: 'Повторить',
              onAction: () => ref
                  .read(eventsControllerProvider)
                  .refresh(center: location.state.center),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref
                  .read(eventsControllerProvider)
                  .refresh(center: location.state.center),
              child: FeedList(
                items: state.feed,
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
