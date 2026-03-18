import 'package:shared_preferences/shared_preferences.dart';

/// Типизированная обёртка над SharedPreferences.
///
/// Инициализируется один раз в `_bootstrap()` → `AppStorage.init()`.
/// После этого все геттеры синхронные.
///
/// Использование:
///   // Чтение
///   final goal = AppStorage.weeklyWorkoutGoal;
///   // Запись
///   await AppStorage.setWeeklyWorkoutGoal(3);
class AppStorage {
  AppStorage._();

  static late SharedPreferences _p;

  /// Инициализировать до первого использования (вызывать в `_bootstrap`).
  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  // ── Тема ────────────────────────────────────────────────────────────────────
  static String get themeMode => _p.getString('theme_mode') ?? 'system';
  static Future<void> setThemeMode(String v) => _p.setString('theme_mode', v);

  // ── Единицы ─────────────────────────────────────────────────────────────────
  static bool get useKg => _p.getBool('use_kg') ?? true;
  static Future<void> setUseKg(bool v) => _p.setBool('use_kg', v);

  static bool get useCm => _p.getBool('use_cm') ?? true;
  static Future<void> setUseCm(bool v) => _p.setBool('use_cm', v);

  // ── Уведомления ─────────────────────────────────────────────────────────────
  static bool get notificationsEnabled =>
      _p.getBool('notifications_enabled') ?? false;
  static Future<void> setNotificationsEnabled(bool v) =>
      _p.setBool('notifications_enabled', v);

  static int get notifHour => _p.getInt('notif_hour') ?? 8;
  static Future<void> setNotifHour(int v) => _p.setInt('notif_hour', v);

  static int get notifMinute => _p.getInt('notif_minute') ?? 0;
  static Future<void> setNotifMinute(int v) => _p.setInt('notif_minute', v);

  /// 'fixed' | 'before'
  static String get notifMode => _p.getString('notif_mode') ?? 'fixed';
  static Future<void> setNotifMode(String v) => _p.setString('notif_mode', v);

  static int get notifMinutesBefore => _p.getInt('notif_minutes_before') ?? 30;
  static Future<void> setNotifMinutesBefore(int v) =>
      _p.setInt('notif_minutes_before', v);

  // ── Уведомления в дни отдыха ────────────────────────────────────────────────
  static int get restDayNotifHour => _p.getInt('rest_day_notif_hour') ?? 9;
  static Future<void> setRestDayNotifHour(int v) =>
      _p.setInt('rest_day_notif_hour', v);

  static int get restDayNotifMinute =>
      _p.getInt('rest_day_notif_minute') ?? 0;
  static Future<void> setRestDayNotifMinute(int v) =>
      _p.setInt('rest_day_notif_minute', v);

  // ── Взвешивание ─────────────────────────────────────────────────────────────
  static bool get weighInEnabled =>
      _p.getBool('weigh_in_notif_enabled') ?? false;
  static Future<void> setWeighInEnabled(bool v) =>
      _p.setBool('weigh_in_notif_enabled', v);

  /// 0 = Пн … 6 = Вс
  static int get weighInWeekday => _p.getInt('weigh_in_weekday') ?? 0;
  static Future<void> setWeighInWeekday(int v) =>
      _p.setInt('weigh_in_weekday', v);

  static int get weighInHour => _p.getInt('weigh_in_hour') ?? 9;
  static Future<void> setWeighInHour(int v) => _p.setInt('weigh_in_hour', v);

  static int get weighInMinute => _p.getInt('weigh_in_minute') ?? 0;
  static Future<void> setWeighInMinute(int v) =>
      _p.setInt('weigh_in_minute', v);

  // ── Тренировки ──────────────────────────────────────────────────────────────
  /// 0 = не задана
  static int get weeklyWorkoutGoal =>
      _p.getInt('weekly_workout_goal') ?? 0;
  static Future<void> setWeeklyWorkoutGoal(int v) =>
      _p.setInt('weekly_workout_goal', v);

  static bool get deloadActive => _p.getBool('deload_active') ?? false;
  static Future<void> setDeloadActive(bool v) =>
      _p.setBool('deload_active', v);

  /// Дата (yyyy-MM-dd), когда последний раз показывалось предложение deload.
  static String? get lastDeloadSuggestionDate =>
      _p.getString('last_deload_suggestion_date');
  static Future<void> setLastDeloadSuggestionDate(String v) =>
      _p.setString('last_deload_suggestion_date', v);

