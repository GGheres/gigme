// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

typedef TelegramAuthInitDataCallback = void Function(String initData);

int _embedViewSeed = 0;

Widget? buildTelegramAuthEmbed({
  required Uri helperUri,
  required TelegramAuthInitDataCallback onInitData,
}) {
  return _TelegramAuthEmbedFrame(
    helperUri: helperUri,
    onInitData: onInitData,
  );
}

class _TelegramAuthEmbedFrame extends StatefulWidget {
  const _TelegramAuthEmbedFrame({
    required this.helperUri,
    required this.onInitData,
  });

  final Uri helperUri;
  final TelegramAuthInitDataCallback onInitData;

  @override
  State<_TelegramAuthEmbedFrame> createState() =>
      _TelegramAuthEmbedFrameState();
}

class _TelegramAuthEmbedFrameState extends State<_TelegramAuthEmbedFrame> {
  late final String _viewType;
  late final html.IFrameElement _iframe;
  late final String _expectedOrigin;
  StreamSubscription<html.MessageEvent>? _messageSub;
  bool _completed = false;

  @override
  void initState() {
    super.initState();

    final frameUri = _withEmbedFlag(widget.helperUri);
    _viewType = 'space_telegram_auth_embed_${_embedViewSeed++}';
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

  @override
  void dispose() {
    _messageSub?.cancel();
    _iframe.src = 'about:blank';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }

  void _handleMessage(html.MessageEvent event) {
    if (_completed || !mounted) return;
    if (event.origin.isNotEmpty &&
        event.origin != 'null' &&
        event.origin != _expectedOrigin) {
      return;
    }

    final initData = _parseInitDataFromMessage(event.data);
    if (initData == null) return;

    _completed = true;
    widget.onInitData(initData);
  }

  Uri _withEmbedFlag(Uri uri) {
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'embed': '1',
      },
    );
  }

  String? _parseInitDataFromMessage(dynamic messageData) {
    Map<String, dynamic>? payload;

    if (messageData is String) {
      try {
        final decoded = jsonDecode(messageData);
        if (decoded is Map<String, dynamic>) {
          payload = decoded;
        }
      } catch (_) {
        return null;
      }
    } else if (messageData is Map) {
      payload = messageData.map((key, value) => MapEntry('$key', value));
    } else {
      final serialized = '$messageData'.trim();
      if (serialized.startsWith('{') && serialized.endsWith('}')) {
        try {
          final decoded = jsonDecode(serialized);
          if (decoded is Map<String, dynamic>) {
            payload = decoded;
          }
        } catch (_) {
          return null;
        }
      }
    }

    if (payload == null) return null;

    final type = '${payload['type'] ?? ''}'.trim();
    if (type != 'space.telegram.auth') return null;

    final initData = '${payload['initData'] ?? ''}'.trim();
    if (initData.isEmpty) return null;

    return initData;
  }
}
