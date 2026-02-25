import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/models/event_card.dart';
import '../../../../ui/components/app_button.dart';
import '../../../../ui/components/app_card.dart';
import '../../../../ui/components/app_section_header.dart';
import '../../../../ui/theme/app_spacing.dart';
import 'event_card_tile.dart';

/// FeedList represents feed list.

class FeedList extends StatelessWidget {
  /// FeedList handles feed list.
  const FeedList({
    required this.items,
    required this.referencePoint,
    required this.onTap,
    required this.onLikeTap,
    required this.apiUrl,
    required this.eventAccessKeys,
    required this.likeLoadingIds,
    super.key,
  });

  final List<EventCard> items;
  final LatLng? referencePoint;
  final ValueChanged<EventCard> onTap;
  final ValueChanged<EventCard> onLikeTap;
  final String apiUrl;
  final Map<int, String> eventAccessKeys;
  final Set<int> likeLoadingIds;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    const itemSpacing = kIsWeb ? AppSpacing.sm : AppSpacing.md;

    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SizedBox(height: 80),
          AppCard(
            child: Column(
              children: [
                AppSectionHeader(
                  title: 'Событий пока нет',
                  subtitle: 'Создайте первое событие, чтобы запустить ленту.',
                ),
                SizedBox(height: AppSpacing.xs),
                AppButton(
                  label: 'Обновить ленту',
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
        final accessKey = eventAccessKeys[event.id] ?? event.accessKey;
        return Padding(
          padding: const EdgeInsets.only(bottom: itemSpacing),
          child: EventCardTile(
            event: event,
            apiUrl: apiUrl,
            accessKey: accessKey,
            referencePoint: referencePoint,
            onTap: () => onTap(event),
            onLikeTap: () => onLikeTap(event),
            likeLoading: likeLoadingIds.contains(event.id),
          ),
        );
      },
    );
  }
}
