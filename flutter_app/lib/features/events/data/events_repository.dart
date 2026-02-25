import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/event_card.dart';
import '../../../core/models/event_comment.dart';
import '../../../core/models/event_detail.dart';
import '../../../core/models/event_marker.dart';
import '../../../core/models/media_models.dart';
import '../../../core/models/referral.dart';
import '../../../core/network/api_paths.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/json_utils.dart';

/// CreateEventPayload represents create event payload.

class CreateEventPayload {
  /// CreateEventPayload creates event payload.
  CreateEventPayload({
    required this.title,
    required this.description,
    required this.startsAt,
    required this.lat,
    required this.lng,
    required this.media,
    this.endsAt,
    this.capacity,
    this.filters = const <String>[],
    this.isPrivate = false,
    this.contactTelegram,
    this.contactWhatsapp,
    this.contactWechat,
    this.contactFbMessenger,
    this.contactSnapchat,
    this.addressLabel,
  });

  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final double lat;
  final double lng;
  final int? capacity;
  final List<String> media;
  final List<String> filters;
  final bool isPrivate;
  final String? contactTelegram;
  final String? contactWhatsapp;
  final String? contactWechat;
  final String? contactFbMessenger;
  final String? contactSnapchat;
  final String? addressLabel;

  /// toJson handles to json.

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'description': description,
      'startsAt': startsAt.toUtc().toIso8601String(),
      if (endsAt != null) 'endsAt': endsAt!.toUtc().toIso8601String(),
      'lat': lat,
      'lng': lng,
      if (capacity != null) 'capacity': capacity,
      'media': media,
      'filters': filters,
      'isPrivate': isPrivate,
      if ((contactTelegram ?? '').trim().isNotEmpty)
        'contactTelegram': contactTelegram!.trim(),
      if ((contactWhatsapp ?? '').trim().isNotEmpty)
        'contactWhatsapp': contactWhatsapp!.trim(),
      if ((contactWechat ?? '').trim().isNotEmpty)
        'contactWechat': contactWechat!.trim(),
      if ((contactFbMessenger ?? '').trim().isNotEmpty)
        'contactFbMessenger': contactFbMessenger!.trim(),
      if ((contactSnapchat ?? '').trim().isNotEmpty)
        'contactSnapchat': contactSnapchat!.trim(),
      if ((addressLabel ?? '').trim().isNotEmpty)
        'addressLabel': addressLabel!.trim(),
    };
  }
}

/// UpdateEventAdminPayload represents update event admin payload.

class UpdateEventAdminPayload {
  /// UpdateEventAdminPayload updates event admin payload.
  UpdateEventAdminPayload({
    this.title,
    this.description,
    this.startsAt,
    this.endsAt,
    this.clearEndsAt = false,
    this.lat,
    this.lng,
    this.capacity,
    this.media,
    this.addressLabel,
    this.filters,
    this.contactTelegram,
    this.contactWhatsapp,
    this.contactWechat,
    this.contactFbMessenger,
    this.contactSnapchat,
  });

  final String? title;
  final String? description;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool clearEndsAt;
  final double? lat;
  final double? lng;
  final int? capacity;
  final List<String>? media;
  final String? addressLabel;
  final List<String>? filters;
  final String? contactTelegram;
  final String? contactWhatsapp;
  final String? contactWechat;
  final String? contactFbMessenger;
  final String? contactSnapchat;

  /// toJson handles to json.

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (title != null) 'title': title!.trim(),
      if (description != null) 'description': description!.trim(),
      if (startsAt != null) 'startsAt': startsAt!.toUtc().toIso8601String(),
      if (clearEndsAt)
        'endsAt': ''
      else if (endsAt != null)
        'endsAt': endsAt!.toUtc().toIso8601String(),
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (capacity != null) 'capacity': capacity,
      if (media != null) 'media': media,
      if (addressLabel != null) 'addressLabel': addressLabel!.trim(),
      if (filters != null) 'filters': filters,
      if (contactTelegram != null) 'contactTelegram': contactTelegram!.trim(),
      if (contactWhatsapp != null) 'contactWhatsapp': contactWhatsapp!.trim(),
      if (contactWechat != null) 'contactWechat': contactWechat!.trim(),
      if (contactFbMessenger != null)
        'contactFbMessenger': contactFbMessenger!.trim(),
      if (contactSnapchat != null) 'contactSnapchat': contactSnapchat!.trim(),
    };
  }
}

/// EventLikeStatus represents event like status.

class EventLikeStatus {
  /// EventLikeStatus handles event like status.
  factory EventLikeStatus.fromJson(dynamic json) {
    final map = asMap(json);
    return EventLikeStatus(
      likesCount: asInt(map['likesCount']),
      isLiked: asBool(map['isLiked']),
    );
  }

