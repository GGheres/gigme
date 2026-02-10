class AppRoutes {
  static const landing = '/';

  static const appRoot = '/space_app';
  static const auth = '/space_app/auth';
  static const feed = '/space_app/feed';
  static const map = '/space_app/map';
  static const create = '/space_app/create';
  static const profile = '/space_app/profile';
  static const admin = '/space_app/admin';

  static String event(int id) => '/space_app/event/$id';

  static bool isAppPath(String location) =>
      location == appRoot || location.startsWith('$appRoot/');
}
