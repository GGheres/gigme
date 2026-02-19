import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/json_utils.dart';

class CreateEventDraft {
  CreateEventDraft({
    required this.title,
    required this.description,
    required this.capacity,
    required this.contactTelegram,
    required this.contactWhatsapp,
    required this.contactWechat,
    required this.contactMessenger,
    required this.contactSnapchat,
    required this.startsAt,
    required this.endsAt,
    required this.selectedPoint,
    required this.isPrivate,
    required this.filters,
    required this.mediaUrls,
  });

  factory CreateEventDraft.fromJson(dynamic json) {
    final map = asMap(json);
    final lat = map['lat'];
    final lng = map['lng'];
    final hasPoint = lat != null && lng != null;

    return CreateEventDraft(
      title: asString(map['title']),
      description: asString(map['description']),
      capacity: asString(map['capacity']),
      contactTelegram: asString(map['contactTelegram']),
      contactWhatsapp: asString(map['contactWhatsapp']),
      contactWechat: asString(map['contactWechat']),
      contactMessenger: asString(map['contactMessenger']),
      contactSnapchat: asString(map['contactSnapchat']),
      startsAt: asDateTime(map['startsAt']),
      endsAt: asDateTime(map['endsAt']),
      selectedPoint: hasPoint ? LatLng(asDouble(lat), asDouble(lng)) : null,
      isPrivate: asBool(map['isPrivate']),
      filters: asList(map['filters'])
          .map((item) => asString(item).trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(),
      mediaUrls: asList(map['mediaUrls'])
          .map((item) => asString(item).trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(),
    );
  }

  final String title;
  final String description;
  final String capacity;
  final String contactTelegram;
  final String contactWhatsapp;
  final String contactWechat;
  final String contactMessenger;
  final String contactSnapchat;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final LatLng? selectedPoint;
  final bool isPrivate;
  final List<String> filters;
  final List<String> mediaUrls;

  bool get hasMeaningfulData {
    final hasText = title.trim().isNotEmpty ||
        description.trim().isNotEmpty ||
        capacity.trim().isNotEmpty ||
        contactTelegram.trim().isNotEmpty ||
        contactWhatsapp.trim().isNotEmpty ||
        contactWechat.trim().isNotEmpty ||
        contactMessenger.trim().isNotEmpty ||
        contactSnapchat.trim().isNotEmpty;

    return hasText ||
        startsAt != null ||
        endsAt != null ||
        isPrivate ||
        filters.isNotEmpty ||
        mediaUrls.isNotEmpty;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'capacity': capacity.trim(),
      'contactTelegram': contactTelegram.trim(),
      'contactWhatsapp': contactWhatsapp.trim(),
      'contactWechat': contactWechat.trim(),
      'contactMessenger': contactMessenger.trim(),
      'contactSnapchat': contactSnapchat.trim(),
      if (startsAt != null) 'startsAt': startsAt!.toIso8601String(),
      if (endsAt != null) 'endsAt': endsAt!.toIso8601String(),
      if (selectedPoint != null) ...<String, dynamic>{
        'lat': selectedPoint!.latitude,
        'lng': selectedPoint!.longitude,
      },
      'isPrivate': isPrivate,
      'filters': filters,
      'mediaUrls': mediaUrls,
    };
  }
}

class CreateEventDraftStore {
  static const String _storageKey = 'gigme_create_event_draft';

  Future<CreateEventDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      final draft = CreateEventDraft.fromJson(decoded);
      if (!draft.hasMeaningfulData) return null;
      return draft;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(CreateEventDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (!draft.hasMeaningfulData) {
      await prefs.remove(_storageKey);
      return;
    }
    await prefs.setString(_storageKey, jsonEncode(draft.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
