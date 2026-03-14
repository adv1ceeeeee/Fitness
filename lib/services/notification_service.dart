import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static const _channelId = 'workout_reminders';
  static const _channelName = 'Напоминания о тренировках';
  static const _channelDesc = 'Ежедневные напоминания о запланированных тренировках';

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(_localTzName()));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: iOS),
    );
    _initialized = true;
  }

  /// Returns true if permission was granted (or already granted).
  static Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    // iOS
    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  /// Schedule weekly notifications for given workout days (0=Mon … 6=Sun).
  /// Notifications fire at [hour]:[minute] in the device's local timezone.
  static Future<void> scheduleWorkoutReminders(
    List<int> workoutDays, {
    int hour = 8,
    int minute = 0,
  }) async {
    await cancelAll();
    if (workoutDays.isEmpty) return;

    const channel = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: channel, iOS: iosDetails);

    final uniqueDays = workoutDays.toSet();
    for (final appDay in uniqueDays) {
      final scheduled = _nextWeekday(appDay, hour, minute);
      await _plugin.zonedSchedule(
        appDay, // notification id = day index (0-6)
        'Время тренироваться! 💪',
        'Сегодня запланирована тренировка. Вперёд!',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Schedule a one-time notification for a specific session.
  /// [sessionId] is used as notification id hash (must fit in int range).
  /// [date] + [plannedTime] determine when the notification fires.
  /// The notification fires exactly at [plannedTime] on [date].
  static Future<void> scheduleSessionNotification({
    required String sessionId,
    required DateTime date,
    required TimeOfDay plannedTime,
    String workoutName = 'Тренировка',
    int minutesBefore = 0,
  }) async {
    const channel = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: channel, iOS: iosDetails);

    final scheduled = tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day,
      plannedTime.hour,
      plannedTime.minute,
    ).subtract(Duration(minutes: minutesBefore));
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) return;

    // Use bottom 30 bits of sessionId hashCode as notification id
    final notifId = sessionId.hashCode & 0x3FFFFFFF;
    await _plugin.zonedSchedule(
      notifId,
      'Время тренироваться! 💪',
      workoutName,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancel the one-time notification for a session.
  static Future<void> cancelSessionNotification(String sessionId) async {
    final notifId = sessionId.hashCode & 0x3FFFFFFF;
    await _plugin.cancel(notifId);
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ─── Internals ─────────────────────────────────────────────────────────────

  /// Returns the next [tz.TZDateTime] for a given app-weekday (0=Mon…6=Sun)
  /// at the specified time. If today matches and time hasn't passed, returns today.
  /// Exposed as @visibleForTesting.
  // ignore: unused_element
  static tz.TZDateTime _nextWeekday(int appDay, int hour, int minute) {
    // app: 0=Mon…6=Sun → DateTime.weekday: 1=Mon…7=Sun
    final targetWeekday = appDay + 1;
    var dt = tz.TZDateTime.now(tz.local);
    dt = tz.TZDateTime(tz.local, dt.year, dt.month, dt.day, hour, minute);
    // advance until we hit the right weekday and the time is in the future
    for (var i = 0; i < 8; i++) {
      if (dt.weekday == targetWeekday && dt.isAfter(tz.TZDateTime.now(tz.local))) {
        return dt;
      }
      dt = dt.add(const Duration(days: 1));
    }
    return dt;
  }

  static String _localTzName() =>
      timezoneNameForOffset(DateTime.now().timeZoneOffset.inHours);
}

/// Maps UTC offset hours to an IANA timezone name.
/// Exposed as top-level for testability.
String timezoneNameForOffset(int hours) {
  const map = {
    2: 'Europe/Kaliningrad',
    3: 'Europe/Moscow',
    4: 'Europe/Samara',
    5: 'Asia/Yekaterinburg',
    6: 'Asia/Omsk',
    7: 'Asia/Krasnoyarsk',
    8: 'Asia/Irkutsk',
    9: 'Asia/Yakutsk',
    10: 'Asia/Vladivostok',
    11: 'Asia/Sakhalin',
    12: 'Asia/Kamchatka',
  };
  return map[hours] ?? 'UTC';
}
