import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gigme_flutter/core/models/event_card.dart';
import 'package:gigme_flutter/features/events/presentation/widgets/feed_list.dart';
import 'package:gigme_flutter/features/events/presentation/widgets/event_card_tile.dart';

/// main is the application entry point.

void main() {
  testWidgets('renders feed list items', (tester) async {
    final items = [_event(1, 'Event A'), _event(2, 'Event B')];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedList(
            items: items,
            referencePoint: null,
            apiUrl: 'https://example.test/api',
            eventAccessKeys: const <int, String>{},
            likeLoadingIds: const <int>{},
            onRefresh: () async {},
            onTap: (_) {},
            onLikeTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(EventCardTile), findsOneWidget);
    expect(
      tester.widget<EventCardTile>(find.byType(EventCardTile)).event.id,
      1,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.byType(EventCardTile), findsNWidgets(2));
    final visibleIds = tester
        .widgetList<EventCardTile>(find.byType(EventCardTile))
        .map((tile) => tile.event.id)
        .toSet();
    expect(visibleIds, equals(<int>{1, 2}));
    expect(find.text('Event B'), findsOneWidget);
  });
}

/// _event creates a test event fixture.

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
