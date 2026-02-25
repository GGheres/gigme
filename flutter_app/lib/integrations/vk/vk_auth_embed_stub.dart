import 'package:flutter/widgets.dart';

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
  return null;
}
