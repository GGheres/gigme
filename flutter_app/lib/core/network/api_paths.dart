class ApiPaths {
  static const authTelegram = '/auth/telegram';
  static const authVkStart = '/auth/vk/start';
  static const authVk = '/auth/vk';
  static const authVkMiniApp = '/auth/vk/miniapp';
  static const me = '/me';
  static const meLocation = '/me/location';
  static const mePushToken = '/me/push-token';

  static const eventsFeed = '/events/feed';
  static const eventsNearby = '/events/nearby';
  static const eventsMine = '/events/mine';
  static const events = '/events';
  static const landingEvents = '/landing/events';
  static const landingContent = '/landing/content';

  static String eventById(int id) => '/events/$id';
  static String eventJoin(int id) => '/events/$id/join';
  static String eventLeave(int id) => '/events/$id/leave';
  static String eventLike(int id) => '/events/$id/like';
  static String eventPromote(int id) => '/events/$id/promote';
  static String adminLandingPublish(int id) => '/admin/events/$id/landing';
  static String adminEventById(int id) => '/admin/events/$id';
  static String adminCommentById(int id) => '/admin/comments/$id';
  static const adminLandingContent = '/admin/landing/content';

  static const mediaPresign = '/media/presign';
  static const mediaUpload = '/media/upload';

  static const referralCode = '/referrals/my-code';
  static const referralClaim = '/referrals/claim';

  static const topupToken = '/wallet/topup/token';
}
