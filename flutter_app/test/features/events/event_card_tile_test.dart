import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gigme_flutter/core/models/event_card.dart';
import 'package:gigme_flutter/features/events/presentation/widgets/event_card_tile.dart';

/// main is the application entry point.

void main() {
  testWidgets('renders compact event card actions', (tester) async {
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
            onTap: () {},
            onLikeTap: () {},
          ),
        ),
      ),
    );

    expect(find.byType(EventCardTile), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
  });

  testWidgets('renders featured compact event card', (tester) async {
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
      promotedUntil: DateTime.now().add(const Duration(days: 5)),
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
            onTap: () {},
            onLikeTap: () {},
          ),
        ),
      ),
    );

    expect(find.byType(EventCardTile), findsOneWidget);
  });

  testWidgets('calls like handler when heart icon is tapped', (tester) async {
    var likesTapped = 0;
    var cardTapped = 0;
    final event = EventCard(
      id: 3,
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
            onTap: () => cardTapped += 1,
            onLikeTap: () => likesTapped += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();

    expect(likesTapped, 1);
    expect(cardTapped, 0);
    expect(
      tester.getSize(find.byIcon(Icons.favorite_border_rounded).hitTestable()),
      const Size(20, 20),
    );
    final likeInk = find.byWidgetPredicate(
      (widget) => widget is Ink && widget.width == 48 && widget.height == 48,
    );
    expect(tester.getSize(likeInk), const Size(48, 48));
  });
}
