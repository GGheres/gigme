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

class CreateEventPayload {
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
      if ((contactTelegram ?? '').trim().isNotEmpty) 'contactTelegram': contactTelegram!.trim(),
      if ((contactWhatsapp ?? '').trim().isNotEmpty) 'contactWhatsapp': contactWhatsapp!.trim(),
      if ((contactWechat ?? '').trim().isNotEmpty) 'contactWechat': contactWechat!.trim(),
      if ((contactFbMessenger ?? '').trim().isNotEmpty) 'contactFbMessenger': contactFbMessenger!.trim(),
      if ((contactSnapchat ?? '').trim().isNotEmpty) 'contactSnapchat': contactSnapchat!.trim(),
      if ((addressLabel ?? '').trim().isNotEmpty) 'addressLabel': addressLabel!.trim(),
    };
  }
}

class EventsRepository {
  EventsRepository(this._ref);

  final Ref _ref;

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

  Future<EventDetail> getEvent({
    required String token,
    required int eventId,
    String? accessKey,
  }) {
    return _ref.read(apiClientProvider).get<EventDetail>(
          ApiPaths.eventById(eventId),
          token: token,
          query: <String, dynamic>{
            if ((accessKey ?? '').trim().isNotEmpty) 'eventKey': accessKey!.trim(),
          },
          decoder: EventDetail.fromJson,
          retry: false,
        );
  }

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

  Future<void> joinEvent({
    required String token,
    required int eventId,
    String? accessKey,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          ApiPaths.eventJoin(eventId),
          token: token,
          query: <String, dynamic>{
            if ((accessKey ?? '').trim().isNotEmpty) 'eventKey': accessKey!.trim(),
          },
          decoder: (_) {},
        );
  }

  Future<void> leaveEvent({
    required String token,
    required int eventId,
    String? accessKey,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          ApiPaths.eventLeave(eventId),
          token: token,
          query: <String, dynamic>{
            if ((accessKey ?? '').trim().isNotEmpty) 'eventKey': accessKey!.trim(),
          },
          decoder: (_) {},
        );
  }

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
            if ((accessKey ?? '').trim().isNotEmpty) 'eventKey': accessKey!.trim(),
          },
          decoder: (data) => asList(data).map(EventComment.fromJson).toList(),
        );
  }

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

  Future<ReferralCodeResponse> getReferralCode({required String token}) {
    return _ref.read(apiClientProvider).get<ReferralCodeResponse>(
          ApiPaths.referralCode,
          token: token,
          decoder: ReferralCodeResponse.fromJson,
        );
  }
}

final eventsRepositoryProvider = Provider<EventsRepository>((ref) => EventsRepository(ref));
