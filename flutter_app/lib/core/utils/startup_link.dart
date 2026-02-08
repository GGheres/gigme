import 'package:flutter/foundation.dart';

import '../../integrations/telegram/telegram_web_app_bridge.dart';

class StartupLink {
  const StartupLink({
    this.eventId,
    this.eventKey,
    this.refCode,
  });

  final int? eventId;
  final String? eventKey;
  final String? refCode;

  bool get hasEvent => eventId != null && eventId! > 0;

  StartupLink copyWith({
    int? eventId,
    String? eventKey,
    String? refCode,
  }) {
    return StartupLink(
      eventId: eventId ?? this.eventId,
      eventKey: eventKey ?? this.eventKey,
      refCode: refCode ?? this.refCode,
    );
  }
}

class StartupLinkParser {
  static StartupLink parse() {
    final fromLocation = _fromUri(Uri.base);
    if (fromLocation.hasEvent) {
      return fromLocation;
    }

    if (kIsWeb) {
      final startParam = TelegramWebAppBridge.startParam();
      final fromTelegram = _fromStartParam(startParam);
      if (fromTelegram.hasEvent) {
        return fromTelegram;
      }
    }

    return const StartupLink();
  }

  static StartupLink _fromUri(Uri uri) {
    final eventId = _parseEventId(uri.queryParameters['eventId'] ?? uri.queryParameters['event']);
    if (eventId == null) return const StartupLink();

    return StartupLink(
      eventId: eventId,
      eventKey: _sanitizeKey(uri.queryParameters['eventKey'] ?? uri.queryParameters['key']),
      refCode: _sanitizeRef(uri.queryParameters['refCode'] ?? uri.queryParameters['ref']),
    );
  }

  static StartupLink _fromStartParam(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return const StartupLink();

    final referralMatch =
        RegExp(r'^e_(\d+)(?:_([a-zA-Z0-9_-]+))?(?:__r_([a-zA-Z0-9_-]+))?$', caseSensitive: false).firstMatch(raw);
    if (referralMatch != null) {
      final eventId = _parseEventId(referralMatch.group(1));
      if (eventId == null) return const StartupLink();
      return StartupLink(
        eventId: eventId,
        eventKey: _sanitizeKey(referralMatch.group(2)),
        refCode: _sanitizeRef(referralMatch.group(3)),
      );
    }

    final legacy = RegExp(r'^event_(\d+)(?:_([a-zA-Z0-9_-]+))?$', caseSensitive: false).firstMatch(raw);
    if (legacy != null) {
      final eventId = _parseEventId(legacy.group(1));
      if (eventId == null) return const StartupLink();
      return StartupLink(eventId: eventId, eventKey: _sanitizeKey(legacy.group(2)));
    }

    final fallback = RegExp(r'\d+').firstMatch(raw);
    final eventId = _parseEventId(fallback?.group(0));
    if (eventId == null) return const StartupLink();
    return StartupLink(eventId: eventId);
  }

  static int? _parseEventId(String? raw) {
    final value = int.tryParse((raw ?? '').trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  static String? _sanitizeKey(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty || value.length > 64) return null;
    return value;
  }

  static String? _sanitizeRef(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty || value.length > 32) return null;
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (cleaned.isEmpty) return null;
    return cleaned;
  }
}
