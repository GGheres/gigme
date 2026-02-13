import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/routes.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/section_card.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_spacing.dart';
import '../application/events_controller.dart';
import '../application/location_controller.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  bool _loadedOnce = false;

  @override
  Widget build(BuildContext context) {
    final eventsController = ref.watch(eventsControllerProvider);
    final locationController = ref.watch(locationControllerProvider);

    if (!_loadedOnce && !locationController.state.loading) {
      _loadedOnce = true;
      unawaited(
        ref.read(eventsControllerProvider).refresh(
              center: locationController.state.center,
              forceLoading: true,
            ),
      );
    }

    final state = eventsController.state;
    final center = locationController.state.center;

    return AppScaffold(
      title: 'Карта',
      subtitle: 'События рядом с вами',
      showBackgroundDecor: true,
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      child: Column(
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            alignment: WrapAlignment.end,
            children: [
              SecondaryButton(
                label: 'Моё место',
                icon: const Icon(Icons.my_location_rounded),
                onPressed: () {
                  _mapController.move(locationController.state.center, 13);
                },
                outline: true,
              ),
              PrimaryButton(
                label: 'Обновить',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () =>
                    ref.read(eventsControllerProvider).refresh(center: center),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: AppCard(
              variant: AppCardVariant.panel,
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 12,
                        interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all),
                        onPositionChanged: (position, hasGesture) {
                          if (!hasGesture) return;
                          ref
                              .read(locationControllerProvider)
                              .setMapCenter(position.center);
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'gigme_flutter',
                        ),
                        MarkerLayer(
                          markers: [
                            for (final marker in state.markers)
                              Marker(
                                width: 46,
                                height: 46,
                                point: LatLng(marker.lat, marker.lng),
                                child: GestureDetector(
                                  onTap: () =>
                                      _openMarkerSheet(context, marker.id),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: marker.isPromoted
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 6,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.music_note_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (state.loading)
                      const Positioned(
                        top: 12,
                        right: 12,
                        left: 12,
                        child: AppCard(
                          variant: AppCardVariant.surface,
                          child: LoadingState(
                            compact: true,
                            title: 'Загрузка',
                            subtitle: 'Обновляем карту',
                          ),
                        ),
                      ),
                    if ((state.error ?? '').isNotEmpty)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: AppCard(
                          variant: AppCardVariant.surface,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: AppColors.danger,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(child: Text(state.error!)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMarkerSheet(BuildContext context, int eventId) async {
    final eventsController = ref.read(eventsControllerProvider);
    final card = eventsController.feedEventById(eventId);
    final accessKey =
        eventsController.accessKeyFor(eventId, fallback: card?.accessKey);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: SectionCard(
            title: card?.title ?? 'Событие #$eventId',
            subtitle: card == null ? null : formatDateTime(card.startsAt),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (card != null)
                  Text(
                    card.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: 'Открыть событие',
                  icon: const Icon(Icons.arrow_forward_rounded),
                  expand: true,
                  onPressed: () {
                    Navigator.of(context).pop();
                    final uri = Uri(
                      path: AppRoutes.event(eventId),
                      queryParameters: {
                        if (accessKey.isNotEmpty) 'key': accessKey,
                      },
                    );
                    this.context.push(uri.toString());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
