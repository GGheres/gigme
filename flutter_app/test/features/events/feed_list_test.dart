import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:gigme_flutter/core/models/event_card.dart';
import 'package:gigme_flutter/features/events/presentation/widgets/feed_list.dart';

void main() {
  testWidgets('renders feed list items', (tester) async {
    final items = [
      _event(1, 'Event A'),
      _event(2, 'Event B'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedList(
            items: items,
            referencePoint: const LatLng(52.37, 4.90),
            apiUrl: 'https://example.test/api',
            eventAccessKeys: const <int, String>{},
            onTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Event A'), findsOneWidget);
    expect(find.text('Event B'), findsOneWidget);
  });
}

EventCard _event(int id, String title) {
  return EventCard(
    id: id,
    title: title,
    description: 'Desc',
    links: const [],
    startsAt: DateTime.parse('2026-02-08T20:00:00Z'),
    endsAt: null,
    lat: 52.37,
    lng: 4.90,
    capacity: null,
    promotedUntil: null,
    creatorName: 'Host',
    thumbnailUrl: '',
    participantsCount: 1,
    likesCount: 0,
    commentsCount: 0,
    filters: const [],
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
}
