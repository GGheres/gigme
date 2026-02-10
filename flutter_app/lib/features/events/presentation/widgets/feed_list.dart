import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/models/event_card.dart';
import '../../../../ui/components/app_button.dart';
import '../../../../ui/components/app_card.dart';
import '../../../../ui/components/app_section_header.dart';
import '../../../../ui/theme/app_spacing.dart';
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
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SizedBox(height: 80),
          AppCard(
            child: Column(
              children: [
                AppSectionHeader(
                  title: 'No events yet',
                  subtitle: 'Create the first event to kick things off.',
                ),
                SizedBox(height: AppSpacing.xs),
                AppButton(
                  label: 'Try refreshing',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final event = items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
