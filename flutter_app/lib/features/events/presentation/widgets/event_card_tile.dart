import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/models/event_card.dart';
import '../../../../core/utils/date_time_utils.dart';

class EventCardTile extends StatelessWidget {
  const EventCardTile({
    required this.event,
    required this.onTap,
    this.referencePoint,
    super.key,
  });

  final EventCard event;
  final VoidCallback onTap;
  final LatLng? referencePoint;

  @override
  Widget build(BuildContext context) {
    final startsAt = formatDateTime(event.startsAt);
    final distanceText = _distanceText();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (event.thumbnailUrl.trim().isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  event.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, __) => const _PlaceholderImage(),
                ),
              )
            else
              const _PlaceholderImage(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (event.isFeatured)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Featured'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(startsAt),
                  const SizedBox(height: 4),
                  Text(
                    event.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _MetaChip(label: '${event.participantsCount} going'),
                      _MetaChip(label: '${event.likesCount} likes'),
                      _MetaChip(label: '${event.commentsCount} comments'),
                      if (distanceText != null) _MetaChip(label: distanceText),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _distanceText() {
    if (referencePoint == null) return null;
    final km = haversineKm(
      lat1: referencePoint!.latitude,
      lng1: referencePoint!.longitude,
      lat2: event.lat,
      lng2: event.lng,
    );
    return formatDistanceKm(km);
  }
}

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      color: const Color(0xFFE8F0F4),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F2F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
