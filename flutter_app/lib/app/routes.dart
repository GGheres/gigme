/// AppRoutes represents app routes.
class AppRoutes {
  static const landing = '/';
  static const iskry = '/iskry';
  static const iskrySuccess = '/iskry/success';
  static const iskryFail = '/iskry/fail';

  static const appRoot = '/space_app';
  static const auth = '/space_app/auth';
  static const feed = '/space_app/feed';
  static const map = '/space_app/map';
  static const create = '/space_app/create';
  static const profile = '/space_app/profile';
  static const settings = '/space_app/settings';
  static const admin = '/space_app/admin';
  static const buy = '/space_app/buy';
  static const transfer = '/space_app/transfer';
  static const myTickets = '/space_app/tickets';
  static const adminOrders = '/space_app/admin/orders';
  static const adminTransfers = '/space_app/admin/transfers';
  static const adminBotMessages = '/space_app/admin/bot-messages';
  static const adminScanner = '/space_app/admin/scanner';
  static const adminProducts = '/space_app/admin/products';
  static const adminPromos = '/space_app/admin/promos';
  static const adminStats = '/space_app/admin/stats';
  static const uiPreview = '/space_app/dev/ui_preview';

  /// event handles internal event behavior.

  static String event(int id) => '/space_app/event/$id';

  /// eventPurchase returns the direct event purchase route.

  static String eventPurchase(int id) => '/space_app/event/$id/buy';

  /// eventTransferPurchase returns the direct transfer purchase route.

  static String eventTransferPurchase(int id) =>
      '${eventPurchase(id)}?mode=transfer';

  /// adminEvent handles admin event.
  static String adminEvent(int id) => '/space_app/admin/event/$id';

  /// adminOrderDetail handles admin order detail.
  static String adminOrderDetail(String id) => '/space_app/admin/orders/$id';

  /// adminBotMessagesForChat handles admin bot messages for chat.
  static String adminBotMessagesForChat(int chatId) =>
      '$adminBotMessages?chatId=$chatId';

  /// isAppPath reports whether app path condition is met.

  static bool isAppPath(String location) =>
      location == appRoot || location.startsWith('$appRoot/');

  /// isAuthReturnPath reports whether auth can safely redirect to this path.
  static bool isAuthReturnPath(String location) {
    return isAppPath(location) ||
        location == landing ||
        location == iskry ||
        location.startsWith('$iskry/');
  }
}
