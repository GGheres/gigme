import 'package:flutter/widgets.dart';

import 'vk_auth_embed_stub.dart' if (dart.library.html) 'vk_auth_embed_web.dart'
    as impl;

typedef VkAuthCodeCallback = void Function(
  String code,
  String state,
  String deviceId,
);
typedef VkAuthErrorCallback = void Function(String errorMessage);

/// buildVkAuthEmbed builds vk auth embed.

Widget? buildVkAuthEmbed({
  required Uri helperUri,
  required VkAuthCodeCallback onAuthCode,
  required VkAuthErrorCallback onError,
}) {
  return impl.buildVkAuthEmbed(
    helperUri: helperUri,
    onAuthCode: onAuthCode,
    onError: onError,
  );
}
