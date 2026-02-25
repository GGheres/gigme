import 'package:flutter/foundation.dart';

import '../../integrations/telegram/telegram_web_app_bridge.dart';

/// StartupLink represents startup link.

class StartupLink {
  /// StartupLink handles startup link.
  const StartupLink({
    this.eventId,
    this.eventKey,
    this.refCode,
  });

  final int? eventId;
  final String? eventKey;
  final String? refCode;

  /// hasEvent reports whether event exists.

  bool get hasEvent => eventId != null && eventId! > 0;

  /// copyWith handles copy with.

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

/// StartupLinkParser represents startup link parser.

class StartupLinkParser {
  /// parseFromUriForTesting parses from uri for testing.
  @visibleForTesting
  static StartupLink parseFromUriForTesting(Uri uri) => _fromUri(uri);

  /// parseStartParamForTesting parses start param for testing.

  @visibleForTesting
  static StartupLink parseStartParamForTesting(String? value) =>

      /// _fromStartParam handles from start param.
      _fromStartParam(value);

  /// parse parses the provided input.

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

  /// _fromUri handles from uri.

  static StartupLink _fromUri(Uri uri) {
    final params = _mergeLocationParams(uri);
    final eventId = _parseEventId(params['eventId'] ?? params['event']);
    if (eventId != null) {
      return StartupLink(
        eventId: eventId,
        eventKey: _sanitizeKey(params['eventKey'] ?? params['key']),
        refCode: _sanitizeRef(params['refCode'] ?? params['ref']),
      );
    }

    final directStartParam = _extractStartParam(params);
    final fromDirectStartParam = _fromStartParam(directStartParam);
    if (fromDirectStartParam.hasEvent) {
      return fromDirectStartParam;
    }

    final initDataStartParam =
        _extractStartParamFromInitData(params['tgWebAppData']);
    final fromInitDataStartParam = _fromStartParam(initDataStartParam);
    if (fromInitDataStartParam.hasEvent) {
      return fromInitDataStartParam;
    }

    return const StartupLink();
  }

  /// _mergeLocationParams merges location params.

  static Map<String, String> _mergeLocationParams(Uri uri) {
    final merged = <String, String>{
      ..._parseFragmentParams(uri.fragment),
      ...uri.queryParameters,
    };
    return merged;
  }

  /// _parseFragmentParams parses fragment params.

  static Map<String, String> _parseFragmentParams(String fragment) {
    final raw = fragment.trim();
    if (raw.isEmpty) {
      return const <String, String>{};
    }

    final out = <String, String>{};
    void merge(String value) {
      final parsed = _parseQueryLikeString(value);
      if (parsed.isNotEmpty) {
        out.addAll(parsed);
      }
    }

    merge(raw);
    final qIndex = raw.indexOf('?');
    if (qIndex >= 0 && qIndex < raw.length - 1) {
      merge(raw.substring(qIndex + 1));
    }

    return out;
  }

  /// _parseQueryLikeString parses query like string.

  static Map<String, String> _parseQueryLikeString(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      return const <String, String>{};
    }
    if (value.startsWith('?')) {
      value = value.substring(1);
    }
    if (value.isEmpty || !value.contains('=')) {
      return const <String, String>{};
    }

    try {
      return Uri.splitQueryString(value);
    } catch (_) {
      return const <String, String>{};
    }
  }

  /// _extractStartParam extracts start param.

  static String? _extractStartParam(Map<String, String> params) {
    const keys = <String>[
      'startapp',
      'startApp',
      'start_param',
      'startParam',
      'tgWebAppStartParam',
      'tgwebappstartparam',
    ];
    for (final key in keys) {
      final value = (params[key] ?? '').trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  /// _extractStartParamFromInitData extracts start param from init data.

  static String? _extractStartParamFromInitData(String? rawInitData) {
    final value = (rawInitData ?? '').trim();
    if (value.isEmpty) return null;

    Map<String, String>? parsed;
    try {
      parsed = Uri.splitQueryString(value);
    } catch (_) {
      try {
        final decoded = Uri.decodeQueryComponent(value);
        parsed = Uri.splitQueryString(decoded);
      } catch (_) {
        return null;
      }
    }
    if (parsed.isEmpty) return null;
    return _extractStartParam(parsed);
  }

  /// _fromStartParam handles from start param.

  static StartupLink _fromStartParam(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return const StartupLink();

    final parsedEventStartParam = _parseEventStartParam(raw);
    if (parsedEventStartParam.hasEvent) {
      return parsedEventStartParam;
    }

    final legacy =
        RegExp(r'^event_(\d+)(?:_([a-zA-Z0-9_-]+))?$', caseSensitive: false)
            .firstMatch(raw);
    if (legacy != null) {
      final eventId = _parseEventId(legacy.group(1));
      if (eventId == null) return const StartupLink();
      return StartupLink(
          eventId: eventId, eventKey: _sanitizeKey(legacy.group(2)));
    }

    final fallback = RegExp(r'\d+').firstMatch(raw);
    final eventId = _parseEventId(fallback?.group(0));
    if (eventId == null) return const StartupLink();
    return StartupLink(eventId: eventId);
  }

  /// _parseEventStartParam parses event start param.

  static StartupLink _parseEventStartParam(String raw) {
    if (!raw.toLowerCase().startsWith('e_')) {
      return const StartupLink();
    }

    final payload = raw.substring(2);
    if (payload.isEmpty) {
      return const StartupLink();
    }

    String? refCodeRaw;
    var eventAndKey = payload;
    final refSeparatorIndex = payload.indexOf('__r_');
    if (refSeparatorIndex >= 0) {
      refCodeRaw = payload.substring(refSeparatorIndex + 4);
      eventAndKey = payload.substring(0, refSeparatorIndex);
    }

    final keySeparatorIndex = eventAndKey.indexOf('_');
    late final String eventIdRaw;
    String? eventKeyRaw;
    if (keySeparatorIndex < 0) {
      eventIdRaw = eventAndKey;
    } else {
      eventIdRaw = eventAndKey.substring(0, keySeparatorIndex);
      eventKeyRaw = eventAndKey.substring(keySeparatorIndex + 1);
    }

    final eventId = _parseEventId(eventIdRaw);
    if (eventId == null) {
      return const StartupLink();
    }

    return StartupLink(
      eventId: eventId,
      eventKey: _sanitizeKey(eventKeyRaw),
      refCode: _sanitizeRef(refCodeRaw),
    );
  }

  /// _parseEventId parses event id.

  static int? _parseEventId(String? raw) {
    final value = int.tryParse((raw ?? '').trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  /// _sanitizeKey handles sanitize key.

  static String? _sanitizeKey(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty || value.length > 64) return null;
    return value;
  }

  /// _sanitizeRef handles sanitize ref.

  static String? _sanitizeRef(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty || value.length > 32) return null;
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (cleaned.isEmpty) return null;
    return cleaned;
  }
}
