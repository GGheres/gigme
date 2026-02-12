import '../utils/json_utils.dart';
import 'auth_session.dart';
import 'user_event.dart';

class AdminLoginResponse {

  factory AdminLoginResponse.fromJson(dynamic json) {
    return AdminLoginResponse(session: AuthSession.fromJson(json));
  }
  AdminLoginResponse({
    required this.session,
  });

  final AuthSession session;
}

class AdminUser {

  factory AdminUser.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminUser(
      id: asInt(map['id']),
      telegramId: asInt(map['telegramId']),
      username: asString(map['username']),
      firstName: asString(map['firstName']),
      lastName: asString(map['lastName']),
      photoUrl: asString(map['photoUrl']),
      rating: asDouble(map['rating']),
      ratingCount: asInt(map['ratingCount']),
      balanceTokens: asInt(map['balanceTokens']),
      isBlocked: asBool(map['isBlocked']),
      blockedReason: asString(map['blockedReason']),
      blockedAt: asDateTime(map['blockedAt']),
      lastSeenAt: asDateTime(map['lastSeenAt']),
      createdAt: asDateTime(map['createdAt']),
      updatedAt: asDateTime(map['updatedAt']),
    );
  }
  AdminUser({
    required this.id,
    required this.telegramId,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.photoUrl,
    required this.rating,
    required this.ratingCount,
    required this.balanceTokens,
    required this.isBlocked,
    required this.blockedReason,
    required this.blockedAt,
    required this.lastSeenAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int telegramId;
  final String username;
  final String firstName;
  final String lastName;
  final String photoUrl;
  final double rating;
  final int ratingCount;
  final int balanceTokens;
  final bool isBlocked;
  final String blockedReason;
  final DateTime? blockedAt;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName {
    final full = [firstName, lastName].where((value) => value.trim().isNotEmpty).join(' ').trim();
    if (full.isNotEmpty) return full;
    if (username.trim().isNotEmpty) return '@${username.trim()}';
    return 'ID $id';
  }
}

class AdminUsersResponse {

  factory AdminUsersResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminUsersResponse(
      items: asList(map['items']).map(AdminUser.fromJson).toList(),
      total: asInt(map['total']),
    );
  }
  AdminUsersResponse({
    required this.items,
    required this.total,
  });

  final List<AdminUser> items;
  final int total;
}

class AdminUserDetailResponse {

  factory AdminUserDetailResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminUserDetailResponse(
      user: AdminUser.fromJson(map['user']),
      createdEvents: asList(map['createdEvents']).map(UserEvent.fromJson).toList(),
    );
  }
  AdminUserDetailResponse({
    required this.user,
    required this.createdEvents,
  });

  final AdminUser user;
  final List<UserEvent> createdEvents;
}

class BroadcastButton {

  factory BroadcastButton.fromJson(dynamic json) {
    final map = asMap(json);
    return BroadcastButton(
      text: asString(map['text']),
      url: asString(map['url']),
    );
  }
  BroadcastButton({
    required this.text,
    required this.url,
  });

  final String text;
  final String url;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'text': text,
      'url': url,
    };
  }
}

class AdminBroadcast {

  factory AdminBroadcast.fromJson(dynamic json) {
    final map = asMap(json);
    final payload = asMap(map['payload']);
    return AdminBroadcast(
      id: asInt(map['id']),
      adminUserId: asInt(map['adminUserId']),
      audience: asString(map['audience']),
      status: asString(map['status']),
      createdAt: asDateTime(map['createdAt']),
      updatedAt: asDateTime(map['updatedAt']),
      targeted: asInt(map['targeted']),
      sent: asInt(map['sent']),
      failed: asInt(map['failed']),
      message: asString(payload['message']),
      buttons: asList(payload['buttons']).map(BroadcastButton.fromJson).toList(),
    );
  }
  AdminBroadcast({
    required this.id,
    required this.adminUserId,
    required this.audience,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.targeted,
    required this.sent,
    required this.failed,
    required this.message,
    required this.buttons,
  });

  final int id;
  final int adminUserId;
  final String audience;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int targeted;
  final int sent;
  final int failed;
  final String message;
  final List<BroadcastButton> buttons;
}

class AdminBroadcastsResponse {

  factory AdminBroadcastsResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminBroadcastsResponse(
      items: asList(map['items']).map(AdminBroadcast.fromJson).toList(),
      total: asInt(map['total']),
    );
  }
  AdminBroadcastsResponse({
    required this.items,
    required this.total,
  });

  final List<AdminBroadcast> items;
  final int total;
}

class AdminCreateBroadcastResponse {

