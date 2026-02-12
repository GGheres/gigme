import '../utils/json_utils.dart';

class EventCard {

  factory EventCard.fromJson(dynamic json) {
    final map = asMap(json);
    return EventCard(
      id: asInt(map['id']),
      title: asString(map['title']),
      description: asString(map['description']),
      links: asList(map['links']).map((e) => asString(e)).where((e) => e.isNotEmpty).toList(),
      startsAt: asDateTime(map['startsAt']),
      endsAt: asDateTime(map['endsAt']),
      lat: asDouble(map['lat']),
      lng: asDouble(map['lng']),
      capacity: map['capacity'] == null ? null : asInt(map['capacity']),
      promotedUntil: asDateTime(map['promotedUntil']),
      creatorName: asString(map['creatorName']),
      thumbnailUrl: asString(map['thumbnailUrl']),
      participantsCount: asInt(map['participantsCount']),
      likesCount: asInt(map['likesCount']),
      commentsCount: asInt(map['commentsCount']),
      filters: asList(map['filters']).map((e) => asString(e)).where((e) => e.isNotEmpty).toList(),
      isJoined: asBool(map['isJoined']),
      isLiked: asBool(map['isLiked']),
      isPrivate: asBool(map['isPrivate']),
      accessKey: asString(map['accessKey']),
      contactTelegram: asString(map['contactTelegram']),
      contactWhatsapp: asString(map['contactWhatsapp']),
      contactWechat: asString(map['contactWechat']),
      contactFbMessenger: asString(map['contactFbMessenger']),
      contactSnapchat: asString(map['contactSnapchat']),
    );
  }
  EventCard({
    required this.id,
    required this.title,
    required this.description,
    required this.links,
    required this.startsAt,
    required this.endsAt,
    required this.lat,
    required this.lng,
    required this.capacity,
    required this.promotedUntil,
    required this.creatorName,
    required this.thumbnailUrl,
    required this.participantsCount,
    required this.likesCount,
    required this.commentsCount,
    required this.filters,
    required this.isJoined,
    required this.isLiked,
    required this.isPrivate,
    required this.accessKey,
    required this.contactTelegram,
    required this.contactWhatsapp,
    required this.contactWechat,
    required this.contactFbMessenger,
    required this.contactSnapchat,
  });

  final int id;
  final String title;
  final String description;
  final List<String> links;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final double lat;
  final double lng;
  final int? capacity;
  final DateTime? promotedUntil;
  final String creatorName;
  final String thumbnailUrl;
  final int participantsCount;
  final int likesCount;
  final int commentsCount;
  final List<String> filters;
  final bool isJoined;
  final bool isLiked;
  final bool isPrivate;
  final String accessKey;
  final String contactTelegram;
  final String contactWhatsapp;
  final String contactWechat;
  final String contactFbMessenger;
  final String contactSnapchat;

  bool get isFeatured => promotedUntil != null && promotedUntil!.isAfter(DateTime.now());

  EventCard copyWith({
    int? participantsCount,
    int? likesCount,
    int? commentsCount,
    bool? isJoined,
    bool? isLiked,
    String? accessKey,
    String? contactTelegram,
    String? contactWhatsapp,
    String? contactWechat,
    String? contactFbMessenger,
    String? contactSnapchat,
  }) {
    return EventCard(
      id: id,
      title: title,
      description: description,
      links: links,
      startsAt: startsAt,
      endsAt: endsAt,
      lat: lat,
      lng: lng,
      capacity: capacity,
      promotedUntil: promotedUntil,
      creatorName: creatorName,
      thumbnailUrl: thumbnailUrl,
      participantsCount: participantsCount ?? this.participantsCount,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      filters: filters,
      isJoined: isJoined ?? this.isJoined,
      isLiked: isLiked ?? this.isLiked,
      isPrivate: isPrivate,
      accessKey: accessKey ?? this.accessKey,
      contactTelegram: contactTelegram ?? this.contactTelegram,
      contactWhatsapp: contactWhatsapp ?? this.contactWhatsapp,
      contactWechat: contactWechat ?? this.contactWechat,
      contactFbMessenger: contactFbMessenger ?? this.contactFbMessenger,
      contactSnapchat: contactSnapchat ?? this.contactSnapchat,
    );
  }
}
