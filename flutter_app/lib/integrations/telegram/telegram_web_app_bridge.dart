import 'telegram_web_app_bridge_stub.dart'
    if (dart.library.html) 'telegram_web_app_bridge_web.dart' as bridge;

/// TelegramWebAppBridge represents telegram web app bridge.

class TelegramWebAppBridge {
  /// isAvailable reports whether available condition is met.
  static bool isAvailable() => bridge.isAvailable();

  /// getInitData returns init data.

  static String? getInitData() => bridge.getInitData();

  /// startParam handles start param.

  static String? startParam() => bridge.startParam();

  /// isLikelyMobileBrowser reports whether likely mobile browser condition is met.

  static bool isLikelyMobileBrowser() => bridge.isLikelyMobileBrowser();

  /// openLink handles open link.

  static void openLink(String url) => bridge.openLink(url);

  /// openPopup handles open popup.

  static bool openPopup(String url) => bridge.openPopup(url);

  /// redirect redirects the user to a target URL.

  static void redirect(String url) => bridge.redirect(url);

  /// showToast handles show toast.

  static void showToast(String message) => bridge.showToast(message);

  /// readyAndExpand handles ready and expand.

  static void readyAndExpand() => bridge.readyAndExpand();
}