  /// EventLikeStatus handles event like status.

  EventLikeStatus({
    required this.likesCount,
    required this.isLiked,
  });

  final int likesCount;
  final bool isLiked;
}

/// EventsRepository represents events repository.

class EventsRepository {
  /// EventsRepository handles events repository.
  EventsRepository(this._ref);

  final Ref _ref;

  /// updateLocation updates location.

  Future<void> updateLocation({
    required String token,
    required double lat,
    required double lng,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          ApiPaths.meLocation,
          token: token,
          body: <String, dynamic>{
            'lat': lat,
            'lng': lng,
          },
          decoder: (_) {},
        );
  }

  /// getNearby returns nearby.

  Future<List<EventMarker>> getNearby({
    required String token,
    required double lat,
    required double lng,
    int radiusM = 0,
    List<String> filters = const <String>[],
    List<String> accessKeys = const <String>[],
  }) {
    return _ref.read(apiClientProvider).get<List<EventMarker>>(
          ApiPaths.eventsNearby,
          token: token,
          query: <String, dynamic>{
            'lat': lat,
            'lng': lng,
            if (radiusM > 0) 'radiusM': radiusM,
            if (filters.isNotEmpty) 'filters': filters.join(','),
            if (accessKeys.isNotEmpty) 'eventKeys': accessKeys.join(','),
          },
          decoder: (data) => asList(data).map(EventMarker.fromJson).toList(),
        );
  }

  /// getFeed returns feed.

  Future<List<EventCard>> getFeed({
    required String token,
    required double lat,
    required double lng,
    int radiusM = 0,
    List<String> filters = const <String>[],
    List<String> accessKeys = const <String>[],
  }) {
    return _ref.read(apiClientProvider).get<List<EventCard>>(
          ApiPaths.eventsFeed,
          token: token,
          query: <String, dynamic>{
            'lat': lat,
            'lng': lng,
            'limit': 50,
            'offset': 0,
            if (radiusM > 0) 'radiusM': radiusM,
            if (filters.isNotEmpty) 'filters': filters.join(','),
            if (accessKeys.isNotEmpty) 'eventKeys': accessKeys.join(','),
          },
          decoder: (data) => asList(data).map(EventCard.fromJson).toList(),
        );
  }

  /// getEvent returns event.

  Future<EventDetail> getEvent({
    required String token,
    required int eventId,
    String? accessKey,
  }) {
    return _ref.read(apiClientProvider).get<EventDetail>(
          ApiPaths.eventById(eventId),
          token: token,
          query: <String, dynamic>{
            if ((accessKey ?? '').trim().isNotEmpty)
              'eventKey': accessKey!.trim(),
          },
          decoder: EventDetail.fromJson,
          retry: false,
        );
  }

  /// createEvent creates event.

  Future<CreateEventResponse> createEvent({
    required String token,
    required CreateEventPayload payload,
  }) {
    return _ref.read(apiClientProvider).post<CreateEventResponse>(
          ApiPaths.events,
          token: token,
          body: payload.toJson(),
          decoder: CreateEventResponse.fromJson,
        );
  }

  /// joinEvent joins event.

  Future<void> joinEvent({
    required String token,
    required int eventId,
    String? accessKey,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          ApiPaths.eventJoin(eventId),
          token: token,
          query: <String, dynamic>{
            if ((accessKey ?? '').trim().isNotEmpty)
              'eventKey': accessKey!.trim(),
          },
          decoder: (_) {},
        );
  }

  /// leaveEvent leaves event.

  Future<void> leaveEvent({
    required String token,
    required int eventId,
    String? accessKey,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          ApiPaths.eventLeave(eventId),
          token: token,
          query: <String, dynamic>{
            if ((accessKey ?? '').trim().isNotEmpty)
              'eventKey': accessKey!.trim(),
          },
          decoder: (_) {},
        );
  }

  /// likeEvent likes event.

  Future<EventLikeStatus> likeEvent({
    required String token,
    required int eventId,
    String? accessKey,
  }) {
    return _ref.read(apiClientProvider).post<EventLikeStatus>(
          ApiPaths.eventLike(eventId),
          token: token,
          query: <String, dynamic>{
            if ((accessKey ?? '').trim().isNotEmpty)
              'eventKey': accessKey!.trim(),
          },
          decoder: EventLikeStatus.fromJson,
        );
  }

  /// unlikeEvent removes like from event.

