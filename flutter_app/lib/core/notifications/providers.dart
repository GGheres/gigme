import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'push_notification_service.dart';

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  final service = PushNotificationService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
