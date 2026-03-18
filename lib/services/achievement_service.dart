import 'package:sportwai/services/analytics_service.dart';

class Achievement {
  final String id;
  final String emoji;
  final String title;
  final String description;
  final bool unlocked;
  final String category;
  /// Current progress value toward the threshold.
  final double progress;
  /// The threshold value needed to unlock.
  final double threshold;

  const Achievement({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.unlocked,
    required this.category,
    required this.progress,
    required this.threshold,
  });

  double get progressFraction => (progress / threshold).clamp(0.0, 1.0);
}

class AchievementService {
  static Future<List<Achievement>> getAchievements() async {
    final results = await Future.wait([
      AnalyticsService.getTotalWorkouts(),
      AnalyticsService.getBestStreak(),
      AnalyticsService.getTotalPrCount(),
      AnalyticsService.getTotalVolumeKg(),
    ]);
    return buildFromStats(
      results[0] as int,
      results[1] as int,
      results[2] as int,
      results[3] as double,
    );
  }

  /// Pure function — builds achievement list from pre-fetched stats.
  /// Exposed for testing.
  static List<Achievement> buildFromStats(
    int totalWorkouts,
    int bestStreak,
    int totalPrs,
    double totalVolumeKg,
  ) {
    return [
      ..._workoutAchievements(totalWorkouts),
      ..._streakAchievements(bestStreak),
      ..._prAchievements(totalPrs),
      ..._volumeAchievements(totalVolumeKg),
    ];
  }

  static List<Achievement> _workoutAchievements(int total) {
    const defs = [
      (1,   '🏋', 'Первая тренировка', 'Завершена первая тренировка'),
      (5,   '💪', 'Начало пути',       'Завершено 5 тренировок'),
      (10,  '🔟', 'Десятка',           '10 тренировок позади'),
      (25,  '🎯', 'Четверть сотни',    '25 завершённых тренировок'),
      (50,  '⚡', 'Полсотни',          '50 тренировок — серьёзно!'),
      (100, '💯', 'Сотня',             '100 тренировок — вы легенда!'),
    ];
    return defs.map((d) => Achievement(
      id: 'workouts_${d.$1}',
      emoji: d.$2,
      title: d.$3,
      description: d.$4,
      unlocked: total >= d.$1,
      category: 'Тренировки',
      progress: total.toDouble(),
      threshold: d.$1.toDouble(),
    )).toList();
  }

  static List<Achievement> _streakAchievements(int streak) {
    const defs = [
      (3,   '🔥', 'Тройная серия', '3 дня подряд'),
      (7,   '📅', 'Неделя',        'Тренировки 7 дней подряд'),
      (14,  '📆', 'Две недели',    '14 дней без пропусков'),
      (30,  '🗓️', 'Месяц',        '30 дней — железная воля!'),
      (100, '🏆', 'Легенда',       '100 дней подряд — невероятно!'),
    ];
    return defs.map((d) => Achievement(
      id: 'streak_${d.$1}',
      emoji: d.$2,
      title: d.$3,
      description: d.$4,
      unlocked: streak >= d.$1,
      category: 'Серия',
      progress: streak.toDouble(),
      threshold: d.$1.toDouble(),
    )).toList();
  }

  static List<Achievement> _prAchievements(int prs) {
    const defs = [
      (1,  '🥇', 'Первый рекорд',  'Установлен первый личный рекорд'),
      (5,  '🎖️', 'Коллекционер',  '5 личных рекордов'),
      (10, '🏅', 'Мастер',         '10 личных рекордов'),
      (25, '👑', 'Чемпион',        '25 личных рекордов — элита!'),
    ];
    return defs.map((d) => Achievement(
      id: 'prs_${d.$1}',
      emoji: d.$2,
      title: d.$3,
      description: d.$4,
      unlocked: prs >= d.$1,
      category: 'Рекорды',
      progress: prs.toDouble(),
      threshold: d.$1.toDouble(),
    )).toList();
  }

  static List<Achievement> _volumeAchievements(double volumeKg) {
    const defs = [
      (1000.0,   '🪨', 'Тонна',      'Поднято суммарно 1 000 кг'),
      (10000.0,  '🦍', 'Горилла',    'Поднято суммарно 10 000 кг'),
      (50000.0,  '🚛', 'Грузовик',   'Поднято суммарно 50 000 кг'),
      (100000.0, '🚀', 'В космос!',  'Поднято суммарно 100 000 кг'),
    ];
    return defs.map((d) => Achievement(
      id: 'volume_${d.$1.toInt()}',
      emoji: d.$2,
      title: d.$3,
      description: d.$4,
      unlocked: volumeKg >= d.$1,
      category: 'Объём',
      progress: volumeKg,
      threshold: d.$1,
    )).toList();
  }
}