  Future<EventLikeStatus> unlikeEvent({
    required String token,
    required int eventId,
    String? accessKey,
  }) {
    return _ref.read(apiClientProvider).delete<EventLikeStatus>(
          ApiPaths.eventLike(eventId),
          token: token,
          query: <String, dynamic>{
            if ((accessKey ?? '').trim().isNotEmpty)
              'eventKey': accessKey!.trim(),
          },
          decoder: EventLikeStatus.fromJson,
        );
  }

  /// setFeedPriorityAsAdmin sets feed priority as admin.

  Future<void> setFeedPriorityAsAdmin({
    required String token,
    required int eventId,
    required bool enabled,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          ApiPaths.eventPromote(eventId),
          token: token,
          body: enabled
              ? <String, dynamic>{
                  'promotedUntil': '2099-12-31T23:59:59Z',
                }
              : <String, dynamic>{
                  'clear': true,
                },
          decoder: (_) {},
        );
  }

  /// updateEventAsAdmin updates event as admin.

  Future<void> updateEventAsAdmin({
    required String token,
    required int eventId,
    required UpdateEventAdminPayload payload,
  }) {
    return _ref.read(apiClientProvider).patch<void>(
          ApiPaths.adminEventById(eventId),
          token: token,
          body: payload.toJson(),
          decoder: (_) {},
        );
  }

  /// getComments returns comments.

  Future<List<EventComment>> getComments({
    required String token,
    required int eventId,
    int limit = 100,
    int offset = 0,
    String? accessKey,
  }) {
    return _ref.read(apiClientProvider).get<List<EventComment>>(
          '${ApiPaths.eventById(eventId)}/comments',
          token: token,
          query: <String, dynamic>{
            'limit': limit,
            'offset': offset,
            if ((accessKey ?? '').trim().isNotEmpty)
              'eventKey': accessKey!.trim(),
          },
          decoder: (data) => asList(data).map(EventComment.fromJson).toList(),
        );
  }

  /// addComment handles add comment.

  Future<EventComment> addComment({
    required String token,
    required int eventId,
    required String body,
    String? accessKey,
  }) {
    return _ref.read(apiClientProvider).post<EventComment>(
      '${ApiPaths.eventById(eventId)}/comments',
      token: token,
      query: <String, dynamic>{
        if ((accessKey ?? '').trim().isNotEmpty) 'eventKey': accessKey!.trim(),
      },
      body: <String, dynamic>{'body': body.trim()},
      decoder: (data) {
        final map = asMap(data);
        return EventComment.fromJson(map['comment']);
      },
    );
  }

  /// deleteCommentAsAdmin deletes comment as admin.

  Future<void> deleteCommentAsAdmin({
    required String token,
    required int commentId,
  }) {
    return _ref.read(apiClientProvider).delete<void>(
          ApiPaths.adminCommentById(commentId),
          token: token,
          decoder: (_) {},
        );
  }

  /// deleteEventAsAdmin deletes event as admin.

  Future<void> deleteEventAsAdmin({
    required String token,
    required int eventId,
  }) {
    return _ref.read(apiClientProvider).delete<void>(
          ApiPaths.adminEventById(eventId),
          token: token,
          decoder: (_) {},
        );
  }

  /// presignMedia handles presign media.

  Future<PresignResponse> presignMedia({
    required String token,
    required String fileName,
    required String contentType,
    required int sizeBytes,
  }) {
    return _ref.read(apiClientProvider).post<PresignResponse>(
          ApiPaths.mediaPresign,
          token: token,
          body: <String, dynamic>{
            'fileName': fileName,
            'contentType': contentType,
            'sizeBytes': sizeBytes,
          },
          decoder: PresignResponse.fromJson,
        );
  }

  /// uploadPresigned handles upload presigned.

  Future<void> uploadPresigned({
    required String uploadUrl,
    required Uint8List bytes,
    required String contentType,
  }) {
    return _ref.read(apiClientProvider).putBytes(
          uploadUrl,
          bytes: bytes,
          contentType: contentType,
        );
  }

  /// uploadMedia handles upload media.

  Future<String> uploadMedia({
    required String token,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) {
    return _ref.read(apiClientProvider).postMultipart<String>(
          ApiPaths.mediaUpload,
          token: token,
          fileFieldName: 'file',
          fileName: fileName,
          bytes: bytes,
          contentType: contentType,
          decoder: (data) => asString(asMap(data)['fileUrl']),
        );
  }

  /// getReferralCode returns referral code.

  Future<ReferralCodeResponse> getReferralCode({required String token}) {
    return _ref.read(apiClientProvider).get<ReferralCodeResponse>(
          ApiPaths.referralCode,
          token: token,
          decoder: ReferralCodeResponse.fromJson,
        );
  }
}

final eventsRepositoryProvider =

    /// EventsRepository handles events repository.
    Provider<EventsRepository>((ref) => EventsRepository(ref));
