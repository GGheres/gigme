class VkAuthCredentials {
  const VkAuthCredentials({
    required this.accessToken,
    this.userId,
  });

  final String accessToken;
  final int? userId;
}

Uri? buildVkOAuthAuthorizeUri({
  required String appId,
  required Uri redirectUri,
  String? state,
}) {
  final clientId = appId.trim();
  if (clientId.isEmpty) return null;

  final queryParameters = <String, String>{
    'client_id': clientId,
    'redirect_uri': redirectUri.toString(),
    'response_type': 'token',
    'scope': 'email',
    'display': 'popup',
    'v': '5.199',
  };
  final stateValue = (state ?? '').trim();
  if (stateValue.isNotEmpty) {
    queryParameters['state'] = stateValue;
  }

  return Uri.https('oauth.vk.com', '/authorize', queryParameters);
}

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

String? parseVkAuthErrorFromUri(Uri? uri) {
  if (uri == null) return null;
  final params = _collectUriAuthParams(uri);

  final hasVkMarker = (params['vk_auth'] ?? '').trim() == '1' ||
      params.containsKey('access_token') ||
      params.containsKey('vk_access_token') ||
      params.containsKey('user_id') ||
      params.containsKey('vk_user_id');
  if (!hasVkMarker) return null;

  final error = (params['error'] ?? '').trim();
  if (error.isEmpty) return null;
  final description = (params['error_description'] ?? '').trim();
  if (description.isEmpty) return error;
  return '$error: $description';
}

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
