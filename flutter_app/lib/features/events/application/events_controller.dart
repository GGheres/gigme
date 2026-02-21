import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/event_filters.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/models/event_card.dart';
import '../../../core/models/event_comment.dart';
import '../../../core/models/event_detail.dart';
import '../../../core/models/event_marker.dart';
import '../../../core/network/providers.dart';
import '../../../core/storage/event_access_key_store.dart';
import '../../auth/application/auth_controller.dart';
import '../data/events_repository.dart';

class EventsState {
  factory EventsState.initial() => const EventsState(
        loading: false,
        refreshing: false,
        error: null,
        feed: <EventCard>[],
        markers: <EventMarker>[],
        activeFilters: <String>[],
        nearbyOnly: false,
        radiusMeters: kNearbyRadiusMeters,
        lastCenter: null,
      );
  const EventsState({
    required this.loading,
    required this.refreshing,
    required this.error,
    required this.feed,
    required this.markers,
    required this.activeFilters,
    required this.nearbyOnly,
    required this.radiusMeters,
    required this.lastCenter,
  });

  final bool loading;
  final bool refreshing;
  final String? error;
  final List<EventCard> feed;
  final List<EventMarker> markers;
  final List<String> activeFilters;
  final bool nearbyOnly;
  final int radiusMeters;
  final LatLng? lastCenter;

  EventsState copyWith({
    bool? loading,
    bool? refreshing,
    String? error,
    List<EventCard>? feed,
    List<EventMarker>? markers,
    List<String>? activeFilters,
    bool? nearbyOnly,
    int? radiusMeters,
    LatLng? lastCenter,
  }) {
    return EventsState(
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      error: error,
      feed: feed ?? this.feed,
      markers: markers ?? this.markers,
      activeFilters: activeFilters ?? this.activeFilters,
      nearbyOnly: nearbyOnly ?? this.nearbyOnly,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      lastCenter: lastCenter ?? this.lastCenter,
    );
  }
}

class EventsController extends ChangeNotifier {
  EventsController({
    required this.ref,
    required this.repository,
    required this.accessKeyStore,
  }) {
    unawaited(_loadAccessKeys());
  }

  final Ref ref;
  final EventsRepository repository;
  final EventAccessKeyStore accessKeyStore;

  EventsState _state = EventsState.initial();
  EventsState get state => _state;

  Map<int, String> _eventAccessKeys = <int, String>{};
  Map<int, String> get eventAccessKeys => _eventAccessKeys;

  String? get _token => ref.read(authControllerProvider).state.token;

  Future<void> _loadAccessKeys() async {
    _eventAccessKeys = await accessKeyStore.load();
    notifyListeners();
  }

