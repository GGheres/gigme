import 'package:flutter/foundation.dart';

/// buildEventShareUrl builds event share url.

String buildEventShareUrl({
  required int eventId,
  String? eventKey,
  String? refCode,
  required String botUsername,
}) {
  final safeKey = _sanitize(eventKey, 64);
  final safeRef = _sanitize(refCode, 32);

  final normalizedBot = botUsername.trim().replaceAll('@', '');
  if (normalizedBot.isNotEmpty) {
    final startParam = _buildStartParam(eventId, safeKey, safeRef);
    final encoded = Uri.encodeComponent(startParam);
    return 'https://t.me/$normalizedBot?startapp=$encoded';
  }

  if (kIsWeb) {
    final uri = Uri.base.replace(queryParameters: {
      ...Uri.base.queryParameters,
      'eventId': '$eventId',
      if (safeKey != null) 'eventKey': safeKey,
      if (safeRef != null) 'refCode': safeRef,
    });
    return uri.toString();
  }

  return 'event:$eventId';
}

/// _buildStartParam builds start param.

String _buildStartParam(int eventId, String? key, String? refCode) {
  final keyPart = (key != null && key.isNotEmpty) ? '_$key' : '';
  final refPart = (refCode != null && refCode.isNotEmpty) ? '__r_$refCode' : '';
  return 'e_$eventId$keyPart$refPart';
}

/// _sanitize handles internal sanitize behavior.

String? _sanitize(String? raw, int max) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty || value.length > max) return null;
  return value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
}
