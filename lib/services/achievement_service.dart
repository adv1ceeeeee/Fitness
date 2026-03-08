import 'package:sportwai/services/analytics_service.dart';

class Achievement {
  final String id;
  final String emoji;
  final String title;
  final String description;
  final bool unlocked;

  const Achievement({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.unlocked,
  });
}

class AchievementService {
  static Future<List<Achievement>> getAchievements() async {
    final results = await Future.wait([
      AnalyticsService.getTotalWorkouts(),
      AnalyticsService.getBestStreak(),
    ]);
    return buildFromStats(results[0], results[1]);
  }

  /// Pure function — builds achievement list from pre-fetched stats.
  /// Exposed for testing.
  static List<Achievement> buildFromStats(int totalWorkouts, int bestStreak) {
    return [
      ..._workoutAchievements(totalWorkouts),
      ..._streakAchievements(bestStreak),
    ];
  }

  static List<Achievement> _workoutAchievements(int total) {
    final defs = [
      (1, '🏋', 'Первая тренировка', 'Завершена первая тренировка'),
      (5, '💪', 'Начало пути', 'Завершено 5 тренировок'),
      (10, '🔟', 'Десятка', '10 тренировок позади'),
      (25, '🎯', 'Четверть сотни', '25 завершённых тренировок'),
      (50, '⚡', 'Полсотни', '50 тренировок — серьёзно!'),
      (100, '💯', 'Сотня', '100 тренировок — вы легенда!'),
    ];
    return defs.map((d) => Achievement(
      id: 'workouts_${d.$1}',
      emoji: d.$2,
      title: d.$3,
      description: d.$4,
      unlocked: total >= d.$1,
    )).toList();
  }

  static List<Achievement> _streakAchievements(int streak) {
    final defs = [
      (3, '🔥', 'Тройная серия', '3 дня подряд'),
      (7, '📅', 'Неделя', 'Тренировки 7 дней подряд'),
      (14, '📆', 'Две недели', '14 дней без пропусков'),
      (30, '🗓️', 'Месяц', '30 дней — железная воля!'),
      (100, '🏆', 'Легенда', '100 дней подряд — невероятно!'),
    ];
    return defs.map((d) => Achievement(
      id: 'streak_${d.$1}',
      emoji: d.$2,
      title: d.$3,
      description: d.$4,
      unlocked: streak >= d.$1,
    )).toList();
  }
}
