// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

typedef VkAuthCodeCallback = void Function(
  String code,
  String state,
  String deviceId,
);
typedef VkAuthErrorCallback = void Function(String errorMessage);

int _vkEmbedViewSeed = 0;

/// buildVkAuthEmbed builds vk auth embed.

Widget? buildVkAuthEmbed({
  required Uri helperUri,
  required VkAuthCodeCallback onAuthCode,
  required VkAuthErrorCallback onError,
}) {
  return _VkAuthEmbedFrame(
    helperUri: helperUri,
    onAuthCode: onAuthCode,
    onError: onError,
  );
}

/// _VkAuthEmbedFrame represents vk auth embed frame.

class _VkAuthEmbedFrame extends StatefulWidget {
  /// _VkAuthEmbedFrame handles vk auth embed frame.
  const _VkAuthEmbedFrame({
    required this.helperUri,
    required this.onAuthCode,
    required this.onError,
  });

  final Uri helperUri;
  final VkAuthCodeCallback onAuthCode;
  final VkAuthErrorCallback onError;

  /// createState creates state.

  @override
  State<_VkAuthEmbedFrame> createState() => _VkAuthEmbedFrameState();
}

/// _VkAuthEmbedFrameState represents vk auth embed frame state.

class _VkAuthEmbedFrameState extends State<_VkAuthEmbedFrame> {
  late final String _viewType;
  late final html.IFrameElement _iframe;
  late final String _expectedOrigin;
  StreamSubscription<html.MessageEvent>? _messageSub;
  bool _completed = false;

  /// initState handles init state.

  @override
  void initState() {
    super.initState();

    final frameUri = _withEmbedFlag(widget.helperUri);
    _viewType = 'space_vk_auth_embed_${_vkEmbedViewSeed++}';
    _iframe = html.IFrameElement()
      ..src = frameUri.toString()
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = 'transparent'
      ..setAttribute('allow', 'clipboard-read; clipboard-write')
      ..setAttribute(
        'sandbox',
        'allow-forms allow-modals allow-popups allow-popups-to-escape-sandbox allow-same-origin allow-scripts',
      );
    _expectedOrigin = frameUri.origin;

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (_) => _iframe,
    );

    _messageSub = html.window.onMessage.listen(_handleMessage);
  }

  /// dispose releases resources held by this instance.

  @override
  void dispose() {
    _messageSub?.cancel();
    _iframe.src = 'about:blank';
    super.dispose();
  }

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }

  /// _handleMessage handles message.

  void _handleMessage(html.MessageEvent event) {
    if (!mounted) return;
    if (event.origin.isNotEmpty &&
        event.origin != 'null' &&
        event.origin != _expectedOrigin) {
      return;
    }

    final payload = _parseMessagePayload(event.data);
    if (payload == null) return;

    final messageType = '${payload['type'] ?? ''}'.trim();
    if (messageType == 'space.vk.auth.error') {
      final message = '${payload['error'] ?? ''}'.trim();
      widget.onError(
        message.isEmpty ? 'VK auth failed in embedded widget' : message,
      );
      return;
    }

    if (messageType != 'space.vk.auth' || _completed) {
      return;
    }

    final code = '${payload['code'] ?? ''}'.trim();
    final state = '${payload['state'] ?? ''}'.trim();
    final deviceId = '${payload['deviceId'] ?? ''}'.trim();
    if (code.isEmpty || state.isEmpty || deviceId.isEmpty) {
      widget.onError('VK widget returned incomplete auth payload');
      return;
    }

    _completed = true;
    widget.onAuthCode(code, state, deviceId);
  }

  /// _withEmbedFlag configures embed flag.

  Uri _withEmbedFlag(Uri uri) {
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'embed': '1',
      },
    );
  }

  /// _parseMessagePayload parses message payload.

  Map<String, dynamic>? _parseMessagePayload(dynamic messageData) {
    if (messageData is String) {
      return _decodeJsonObject(messageData);
    }
    if (messageData is Map) {
      return messageData.map((key, value) => MapEntry('$key', value));
    }

    final raw = '$messageData'.trim();
    if (!raw.startsWith('{') || !raw.endsWith('}')) {
      return null;
    }
    return _decodeJsonObject(raw);
  }

  /// _decodeJsonObject decodes json object.

  Map<String, dynamic>? _decodeJsonObject(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, val) => MapEntry('$key', val));
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