  factory AdminCreateBroadcastResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminCreateBroadcastResponse(
      broadcastId: asInt(map['broadcastId']),
      targets: asInt(map['targets']),
    );
  }
  AdminCreateBroadcastResponse({
    required this.broadcastId,
    required this.targets,
  });

  final int broadcastId;
  final int targets;
}

class AdminParserSource {

  factory AdminParserSource.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminParserSource(
      id: asInt(map['id']),
      sourceType: asString(map['sourceType']),
      input: asString(map['input']),
      title: asString(map['title']),
      isActive: asBool(map['isActive']),
      lastParsedAt: asDateTime(map['lastParsedAt']),
      createdBy: asInt(map['createdBy']),
      createdAt: asDateTime(map['createdAt']),
      updatedAt: asDateTime(map['updatedAt']),
    );
  }
  AdminParserSource({
    required this.id,
    required this.sourceType,
    required this.input,
    required this.title,
    required this.isActive,
    required this.lastParsedAt,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String sourceType;
  final String input;
  final String title;
  final bool isActive;
  final DateTime? lastParsedAt;
  final int createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class AdminParserSourcesResponse {

  factory AdminParserSourcesResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminParserSourcesResponse(
      items: asList(map['items']).map(AdminParserSource.fromJson).toList(),
      total: asInt(map['total']),
    );
  }
  AdminParserSourcesResponse({
    required this.items,
    required this.total,
  });

  final List<AdminParserSource> items;
  final int total;
}

class AdminParsedEvent {

  factory AdminParsedEvent.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminParsedEvent(
      id: asInt(map['id']),
      sourceId: map['sourceId'] == null ? null : asInt(map['sourceId']),
      sourceType: asString(map['sourceType']),
      input: asString(map['input']),
      name: asString(map['name']),
      dateTime: asDateTime(map['dateTime']),
      location: asString(map['location']),
      description: asString(map['description']),
      links: asList(map['links']).map((item) => asString(item)).where((item) => item.isNotEmpty).toList(),
      status: asString(map['status']),
      parserError: asString(map['parserError']),
      parsedAt: asDateTime(map['parsedAt']),
      importedEventId: map['importedEventId'] == null ? null : asInt(map['importedEventId']),
      importedBy: map['importedBy'] == null ? null : asInt(map['importedBy']),
      importedAt: asDateTime(map['importedAt']),
      createdAt: asDateTime(map['createdAt']),
      updatedAt: asDateTime(map['updatedAt']),
    );
  }
  AdminParsedEvent({
    required this.id,
    required this.sourceId,
    required this.sourceType,
    required this.input,
    required this.name,
    required this.dateTime,
    required this.location,
    required this.description,
    required this.links,
    required this.status,
    required this.parserError,
    required this.parsedAt,
    required this.importedEventId,
    required this.importedBy,
    required this.importedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int? sourceId;
  final String sourceType;
  final String input;
  final String name;
  final DateTime? dateTime;
  final String location;
  final String description;
  final List<String> links;
  final String status;
  final String parserError;
  final DateTime? parsedAt;
  final int? importedEventId;
  final int? importedBy;
  final DateTime? importedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class AdminParsedEventsResponse {

  factory AdminParsedEventsResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminParsedEventsResponse(
      items: asList(map['items']).map(AdminParsedEvent.fromJson).toList(),
      total: asInt(map['total']),
    );
  }
  AdminParsedEventsResponse({
    required this.items,
    required this.total,
  });

  final List<AdminParsedEvent> items;
  final int total;
}

class AdminParserParseResponse {

  factory AdminParserParseResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminParserParseResponse(
      item: map['item'] == null ? null : AdminParsedEvent.fromJson(map['item']),
      items: asList(map['items']).map(AdminParsedEvent.fromJson).toList(),
      count: asInt(map['count']),
      error: asString(map['error']),
    );
  }
  AdminParserParseResponse({
    required this.item,
    required this.items,
    required this.count,
    required this.error,
  });

  final AdminParsedEvent? item;
  final List<AdminParsedEvent> items;
  final int count;
  final String error;
}

class GeocodeResult {

  factory GeocodeResult.fromJson(dynamic json) {
    final map = asMap(json);
    return GeocodeResult(
      displayName: asString(map['displayName']),
      lat: asDouble(map['lat']),
      lng: asDouble(map['lng']),
    );
  }
  GeocodeResult({
    required this.displayName,
    required this.lat,
    required this.lng,
  });

  final String displayName;
  final double lat;
  final double lng;
}

class GeocodeResultsResponse {

  factory GeocodeResultsResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return GeocodeResultsResponse(
      items: asList(map['items']).map(GeocodeResult.fromJson).toList(),
    );
  }
  GeocodeResultsResponse({required this.items});

  final List<GeocodeResult> items;
}
