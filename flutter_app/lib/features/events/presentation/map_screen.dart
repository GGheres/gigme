import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/routes.dart';
import '../../../core/utils/date_time_utils.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event map'),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(eventsControllerProvider).refresh(center: center),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 12,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.all),
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
                        onTap: () => _openMarkerSheet(context, marker.id),
                        child: Container(
                          decoration: BoxDecoration(
                            color: marker.isPromoted
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.secondary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Icon(Icons.music_note_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (state.loading)
            const Positioned(
              top: 16,
              right: 16,
              child: CircularProgressIndicator(),
            ),
          if ((state.error ?? '').isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(state.error!),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _mapController.move(locationController.state.center, 13);
        },
        icon: const Icon(Icons.my_location_rounded),
        label: const Text('Center'),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(card?.title ?? 'Event #$eventId',
                  style: Theme.of(context).textTheme.titleLarge),
              if (card != null) ...[
                const SizedBox(height: 6),
                Text(formatDateTime(card.startsAt)),
                const SizedBox(height: 6),
                Text(
                  card.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
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
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Open event'),
              ),
            ],
          ),
        );
      },
    );
  }
}
