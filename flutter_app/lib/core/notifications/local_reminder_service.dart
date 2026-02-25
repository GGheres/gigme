import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

/// LocalReminderService represents local reminder service.

class LocalReminderService {
  static const int _createEventReminderId = 4001;
  static const String _channelId = 'gigme_draft_reminders';
  static const String _channelName = 'Draft reminders';
  static const String _channelDescription =
      'Reminders to finish incomplete actions';
  static const Duration _defaultDelay = Duration(minutes: 2);
  static const String _enabledStorageKey = 'gigme_local_reminders_enabled';
  static const InitializationSettings _initializationSettings =

      /// InitializationSettings handles initialization settings.
      InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
      defaultPresentAlert: true,
      defaultPresentSound: true,
      defaultPresentBadge: false,
      defaultPresentBanner: true,
      defaultPresentList: true,
    ),
  );

  final FlutterLocalNotificationsPlugin _plugin =

      /// FlutterLocalNotificationsPlugin handles flutter local notifications plugin.
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _initializing = false;
  bool _permissionsRequested = false;

  /// initialize handles internal initialize behavior.

  Future<void> initialize() async {
    await _ensureInitialized(
      respectEnabledFlag: true,
      requestPermissions: true,
    );
  }

  /// isEnabled reports whether enabled condition is met.

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledStorageKey) ?? true;
  }

  /// setEnabled sets enabled.

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledStorageKey, enabled);
    if (!enabled) {
      await cancelAllDraftReminders();
      return;
    }
    await initialize();
  }

  /// scheduleCreateEventReminder handles schedule create event reminder.

  Future<void> scheduleCreateEventReminder({
    Duration delay = _defaultDelay,
  }) async {
    if (!await isEnabled()) return;
    await _scheduleReminder(
      id: _createEventReminderId,
      title: 'Не забудьте завершить событие',
      body: 'Черновик сохранен. Откройте приложение и опубликуйте событие.',
      payload: 'create_event_draft',
      delay: delay,
    );
  }

  /// cancelCreateEventReminder handles cancel create event reminder.

  Future<void> cancelCreateEventReminder() {
    return _cancel(_createEventReminderId);
  }

  /// schedulePurchaseReminder handles schedule purchase reminder.

  Future<void> schedulePurchaseReminder({
    required int eventId,
    Duration delay = _defaultDelay,
  }) async {
    if (!await isEnabled()) return;
    await _scheduleReminder(
      id: _purchaseReminderId(eventId),
      title: 'Завершите покупку билета',
      body: 'Ваш выбор сохранен. Вернитесь в приложение и завершите заказ.',
      payload: 'purchase_draft:$eventId',
      delay: delay,
    );
  }

  /// cancelAllDraftReminders handles cancel all draft reminders.

  Future<void> cancelAllDraftReminders() async {
    if (kIsWeb) return;
    await _ensureInitialized(
      respectEnabledFlag: false,
      requestPermissions: false,
    );
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  /// cancelPurchaseReminder handles cancel purchase reminder.

  Future<void> cancelPurchaseReminder({required int eventId}) {
    return _cancel(_purchaseReminderId(eventId));
  }

  /// _scheduleReminder handles schedule reminder.

  Future<void> _scheduleReminder({
    required int id,
    required String title,
    required String body,
    required String payload,
    required Duration delay,
  }) async {
    if (kIsWeb) return;

    await initialize();
    if (!_initialized) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
      ),
    );

    final now = tz.TZDateTime.now(tz.local);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      now.add(delay),
      details,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// _cancel handles internal cancel behavior.

  Future<void> _cancel(int id) async {
    if (kIsWeb) return;
    await _ensureInitialized(
      respectEnabledFlag: false,
      requestPermissions: false,
    );
    if (!_initialized) return;
    await _plugin.cancel(id);
  }

  /// _ensureInitialized handles ensure initialized.

  Future<void> _ensureInitialized({
    required bool respectEnabledFlag,
    required bool requestPermissions,
  }) async {
    if (kIsWeb || _initializing) return;
    if (respectEnabledFlag && !await isEnabled()) return;

    if (!_initialized) {
      _initializing = true;
      try {
        timezone_data.initializeTimeZones();
        await _plugin.initialize(_initializationSettings);
        _initialized = true;
      } catch (error) {
        debugPrint('Local reminder init skipped: $error');
      } finally {
        _initializing = false;
      }
    }

    if (!_initialized) return;
    if (!requestPermissions || _permissionsRequested) return;

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: false,
            sound: true,
          );
      _permissionsRequested = true;
    } catch (error) {
      debugPrint('Local reminder permission request skipped: $error');
    }
  }

  /// _purchaseReminderId handles purchase reminder id.

  int _purchaseReminderId(int eventId) {
    final positiveId = eventId.abs();
    return 500000 + (positiveId % 900000);
  }
}
