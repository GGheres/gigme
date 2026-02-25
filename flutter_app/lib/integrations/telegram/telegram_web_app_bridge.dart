import 'telegram_web_app_bridge_stub.dart'
    if (dart.library.html) 'telegram_web_app_bridge_web.dart' as bridge;

class TelegramWebAppBridge {
  static bool isAvailable() => bridge.isAvailable();

  static String? getInitData() => bridge.getInitData();

  static String? startParam() => bridge.startParam();

  static bool isLikelyMobileBrowser() => bridge.isLikelyMobileBrowser();

  static void openLink(String url) => bridge.openLink(url);

  static bool openPopup(String url) => bridge.openPopup(url);

  static void redirect(String url) => bridge.redirect(url);

  static void showToast(String message) => bridge.showToast(message);

  static void readyAndExpand() => bridge.readyAndExpand();
}
