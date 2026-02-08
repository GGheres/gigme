import '../utils/json_utils.dart';

class EventMarker {
  EventMarker({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.lat,
    required this.lng,
    required this.isPromoted,
    required this.filters,
  });

  final int id;
  final String title;
  final DateTime? startsAt;
  final double lat;
  final double lng;
  final bool isPromoted;
  final List<String> filters;

  factory EventMarker.fromJson(dynamic json) {
    final map = asMap(json);
    return EventMarker(
      id: asInt(map['id']),
      title: asString(map['title']),
      startsAt: asDateTime(map['startsAt']),
      lat: asDouble(map['lat']),
      lng: asDouble(map['lng']),
      isPromoted: asBool(map['isPromoted']),
      filters: asList(map['filters']).map((e) => asString(e)).where((e) => e.isNotEmpty).toList(),
    );
  }
}
