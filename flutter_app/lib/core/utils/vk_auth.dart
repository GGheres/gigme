import 'dart:convert';

/// VkAuthCredentials represents vk auth credentials.

class VkAuthCredentials {
  /// VkAuthCredentials handles vk auth credentials.
  const VkAuthCredentials({
    required this.accessToken,
    this.userId,
  });

  final String accessToken;
  final int? userId;
}

/// VkAuthCodeCredentials represents vk auth code credentials.

class VkAuthCodeCredentials {
  /// VkAuthCodeCredentials handles vk auth code credentials.
  const VkAuthCodeCredentials({
    required this.code,
    required this.state,
    required this.deviceId,
  });

  final String code;
  final String state;
  final String deviceId;
}

/// extractVkMiniAppLaunchParams extracts vk mini app launch params.

String? extractVkMiniAppLaunchParams(Uri? uri) {
  if (uri == null) return null;

  final hasViewerId =
      uri.queryParameters['vk_user_id']?.trim().isNotEmpty ?? false;
  final hasAppId = uri.queryParameters['vk_app_id']?.trim().isNotEmpty ?? false;
  final hasSign = uri.queryParameters['sign']?.trim().isNotEmpty ?? false;
  if (!hasViewerId || !hasAppId || !hasSign) {
    return null;
  }

  final raw = uri.query.trim();
  if (raw.isEmpty) return null;
  return raw;
}

/// parseVkAuthCredentialsFromUri parses vk auth credentials from uri.

VkAuthCredentials? parseVkAuthCredentialsFromUri(Uri? uri) {
  if (uri == null) return null;
  final params = _collectUriAuthParams(uri);

  final accessToken =
      (params['vk_access_token'] ?? params['access_token'] ?? '').trim();
  if (accessToken.isEmpty) return null;

  final rawUserId = (params['vk_user_id'] ?? params['user_id'] ?? '').trim();
  final parsedUserId = int.tryParse(rawUserId);
  return VkAuthCredentials(
    accessToken: accessToken,
    userId: parsedUserId != null && parsedUserId > 0 ? parsedUserId : null,
  );
}

/// parseVkAuthCodeCredentialsFromUri parses vk auth code credentials from uri.

VkAuthCodeCredentials? parseVkAuthCodeCredentialsFromUri(Uri? uri) {
  if (uri == null) return null;
  final params = _collectUriAuthParams(uri);

  var code = (params['code'] ?? '').trim();
  var state = (params['state'] ?? '').trim();
  var deviceId = (params['device_id'] ?? params['deviceId'] ?? '').trim();

  final payloadRaw = (params['payload'] ?? '').trim();
  if (payloadRaw.isNotEmpty &&
      (code.isEmpty || state.isEmpty || deviceId.isEmpty)) {
    final payload = _parseVkAuthPayload(payloadRaw);
    code = code.isEmpty ? (payload['code'] ?? '').trim() : code;
    state = state.isEmpty ? (payload['state'] ?? '').trim() : state;
    deviceId = deviceId.isEmpty
        ? (payload['device_id'] ?? payload['deviceId'] ?? '').trim()
        : deviceId;
  }

  if (code.isEmpty || deviceId.isEmpty) {
    return null;
  }

  return VkAuthCodeCredentials(
    code: code,
    state: state,
    deviceId: deviceId,
  );
}

/// parseVkAuthErrorFromUri parses vk auth error from uri.

String? parseVkAuthErrorFromUri(Uri? uri) {
  if (uri == null) return null;
  final params = _collectUriAuthParams(uri);
  final error = (params['error'] ?? '').trim();
  if (error.isEmpty) return null;

  final hasVkMarker = (params['vk_auth'] ?? '').trim() == '1' ||
      params.containsKey('access_token') ||
      params.containsKey('vk_access_token') ||
      params.containsKey('code') ||
      params.containsKey('device_id') ||
      params.containsKey('user_id') ||
      params.containsKey('vk_user_id') ||
      params.containsKey('payload') ||
      params.containsKey('state');
  if (!hasVkMarker) return null;

  final description = (params['error_description'] ?? '').trim();
  if (description.isEmpty) return error;
  return '$error: $description';
}

/// _collectUriAuthParams handles collect uri auth params.

Map<String, String> _collectUriAuthParams(Uri uri) {
  final out = <String, String>{...uri.queryParameters};
  final fragment = uri.fragment.trim();
  if (fragment.isEmpty) return out;

  final candidates = <String>{fragment};
  final questionMarkIndex = fragment.indexOf('?');
  if (questionMarkIndex >= 0 && questionMarkIndex < fragment.length - 1) {
    candidates.add(fragment.substring(questionMarkIndex + 1));
  }

  for (final candidate in candidates) {
    try {
      final parsed = Uri.splitQueryString(candidate);
      parsed.forEach((key, value) {
        if (value.trim().isEmpty) return;
        out[key] = value.trim();
      });
    } catch (_) {
      // Ignore malformed fragment values and keep parsed params from query.
    }
  }

  return out;
}

/// _parseVkAuthPayload parses vk auth payload.

Map<String, String> _parseVkAuthPayload(String payloadRaw) {
  final raw = payloadRaw.trim();
  if (raw.isEmpty) return const <String, String>{};

  final direct = _decodePayloadMap(raw);
  if (direct.isNotEmpty) return direct;

  try {
    final decoded = Uri.decodeComponent(raw).trim();
    if (decoded == raw || decoded.isEmpty) {
      return const <String, String>{};
    }
    return _decodePayloadMap(decoded);
  } catch (_) {
    return const <String, String>{};
  }
}

/// _decodePayloadMap decodes payload map.

Map<String, String> _decodePayloadMap(String source) {
  final asJson = _decodeJsonMap(source);
  if (asJson.isNotEmpty) return asJson;

  final normalized = source.replaceAll('-', '+').replaceAll('_', '/');
  final remainder = normalized.length % 4;
  final withPadding = remainder == 0
      ? normalized
      : '$normalized${''.padRight(4 - remainder, '=')}';
  try {
    final decoded = utf8.decode(base64.decode(withPadding));
    return _decodeJsonMap(decoded);
  } catch (_) {
    return const <String, String>{};
  }
}

/// _decodeJsonMap decodes json map.

Map<String, String> _decodeJsonMap(String source) {
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map) return const <String, String>{};

    final out = <String, String>{};
    for (final entry in decoded.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) continue;
      final value = entry.value?.toString().trim() ?? '';
      if (value.isEmpty) continue;
      out[key] = value;
    }
    return out;
  } catch (_) {
    return const <String, String>{};
  }
}
