import 'package:flutter/widgets.dart';

import 'telegram_auth_embed_stub.dart'
    if (dart.library.html) 'telegram_auth_embed_web.dart' as impl;

typedef TelegramAuthInitDataCallback = void Function(String initData);

/// buildTelegramAuthEmbed builds telegram auth embed.

Widget? buildTelegramAuthEmbed({
  required Uri helperUri,
  required TelegramAuthInitDataCallback onInitData,
}) {
  return impl.buildTelegramAuthEmbed(
    helperUri: helperUri,
    onInitData: onInitData,
  );
}