  Future<void> refresh(
      {required LatLng center, bool forceLoading = false}) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) return;

    _state = _state.copyWith(
      loading: forceLoading || _state.feed.isEmpty,
      refreshing: true,
      error: null,
      lastCenter: center,
    );
    notifyListeners();

    try {
      unawaited(
        repository.updateLocation(
            token: token, lat: center.latitude, lng: center.longitude),
      );

      final accessKeys = _eventAccessKeys.values.toList(growable: false);
      final radius = _state.nearbyOnly ? _state.radiusMeters : 0;
      final filters = _state.activeFilters;

      final results = await Future.wait<dynamic>([
        repository.getNearby(
          token: token,
          lat: center.latitude,
          lng: center.longitude,
          radiusM: radius,
          filters: filters,
          accessKeys: accessKeys,
        ),
        repository.getFeed(
          token: token,
          lat: center.latitude,
          lng: center.longitude,
          radiusM: radius,
          filters: filters,
          accessKeys: accessKeys,
        ),
      ]);

      final markers = (results[0] as List<EventMarker>);
      final feed = _sortFeed(results[1] as List<EventCard>);

      _state = _state.copyWith(
        loading: false,
        refreshing: false,
        error: null,
        markers: markers,
        feed: feed,
      );
      notifyListeners();
    } catch (error) {
      _state = _state.copyWith(
        loading: false,
        refreshing: false,
        error: '$error',
      );
      notifyListeners();
    }
  }

  void toggleFilter(String filterId) {
    final current = <String>[..._state.activeFilters];
    if (current.contains(filterId)) {
      current.remove(filterId);
    } else {
      current.add(filterId);
    }
    _state = _state.copyWith(activeFilters: current, error: null);
    notifyListeners();
  }

  void clearFilters() {
    _state = _state.copyWith(
      activeFilters: <String>[],
      nearbyOnly: false,
      error: null,
    );
    notifyListeners();
  }

  void setNearbyOnly(bool enabled) {
    _state = _state.copyWith(nearbyOnly: enabled, error: null);
    notifyListeners();
  }

  String accessKeyFor(int eventId, {String? fallback}) {
    if ((fallback ?? '').trim().isNotEmpty) return fallback!.trim();
    return _eventAccessKeys[eventId] ?? '';
  }

  Future<void> rememberAccessKey(int eventId, String accessKey) async {
    final key = accessKey.trim();
    if (eventId <= 0 || key.isEmpty) return;
    _eventAccessKeys = <int, String>{..._eventAccessKeys, eventId: key};
    await accessKeyStore.save(_eventAccessKeys);
    notifyListeners();
  }

  Future<EventDetail> loadEventDetail(
      {required int eventId, String? accessKey}) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }

    final detail = await repository.getEvent(
      token: token,
      eventId: eventId,
      accessKey: accessKeyFor(eventId, fallback: accessKey),
    );

    final key = detail.event.accessKey.trim();
    if (key.isNotEmpty) {
      await rememberAccessKey(eventId, key);
    }

    _upsertFeedItem(detail.event);
    _upsertMarkerFromEvent(detail.event);

    return detail;
  }

  Future<void> joinEvent({required int eventId, String? accessKey}) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }
    await repository.joinEvent(
      token: token,
      eventId: eventId,
      accessKey: accessKeyFor(eventId, fallback: accessKey),
    );
  }

  Future<void> leaveEvent({required int eventId, String? accessKey}) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }
    await repository.leaveEvent(
      token: token,
      eventId: eventId,
      accessKey: accessKeyFor(eventId, fallback: accessKey),
    );
  }

  Future<EventLikeStatus> toggleLike({
    required int eventId,
    required bool isLiked,
    String? accessKey,
  }) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }

    final next = isLiked
        ? await repository.unlikeEvent(
            token: token,
            eventId: eventId,
            accessKey: accessKeyFor(eventId, fallback: accessKey),
          )
        : await repository.likeEvent(
            token: token,
            eventId: eventId,
            accessKey: accessKeyFor(eventId, fallback: accessKey),
          );

    final feedIndex = _state.feed.indexWhere((item) => item.id == eventId);
    if (feedIndex >= 0) {
      final updatedFeed = [..._state.feed];
      updatedFeed[feedIndex] = updatedFeed[feedIndex].copyWith(
        likesCount: next.likesCount,
        isLiked: next.isLiked,
      );
      _state = _state.copyWith(feed: updatedFeed);
      notifyListeners();
    }

    return next;
  }

  Future<void> setFeedPriorityAsAdmin({
    required int eventId,
    required bool enabled,
  }) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }
    await repository.setFeedPriorityAsAdmin(
      token: token,
      eventId: eventId,
      enabled: enabled,
    );
  }

  Future<void> updateEventAsAdmin({
    required int eventId,
    required UpdateEventAdminPayload payload,
  }) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }
    await repository.updateEventAsAdmin(
      token: token,
      eventId: eventId,
      payload: payload,
    );
  }

  Future<List<EventComment>> loadComments({
    required int eventId,
    String? accessKey,
  }) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }
    return repository.getComments(
      token: token,
      eventId: eventId,
      accessKey: accessKeyFor(eventId, fallback: accessKey),
    );
  }

  Future<EventComment> addComment({
    required int eventId,
    required String body,
    String? accessKey,
  }) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }
    return repository.addComment(
      token: token,
      eventId: eventId,
      body: body,
      accessKey: accessKeyFor(eventId, fallback: accessKey),
    );
  }

  Future<void> deleteCommentAsAdmin({
    required int commentId,
  }) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }
    await repository.deleteCommentAsAdmin(
      token: token,
      commentId: commentId,
    );
  }

  Future<void> deleteEventAsAdmin({
    required int eventId,
  }) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }
    await repository.deleteEventAsAdmin(
      token: token,
      eventId: eventId,
    );
  }

  Future<String> uploadImage({
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }

    final presign = await repository.presignMedia(
      token: token,
      fileName: fileName,
      contentType: contentType,
      sizeBytes: bytes.lengthInBytes,
    );

    try {
      await repository.uploadPresigned(
        uploadUrl: presign.uploadUrl,
        bytes: bytes,
        contentType: contentType,
      );
    } on AppException catch (error) {
      if (!_shouldFallbackToApiUpload(error)) {
        rethrow;
      }
      return repository.uploadMedia(
        token: token,
        fileName: fileName,
        contentType: contentType,
        bytes: bytes,
      );
    }

    return presign.fileUrl;
  }

  bool _shouldFallbackToApiUpload(AppException error) {
    if (error.statusCode != null) return false;
    return const <String>{
      'connectionError',
      'connectionTimeout',
      'sendTimeout',
      'receiveTimeout',
    }.contains(error.code);
  }

  Future<int> createEvent(CreateEventPayload payload) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) {
      throw StateError('Missing auth token');
    }

    final created =
        await repository.createEvent(token: token, payload: payload);
    if (created.accessKey.trim().isNotEmpty) {
      await rememberAccessKey(created.eventId, created.accessKey);
    }
    return created.eventId;
  }

  Future<String?> loadReferralCode() async {
    final token = _token;
    if (token == null || token.trim().isEmpty) return null;
    final code = await repository.getReferralCode(token: token);
    if (code.code.trim().isEmpty) return null;
    return code.code.trim();
  }

  void _upsertFeedItem(EventCard event) {
    final next = [..._state.feed];
    final index = next.indexWhere((item) => item.id == event.id);
    if (index >= 0) {
      next[index] = event;
    } else {
      next.add(event);
    }
    _state = _state.copyWith(feed: _sortFeed(next));
    notifyListeners();
  }

  void _upsertMarkerFromEvent(EventCard event) {
    final next = [..._state.markers];
    final marker = EventMarker(
      id: event.id,
      title: event.title,
      startsAt: event.startsAt,
      lat: event.lat,
      lng: event.lng,
      isPromoted: event.isFeatured,
      filters: event.filters,
    );
    final index = next.indexWhere((item) => item.id == event.id);
    if (index >= 0) {
      next[index] = marker;
    } else {
      next.add(marker);
    }
    _state = _state.copyWith(markers: next);
    notifyListeners();
  }

  List<EventCard> _sortFeed(List<EventCard> items) {
    final now = DateTime.now();
    return [...items]..sort((a, b) {
        final aPromoted = a.promotedUntil?.isAfter(now) ?? false;
        final bPromoted = b.promotedUntil?.isAfter(now) ?? false;
        if (aPromoted != bPromoted) return aPromoted ? -1 : 1;

        final aStarts = a.startsAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bStarts = b.startsAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aStarts.compareTo(bStarts);
      });
  }

  EventCard? feedEventById(int eventId) =>
      _state.feed.firstWhereOrNull((item) => item.id == eventId);
}

final eventsControllerProvider =
    ChangeNotifierProvider<EventsController>((ref) {
  final controller = EventsController(
    ref: ref,
    repository: ref.watch(eventsRepositoryProvider),
    accessKeyStore: ref.watch(eventAccessKeyStoreProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
