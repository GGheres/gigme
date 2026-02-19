class AppRoutes {
  static const landing = '/';

  static const appRoot = '/space_app';
  static const auth = '/space_app/auth';
  static const feed = '/space_app/feed';
  static const map = '/space_app/map';
  static const create = '/space_app/create';
  static const profile = '/space_app/profile';
  static const settings = '/space_app/settings';
  static const admin = '/space_app/admin';
  static const myTickets = '/space_app/tickets';
  static const adminOrders = '/space_app/admin/orders';
  static const adminBotMessages = '/space_app/admin/bot-messages';
  static const adminScanner = '/space_app/admin/scanner';
  static const adminProducts = '/space_app/admin/products';
  static const adminPromos = '/space_app/admin/promos';
  static const adminStats = '/space_app/admin/stats';
  static const uiPreview = '/space_app/dev/ui_preview';

  static String event(int id) => '/space_app/event/$id';
  static String adminEvent(int id) => '/space_app/admin/event/$id';
  static String adminOrderDetail(String id) => '/space_app/admin/orders/$id';
  static String adminBotMessagesForChat(int chatId) =>
      '$adminBotMessages?chatId=$chatId';

  static bool isAppPath(String location) =>
      location == appRoot || location.startsWith('$appRoot/');
}
