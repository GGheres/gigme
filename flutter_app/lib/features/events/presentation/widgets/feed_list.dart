import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/models/event_card.dart';
import 'event_card_tile.dart';

class FeedList extends StatelessWidget {
  const FeedList({
    required this.items,
    required this.referencePoint,
    required this.onTap,
    super.key,
  });

  final List<EventCard> items;
  final LatLng? referencePoint;
  final ValueChanged<EventCard> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: Text('No events yet. Create the first one.')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final event = items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: EventCardTile(
            event: event,
            referencePoint: referencePoint,
            onTap: () => onTap(event),
          ),
        );
      },
    );
  }
}
