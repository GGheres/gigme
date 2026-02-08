import 'telegram_web_app_bridge_stub.dart'
    if (dart.library.html) 'telegram_web_app_bridge_web.dart' as bridge;

class TelegramWebAppBridge {
  static String? getInitData() => bridge.getInitData();

  static String? startParam() => bridge.startParam();

  static void openLink(String url) => bridge.openLink(url);

  static void showToast(String message) => bridge.showToast(message);

  static void readyAndExpand() => bridge.readyAndExpand();
}
