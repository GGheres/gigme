import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// _webApp handles web app.

JSObject? _webApp() {
  final telegram = globalContext['Telegram'];
  if (telegram is! JSObject) return null;
  final app = telegram['WebApp'];
  if (app is! JSObject) return null;
  return app;
}

/// _readTrimmedJsString reads trimmed js string.

String? _readTrimmedJsString(JSAny? value) {
  if (value is! JSString) return null;
  final text = value.toDart.trim();
  if (text.isEmpty) return null;
  return text;
}

/// isAvailable reports whether available condition is met.

bool isAvailable() => _webApp() != null;

/// getInitData returns init data.

String? getInitData() {
  final app = _webApp();
  if (app == null) return null;
  return _readTrimmedJsString(app['initData']);
}

/// startParam handles start param.

String? startParam() {
  final app = _webApp();
  if (app == null) return null;

  final unsafe = app['initDataUnsafe'];
  if (unsafe is! JSObject) return null;

  final first = _readTrimmedJsString(unsafe['start_param']);
  if (first != null) return first;

  return _readTrimmedJsString(unsafe['startParam']);
}

/// isLikelyMobileBrowser reports whether likely mobile browser condition is met.

bool isLikelyMobileBrowser() {
  final navigator = globalContext['navigator'];
  if (navigator is! JSObject) return false;

  final userAgent =
      _readTrimmedJsString(navigator['userAgent'])?.toLowerCase() ?? '';
  if (userAgent.isEmpty) return false;

  return userAgent.contains('android') ||
      userAgent.contains('iphone') ||
      userAgent.contains('ipad') ||
      userAgent.contains('ipod') ||
      userAgent.contains('mobile');
}

/// openLink handles open link.

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

/// openPopup handles open popup.

bool openPopup(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;

  final popup = globalContext.callMethodVarArgs<JSAny?>(
    'open'.toJS,
    <JSAny?>[
      trimmed.toJS,
      'space_telegram_auth'.toJS,
      'popup=yes,width=480,height=760,menubar=no,toolbar=no,location=no,status=no,resizable=yes,scrollbars=yes'
          .toJS,
    ],
  );
  return popup != null;
}

/// redirect redirects the user to a target URL.

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

/// showToast handles show toast.

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

/// readyAndExpand handles ready and expand.

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
