import 'dart:html' as html;
import 'dart:js_util' as js_util;

Object? _webApp() {
  final telegram = js_util.getProperty<Object?>(html.window, 'Telegram');
  if (telegram == null) return null;
  return js_util.getProperty<Object?>(telegram, 'WebApp');
}

String? getInitData() {
  final app = _webApp();
  if (app == null) return null;
  final value = js_util.getProperty<Object?>(app, 'initData')?.toString().trim() ?? '';
  if (value.isEmpty) return null;
  return value;
}

String? startParam() {
  final app = _webApp();
  if (app == null) return null;
  final unsafe = js_util.getProperty<Object?>(app, 'initDataUnsafe');
  if (unsafe == null) return null;

  final first = js_util.getProperty<Object?>(unsafe, 'start_param')?.toString().trim() ?? '';
  if (first.isNotEmpty) return first;

  final second = js_util.getProperty<Object?>(unsafe, 'startParam')?.toString().trim() ?? '';
  if (second.isNotEmpty) return second;

  return null;
}

void openLink(String url) {
  final app = _webApp();
  final trimmed = url.trim();
  if (trimmed.isEmpty) return;

  if (app != null) {
    final openLink = js_util.getProperty<Object?>(app, 'openLink');
    if (openLink != null) {
      js_util.callMethod<void>(app, 'openLink', [trimmed]);
      return;
    }
  }

  html.window.open(trimmed, '_blank');
}

void showToast(String message) {
  final app = _webApp();
  final text = message.trim();
  if (text.isEmpty) return;

  if (app != null) {
    final showAlert = js_util.getProperty<Object?>(app, 'showAlert');
    if (showAlert != null) {
      js_util.callMethod<void>(app, 'showAlert', [text]);
      return;
    }
  }

  html.window.console.log(text);
}

void readyAndExpand() {
  final app = _webApp();
  if (app == null) return;

  if (js_util.getProperty<Object?>(app, 'ready') != null) {
    js_util.callMethod<void>(app, 'ready', const []);
  }
  if (js_util.getProperty<Object?>(app, 'expand') != null) {
    js_util.callMethod<void>(app, 'expand', const []);
  }
}
