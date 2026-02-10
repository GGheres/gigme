import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:gigme_flutter/core/models/event_card.dart';
import 'package:gigme_flutter/features/events/presentation/widgets/event_card_tile.dart';

void main() {
  testWidgets('renders event card content', (tester) async {
    final event = EventCard(
      id: 1,
      title: 'City Jam',
      description: 'Open mic and DJ sets',
      links: const [],
      startsAt: DateTime.parse('2026-02-08T20:00:00Z'),
      endsAt: null,
      lat: 52.37,
      lng: 4.90,
      capacity: 20,
      promotedUntil: null,
      creatorName: 'Host',
      thumbnailUrl: '',
      participantsCount: 5,
      likesCount: 2,
      commentsCount: 1,
      filters: const ['party'],
      isJoined: false,
      isLiked: false,
      isPrivate: false,
      accessKey: '',
      contactTelegram: '',
      contactWhatsapp: '',
      contactWechat: '',
      contactFbMessenger: '',
      contactSnapchat: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventCardTile(
            event: event,
            apiUrl: 'https://example.test/api',
            referencePoint: const LatLng(52.37, 4.90),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('City Jam'), findsOneWidget);
    expect(find.textContaining('going'), findsOneWidget);
    expect(find.textContaining('likes'), findsOneWidget);
  });
}
