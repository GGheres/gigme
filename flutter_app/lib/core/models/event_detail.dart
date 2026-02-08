import '../utils/json_utils.dart';
import 'event_card.dart';
import 'participant.dart';

class EventDetail {
  EventDetail({
    required this.event,
    required this.participants,
    required this.media,
    required this.isJoined,
  });

  final EventCard event;
  final List<Participant> participants;
  final List<String> media;
  final bool isJoined;

  factory EventDetail.fromJson(dynamic json) {
    final map = asMap(json);
    return EventDetail(
      event: EventCard.fromJson(map['event']),
      participants: asList(map['participants']).map(Participant.fromJson).toList(),
      media: asList(map['media']).map((e) => asString(e)).where((e) => e.isNotEmpty).toList(),
      isJoined: asBool(map['isJoined']),
    );
  }

  EventDetail copyWith({
    EventCard? event,
    List<Participant>? participants,
    List<String>? media,
    bool? isJoined,
  }) {
    return EventDetail(
      event: event ?? this.event,
      participants: participants ?? this.participants,
      media: media ?? this.media,
      isJoined: isJoined ?? this.isJoined,
    );
  }
}
