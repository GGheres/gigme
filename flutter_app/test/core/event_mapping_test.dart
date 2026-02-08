import 'package:flutter_test/flutter_test.dart';

import 'package:gigme_flutter/core/models/event_card.dart';
import 'package:gigme_flutter/core/models/event_detail.dart';

void main() {
  test('maps EventCard from backend json', () {
    final event = EventCard.fromJson({
      'id': 101,
      'title': 'Sunset meetup',
      'description': 'Chill event',
      'startsAt': '2026-02-08T18:00:00Z',
      'lat': 52.37,
      'lng': 4.90,
      'participantsCount': 4,
      'likesCount': 10,
      'commentsCount': 2,
      'filters': ['party', 'travel'],
      'isPrivate': true,
      'accessKey': 'abc123',
    });

    expect(event.id, 101);
    expect(event.title, 'Sunset meetup');
    expect(event.filters, ['party', 'travel']);
    expect(event.isPrivate, true);
    expect(event.accessKey, 'abc123');
  });

  test('maps EventDetail with participants and media', () {
    final detail = EventDetail.fromJson({
      'event': {
        'id': 11,
        'title': 'Gig',
        'description': 'Live music',
        'startsAt': '2026-02-08T19:00:00Z',
        'lat': 52.37,
        'lng': 4.90,
        'participantsCount': 1,
        'likesCount': 0,
        'commentsCount': 0,
      },
      'participants': [
        {'userId': 1, 'name': 'Alice', 'joinedAt': '2026-02-08T17:00:00Z'}
      ],
      'media': ['https://cdn/gig.jpg'],
      'isJoined': true,
    });

    expect(detail.event.id, 11);
    expect(detail.participants.length, 1);
    expect(detail.participants.first.name, 'Alice');
    expect(detail.media.first, 'https://cdn/gig.jpg');
    expect(detail.isJoined, true);
  });
}
