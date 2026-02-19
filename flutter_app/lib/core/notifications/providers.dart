import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_reminder_service.dart';
import 'push_notification_service.dart';

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  final service = PushNotificationService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final localReminderServiceProvider = Provider<LocalReminderService>((ref) {
  return LocalReminderService();
});
