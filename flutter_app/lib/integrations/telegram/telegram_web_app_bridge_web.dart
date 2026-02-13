import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject? _webApp() {
  final telegram = globalContext['Telegram'];
  if (telegram is! JSObject) return null;
  final app = telegram['WebApp'];
  if (app is! JSObject) return null;
  return app;
}

String? _readTrimmedJsString(JSAny? value) {
  if (value is! JSString) return null;
  final text = value.toDart.trim();
  if (text.isEmpty) return null;
  return text;
}

bool isAvailable() => _webApp() != null;

String? getInitData() {
  final app = _webApp();
  if (app == null) return null;
  return _readTrimmedJsString(app['initData']);
}

String? startParam() {
  final app = _webApp();
  if (app == null) return null;

  final unsafe = app['initDataUnsafe'];
  if (unsafe is! JSObject) return null;

  final first = _readTrimmedJsString(unsafe['start_param']);
  if (first != null) return first;

  return _readTrimmedJsString(unsafe['startParam']);
}

void openLink(String url) {
  final app = _webApp();
  final trimmed = url.trim();
  if (trimmed.isEmpty) return;

  if (app != null && app.has('openLink')) {
    app.callMethodVarArgs<JSAny?>(
      'openLink'.toJS,
      <JSAny?>[trimmed.toJS],
    );
    return;
  }

  globalContext.callMethodVarArgs<JSAny?>(
    'open'.toJS,
    <JSAny?>[trimmed.toJS, '_blank'.toJS],
  );
}

void redirect(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return;

  final location = globalContext['location'];
  if (location is JSObject && location.has('assign')) {
    location.callMethodVarArgs<JSAny?>(
      'assign'.toJS,
      <JSAny?>[trimmed.toJS],
    );
    return;
  }

  globalContext.callMethodVarArgs<JSAny?>(
    'open'.toJS,
    <JSAny?>[trimmed.toJS, '_self'.toJS],
  );
}

void showToast(String message) {
  final app = _webApp();
  final text = message.trim();
  if (text.isEmpty) return;

  if (app != null && app.has('showAlert')) {
    app.callMethodVarArgs<JSAny?>(
      'showAlert'.toJS,
      <JSAny?>[text.toJS],
    );
    return;
  }

  final console = globalContext['console'];
  if (console is JSObject && console.has('log')) {
    console.callMethodVarArgs<JSAny?>(
      'log'.toJS,
      <JSAny?>[text.toJS],
    );
  }
}

void readyAndExpand() {
  final app = _webApp();
  if (app == null) return;

  if (app.has('ready')) {
    app.callMethodVarArgs<JSAny?>('ready'.toJS, const <JSAny?>[]);
  }
  if (app.has('expand')) {
    app.callMethodVarArgs<JSAny?>('expand'.toJS, const <JSAny?>[]);
  }
  if (app.has('disableVerticalSwipes')) {
    app.callMethodVarArgs<JSAny?>(
      'disableVerticalSwipes'.toJS,
      const <JSAny?>[],
    );
  }

  globalContext.callMethodVarArgs<JSAny?>(
    'scrollTo'.toJS,
    <JSAny?>[0.toJS, 0.toJS],
  );
}
