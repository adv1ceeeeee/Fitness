import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform, kDebugMode, TargetPlatform;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/local_storage.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static const _channelId = 'workout_reminders';
  static const _channelName = 'Напоминания о тренировках';
  static const _channelDesc = 'Ежедневные напоминания о запланированных тренировках';

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> initialize() async {
    if (_initialized) return;
    if (!_isSupportedPlatform) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(_localTzName()));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    try {
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: iOS),
        onDidReceiveNotificationResponse: _onTap,
      );
      _initialized = true;
    } on UnimplementedError catch (e) {
      if (kDebugMode) debugPrint('[NotifService] initialize: platform not supported — $e');
    } catch (e) {
      if (kDebugMode) debugPrint('[NotifService] initialize error: $e');
    }
  }

  /// Called when the user taps a notification (foreground or background).
  static void _onTap(NotificationResponse response) {
    final type = response.payload ?? 'unknown';
    EventLogger.log('notification_tapped', props: {
      'notif_type': type,
      'notif_id': response.id,
    });
    // Mark tapped_at in push_notification_logs (fire-and-forget)
    _markTapped(response.id, type);
  }

  static void _markTapped(int? notifId, String type) {
    if (notifId == null) return;
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    Supabase.instance.client
        .from('push_notification_logs')
        .update({'tapped_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', userId)
        .eq('notif_id', notifId)
        .isFilter('tapped_at', null)
        .then((_) {}, onError: (e) { if (kDebugMode) debugPrint('[NotifService] markTapped: $e'); });
  }

  /// Fire-and-forget: log a scheduled notification to Supabase.
  static void _logScheduled({
    required String type,
    required int notifId,
    DateTime? scheduledFor,
    String? sessionId,
  }) {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    Supabase.instance.client.from('push_notification_logs').insert({
      'user_id': userId,
      'notif_type': type,
      'notif_id': notifId,
      if (scheduledFor != null) 'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      if (sessionId != null) 'session_id': sessionId,
    }).then((_) {}, onError: (e) { if (kDebugMode) debugPrint('[NotifService] logScheduled: $e'); });
  }

  /// Returns true if permission was granted (or already granted).
  static Future<bool> requestPermission() async {
    if (!_isSupportedPlatform) return true; // desktop: no permission needed
    if (!_initialized) return false;
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
  /// [dayToName] maps each app-day index to the workout name shown in the body.
  /// Notifications fire at [hour]:[minute] in the device's local timezone.
  static Future<void> scheduleWorkoutReminders(
    List<int> workoutDays, {
    int hour = 8,
    int minute = 0,
    Map<int, String>? dayToName,
  }) async {
    if (!_initialized) return;
    // Cancel only workout-day notifications (IDs 0-6) — keep other notifs
    for (int i = 0; i < 7; i++) {
      await _plugin.cancel(i);
    }
    await _plugin.cancel(_kDailyReminderId);

    if (workoutDays.isEmpty) {
      // No program → schedule a general daily reminder so the user doesn't ghost
      await scheduleGeneralDailyReminder(hour: hour, minute: minute);
      return;
    }

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
      final name = dayToName?[appDay];
      final body = name != null
          ? 'Сегодня: $name. Вперёд, ты можешь! 🏋'
          : 'Сегодня запланирована тренировка. Вперёд! 💪';
      final scheduled = _nextWeekday(appDay, hour, minute);
      await _zonedSchedule(
        appDay, // notification id = day index (0-6)
        'Время тренироваться! 💪',
        body,
        scheduled,
        details,
        payload: 'workout_reminder',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      _logScheduled(type: 'workout_reminder', notifId: appDay);
    }
  }

  /// Schedule a general daily reminder (fires every day at [hour]:[minute]).
  /// Used for users who have notifications enabled but no workout program.
  static Future<void> scheduleGeneralDailyReminder({
    int hour = 8,
    int minute = 0,
  }) async {
    if (!_initialized) return;
    await _plugin.cancel(_kDailyReminderId);
    const channel = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: channel, iOS: DarwinNotificationDetails());
    final scheduled = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1));
    final scheduledTime = tz.TZDateTime(
        tz.local, scheduled.year, scheduled.month, scheduled.day, hour, minute);
    await _zonedSchedule(
      _kDailyReminderId,
      'Не забудь про тренировку 💪',
      'Создай программу — и мы будем напоминать тебе каждый день.',
      scheduledTime.isBefore(tz.TZDateTime.now(tz.local))
          ? scheduledTime.add(const Duration(days: 1))
          : scheduledTime,
      details,
      payload: 'daily_reminder',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    _logScheduled(type: 'daily_reminder', notifId: _kDailyReminderId);
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
    await _zonedSchedule(
      notifId,
      'Время тренироваться! 💪',
      workoutName,
      scheduled,
      details,
      payload: 'session',
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    _logScheduled(
      type: 'session',
      notifId: notifId,
      scheduledFor: scheduled.toLocal(),
      sessionId: sessionId,
    );
  }

  /// Cancel the one-time notification for a session.
  static Future<void> cancelSessionNotification(String sessionId) async {
    if (!_initialized) return;
    final notifId = sessionId.hashCode & 0x3FFFFFFF;
    await _plugin.cancel(notifId);
  }

  /// Schedule a motivational inactivity reminder N days from now.
  /// Cancels the previous one so only one is active at a time.
  static Future<void> scheduleInactivityReminder({int daysLater = 3}) async {
    if (!_initialized) return;
    await _plugin.cancel(_kInactivityId);
    final fire = tz.TZDateTime.now(tz.local).add(Duration(days: daysLater));
    const channel = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high, priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(
        android: channel, iOS: DarwinNotificationDetails());
    await _zonedSchedule(
      _kInactivityId,
      'Давно не тренировались! 💪',
      'Пора вернуться — тело скучает по нагрузке.',
      fire,
      details,
      payload: 'inactivity',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    _logScheduled(
      type: 'inactivity',
      notifId: _kInactivityId,
      scheduledFor: fire.toLocal(),
    );
  }

  static Future<void> cancelInactivityReminder() async {
    if (!_initialized) return;
    await _plugin.cancel(_kInactivityId);
  }

  /// Cancels and reschedules a churn notification 14 days from now.
  /// Call on every app open so only users truly silent for 14 days get it.
  static Future<void> scheduleChurnNotification() async {
    if (!_initialized) return;
    await _plugin.cancel(_kChurnId);
    final fire = tz.TZDateTime.now(tz.local).add(const Duration(days: 14));
    const channel = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high, priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(
        android: channel, iOS: DarwinNotificationDetails());
    await _zonedSchedule(
      _kChurnId,
      'Скучаем по тебе 🏋️',
      'Две недели без тренировок. Возвращайся — твой прогресс ждёт!',
      fire,
      details,
      payload: 'churn',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedule weekly weigh-in reminders for one or more weekdays.
  /// [weekdays]: list of 0=Пн … 6=Вс. Pass [0,1,2,3,4,5,6] for every day.
  static Future<void> scheduleWeighInReminders(
    List<int> weekdays, {
    int hour = 9,
    int minute = 0,
  }) async {
    await cancelWeighInReminder(); // cancel all previous weigh-in notifs
    if (weekdays.isEmpty) return;

    const channel = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(
        android: channel, iOS: DarwinNotificationDetails());

    for (final day in weekdays.toSet()) {
      final notifId = _kWeighInBase + day;
      final scheduled = _nextWeekday(day, hour, minute);
      await _zonedSchedule(
        notifId,
        'Время взвеситься ⚖️',
        'Зафиксируйте вес для отслеживания прогресса.',
        scheduled,
        details,
        payload: 'weigh_in',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      _logScheduled(type: 'weigh_in', notifId: notifId);
    }
  }

  /// Legacy single-day wrapper — kept for backward compatibility.
  static Future<void> scheduleWeighInReminder({
    int weekday = 0,
    int hour = 9,
    int minute = 0,
  }) => scheduleWeighInReminders([weekday], hour: hour, minute: minute);

  static Future<void> cancelWeighInReminder() async {
    if (!_initialized) return;
    // Cancel legacy single ID + all per-day IDs
    await _plugin.cancel(_kWeighInId);
    for (int i = 0; i < 7; i++) {
      await _plugin.cancel(_kWeighInBase + i);
    }
  }

  /// Schedule weekly rest-day reminders for each day in [restDays] (0=Mon…6=Sun).
  /// Cancels all previous rest-day notifications first.
  static Future<void> scheduleRestDayReminders(
    List<int> restDays, {
    int hour = 9,
    int minute = 0,
  }) async {
    if (!_initialized) return;
    for (int i = 0; i < 7; i++) {
      await _plugin.cancel(_kRestDayBase + i);
    }
    if (restDays.isEmpty) return;

    const channel = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(
        android: channel, iOS: DarwinNotificationDetails());

    for (final day in restDays.toSet()) {
      final scheduled = _nextWeekday(day, hour, minute);
      final notifId = _kRestDayBase + day;
      await _zonedSchedule(
        notifId,
        'Сегодня день отдыха 🛏',
        'Отдохните и восстановитесь — завтра снова в бой!',
        scheduled,
        details,
        payload: 'rest_day',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      _logScheduled(type: 'rest_day', notifId: notifId);
    }
  }

  static Future<void> cancelRestDayReminders() async {
    if (!_initialized) return;
    for (int i = 0; i < 7; i++) {
      await _plugin.cancel(_kRestDayBase + i);
    }
  }

  /// Schedule (or reschedule) the weekly summary notification for Sunday 19:00.
  /// Call this on app open and after every workout completion.
  static Future<void> scheduleWeeklySummary({
    required int workoutsCount,
    required double volumeKg,
    required int streak,
    required int prs,
  }) async {
    if (!_initialized) return;
    await _plugin.cancel(_kWeeklySummaryId);

    final title = _weeklySummaryTitle(workoutsCount);
    final body = _weeklySummaryBody(
        workoutsCount: workoutsCount, volumeKg: volumeKg, streak: streak, prs: prs);

    const channel = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: channel, iOS: DarwinNotificationDetails());

    final scheduled = _nextWeekday(6, 19, 0); // 6 = Sunday, 19:00
    await _zonedSchedule(
      _kWeeklySummaryId,
      title,
      body,
      scheduled,
      details,
      payload: 'weekly_summary',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    _logScheduled(type: 'weekly_summary', notifId: _kWeeklySummaryId);
  }

  static Future<void> cancelWeeklySummary() async {
    if (!_initialized) return;
    await _plugin.cancel(_kWeeklySummaryId);
  }

  /// Fire-and-forget: fetch this week's stats and reschedule the Sunday summary.
  /// Safe to call on every app open and after every workout completion.
  static void refreshWeeklySummary() {
    if (!AppStorage.notificationsEnabled || !AppStorage.weeklySummaryEnabled) return;
    AnalyticsService.getWeeklySummaryData().then((data) {
      scheduleWeeklySummary(
        workoutsCount: data.workouts,
        volumeKg: data.volumeKg,
        streak: data.streak,
        prs: data.prs,
      );
    }).catchError((e) { if (kDebugMode) debugPrint('[NotifService] refreshWeeklySummary: $e'); });
  }

  static String _weeklySummaryTitle(int workouts) {
    if (workouts == 0) return 'Неделя закончилась 🤔';
    if (workouts <= 2) return 'Начало положено 👍';
    return 'Отличная неделя 🔥';
  }

  static String _weeklySummaryBody({
    required int workoutsCount,
    required double volumeKg,
    required int streak,
    required int prs,
  }) {
    if (workoutsCount == 0) {
      return 'На этой неделе тренировок не было. Следующая неделя — новый шанс!';
    }
    final parts = <String>[];
    parts.add('$workoutsCount ${_plural(workoutsCount, 'тренировка', 'тренировки', 'тренировок')}');
    if (volumeKg > 0) {
      parts.add('${volumeKg.round()} кг объёма');
    }
    if (prs > 0) {
      parts.add('$prs ${_plural(prs, 'рекорд', 'рекорда', 'рекордов')} 🏆');
    }
    final base = parts.join(' · ');
    if (streak >= 7) return '$base · стрик $streak дн 🔥';
    return base;
  }

  static String _plural(int n, String one, String few, String many) {
    final mod10 = n % 10, mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return few;
    return many;
  }

  static Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } on UnimplementedError catch (e) {
      if (kDebugMode) debugPrint('[NotifService] cancelAll not supported on this platform: $e');
    }
  }

  /// Wraps [_plugin.zonedSchedule] and silently ignores [UnimplementedError]
  /// so that platforms without notification support (e.g. Windows desktop)
  /// don't crash the calling flow.
  static Future<void> _zonedSchedule(
    int id,
    String title,
    String body,
    tz.TZDateTime scheduledDate,
    NotificationDetails details, {
    required AndroidScheduleMode androidScheduleMode,
    required UILocalNotificationDateInterpretation
        uiLocalNotificationDateInterpretation,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        payload: payload,
        androidScheduleMode: androidScheduleMode,
        uiLocalNotificationDateInterpretation:
            uiLocalNotificationDateInterpretation,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } on UnimplementedError catch (e) {
      if (kDebugMode) debugPrint('[NotifService] zonedSchedule not supported on this platform: $e');
    }
  }

  static const int _kInactivityId = 900;
  static const int _kWeighInId = 901;
  static const int _kWeeklySummaryId = 920;
  static const int _kDailyReminderId = 930;
  static const int _kChurnId = 940;
  // Rest-day notifications use IDs 800–806 (one per weekday)
  static const int _kRestDayBase = 800;
  // Weigh-in notifications use IDs 910–916 (one per weekday)
  static const int _kWeighInBase = 910;

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
