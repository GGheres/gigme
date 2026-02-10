import '../utils/json_utils.dart';

class LandingEvent {
  LandingEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    required this.lat,
    required this.lng,
    required this.addressLabel,
    required this.creatorName,
    required this.participantsCount,
    required this.thumbnailUrl,
    required this.ticketUrl,
    required this.appUrl,
  });

  final int id;
  final String title;
  final String description;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final double lat;
  final double lng;
  final String addressLabel;
  final String creatorName;
  final int participantsCount;
  final String thumbnailUrl;
  final String ticketUrl;
  final String appUrl;

  factory LandingEvent.fromJson(dynamic json) {
    final map = asMap(json);
    return LandingEvent(
      id: asInt(map['id']),
      title: asString(map['title']),
      description: asString(map['description']),
      startsAt: asDateTime(map['startsAt']),
      endsAt: asDateTime(map['endsAt']),
      lat: asDouble(map['lat']),
      lng: asDouble(map['lng']),
      addressLabel: asString(map['addressLabel']),
      creatorName: asString(map['creatorName']),
      participantsCount: asInt(map['participantsCount']),
      thumbnailUrl: asString(map['thumbnailUrl']),
      ticketUrl: asString(map['ticketUrl']),
      appUrl: asString(map['appUrl']),
    );
  }
}

class LandingEventsResponse {
  LandingEventsResponse({
    required this.items,
    required this.total,
  });

  final List<LandingEvent> items;
  final int total;

  factory LandingEventsResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return LandingEventsResponse(
      items: asList(map['items']).map(LandingEvent.fromJson).toList(),
      total: asInt(map['total']),
    );
  }
}