  // ── Еженедельный итог ────────────────────────────────────────────────────────
  static bool get weeklySummaryEnabled =>
      _p.getBool('weekly_summary_enabled') ?? true;
  static Future<void> setWeeklySummaryEnabled(bool v) =>
      _p.setBool('weekly_summary_enabled', v);

  // ── Streak freeze ────────────────────────────────────────────────────────────
  /// Дата последней использованной заморозки (yyyy-MM-dd) или null.
  static String? get streakFreezeUsedDate =>
      _p.getString('streak_freeze_used_date');
  static Future<void> setStreakFreezeUsedDate(String? v) => v != null
      ? _p.setString('streak_freeze_used_date', v)
      : _p.remove('streak_freeze_used_date');

  /// Кол-во доступных заморозок (максимум 1, восстанавливается каждую неделю).
  static int get streakFreezeCount => _p.getInt('streak_freeze_count') ?? 1;
  static Future<void> setStreakFreezeCount(int v) =>
      _p.setInt('streak_freeze_count', v);

  /// Дата последнего восстановления заморозки (yyyy-MM-dd).
  static String? get streakFreezeRefillDate =>
      _p.getString('streak_freeze_refill_date');
  static Future<void> setStreakFreezeRefillDate(String? v) => v != null
      ? _p.setString('streak_freeze_refill_date', v)
      : _p.remove('streak_freeze_refill_date');

  // ── Еженедельная цель ────────────────────────────────────────────────────────
  // weeklyWorkoutGoal уже объявлена выше (int, 0 = не задана)

  // ── Порядок и видимость программ ────────────────────────────────────────────
  static List<String> get workoutOrder =>
      _p.getStringList('workout_order') ?? [];
  static Future<void> setWorkoutOrder(List<String> v) =>
      _p.setStringList('workout_order', v);

  static List<String> get hiddenWorkoutIds =>
      _p.getStringList('hidden_workout_ids') ?? [];
  static Future<void> setHiddenWorkoutIds(List<String> v) =>
      _p.setStringList('hidden_workout_ids', v);

  // ── Офлайн-очередь ──────────────────────────────────────────────────────────
  static List<String> get offlineSetQueue =>
      _p.getStringList('offline_set_queue') ?? [];
  static Future<void> setOfflineSetQueue(List<String> v) =>
      _p.setStringList('offline_set_queue', v);

  // ── PIN ─────────────────────────────────────────────────────────────────────
  static String? get pinHash => _p.getString('pin_hash');
  static Future<void> setPinHash(String? v) => v != null
      ? _p.setString('pin_hash', v)
      : _p.remove('pin_hash');

  static int get pinFailedAttempts =>
      _p.getInt('pin_failed_attempts') ?? 0;
  static Future<void> setPinFailedAttempts(int v) =>
      _p.setInt('pin_failed_attempts', v);

  static int? get pinFailedAt => _p.getInt('pin_failed_at');
  static Future<void> setPinFailedAt(int? v) => v != null
      ? _p.setInt('pin_failed_at', v)
      : _p.remove('pin_failed_at');

  // ── Биометрия ───────────────────────────────────────────────────────────────
  static bool get biometricEnabled => _p.getBool('biometric_enabled') ?? false;
  static Future<void> setBiometricEnabled(bool v) =>
      _p.setBool('biometric_enabled', v);

  // ── Еженедельный отчёт ───────────────────────────────────────────────────────
  /// ISO-неделя последнего показанного отчёта, формат "yyyy-Www" (например "2026-W12").
  /// null — ещё не показывался.
  static String? get lastWeeklySummaryShownWeek =>
      _p.getString('weekly_summary_shown_week');
  static Future<void> setLastWeeklySummaryShownWeek(String v) =>
      _p.setString('weekly_summary_shown_week', v);

  // ── Достижения ───────────────────────────────────────────────────────────────
  /// IDs достижений, о которых пользователь уже был уведомлён.
  static List<String> get seenAchievementIds =>
      _p.getStringList('seen_achievement_ids') ?? [];
  static Future<void> setSeenAchievementIds(List<String> v) =>
      _p.setStringList('seen_achievement_ids', v);
}
