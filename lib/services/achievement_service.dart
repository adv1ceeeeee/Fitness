import 'dart:ui';
import 'package:sportwai/services/analytics_service.dart';

// ─── Rarity ──────────────────────────────────────────────────────────────────

enum AchievementRarity {
  common,    // серый
  uncommon,  // зелёный
  rare,      // синий
  epic,      // фиолетовый
  legendary, // золотой
}

extension AchievementRarityX on AchievementRarity {
  String get label => switch (this) {
        AchievementRarity.common => 'Обычное',
        AchievementRarity.uncommon => 'Необычное',
        AchievementRarity.rare => 'Редкое',
        AchievementRarity.epic => 'Эпическое',
        AchievementRarity.legendary => 'Легендарное',
      };

  Color get color => switch (this) {
        AchievementRarity.common => const Color(0xFF8E8E93),
        AchievementRarity.uncommon => const Color(0xFF30D158),
        AchievementRarity.rare => const Color(0xFF007AFF),
        AchievementRarity.epic => const Color(0xFFAF52DE),
        AchievementRarity.legendary => const Color(0xFFFFD700),
      };

  int get xpReward => switch (this) {
        AchievementRarity.common => 50,
        AchievementRarity.uncommon => 75,
        AchievementRarity.rare => 100,
        AchievementRarity.epic => 150,
        AchievementRarity.legendary => 200,
      };
}

// ─── Achievement model ───────────────────────────────────────────────────────

class Achievement {
  final String id;
  final String emoji;
  final String title;
  final String description;
  final bool unlocked;
  final String category;
  final double progress;
  final double threshold;
  final AchievementRarity rarity;
  final bool hidden; // hidden until unlocked

  const Achievement({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.unlocked,
    required this.category,
    required this.progress,
    required this.threshold,
    this.rarity = AchievementRarity.common,
    this.hidden = false,
  });

  double get progressFraction => (progress / threshold).clamp(0.0, 1.0);
}

// ─── Stats bundle ────────────────────────────────────────────────────────────

class AchievementStats {
  final int totalWorkouts;
  final int bestStreak;
  final int totalPrs;
  final double totalVolumeKg;
  final int earlyWorkouts;      // before 8:00
  final int lateWorkouts;       // after 20:00
  final int weekendWorkouts;    // Sat/Sun
  final int wellnessStreak;     // consecutive days with check-in
  final int totalWellnessLogs;
  final int totalBodyMetrics;
  final int uniqueExercises;
  final int uniqueMuscleGroups; // distinct categories in last 30 days
  final int exportCount;
  final int rpe10Count;         // sessions with RPE 10
  final bool jan1Workout;       // workout on Jan 1 of any year
  final int longestWorkoutMin;  // longest session in minutes

  const AchievementStats({
    required this.totalWorkouts,
    required this.bestStreak,
    required this.totalPrs,
    required this.totalVolumeKg,
    required this.earlyWorkouts,
    required this.lateWorkouts,
    required this.weekendWorkouts,
    required this.wellnessStreak,
    required this.totalWellnessLogs,
    required this.totalBodyMetrics,
    required this.uniqueExercises,
    required this.uniqueMuscleGroups,
    required this.exportCount,
    required this.rpe10Count,
    required this.jan1Workout,
    required this.longestWorkoutMin,
  });
}

// ─── Service ─────────────────────────────────────────────────────────────────

class AchievementService {
  static Future<List<Achievement>> getAchievements() async {
    final results = await Future.wait([
      AnalyticsService.getTotalWorkouts(),
      AnalyticsService.getBestStreak(),
      AnalyticsService.getTotalPrCount(),
      AnalyticsService.getTotalVolumeKg(),
      AnalyticsService.getEarlyWorkoutCount(),
      AnalyticsService.getLateWorkoutCount(),
      AnalyticsService.getWeekendWorkoutCount(),
      AnalyticsService.getWellnessStreak(),
      AnalyticsService.getTotalWellnessLogs(),
      AnalyticsService.getTotalBodyMetrics(),
      AnalyticsService.getUniqueExerciseCount(),
      AnalyticsService.getUniqueMuscleGroupsLast30(),
      AnalyticsService.getExportCount(),
      AnalyticsService.getRpe10Count(),
      AnalyticsService.hasJan1Workout(),
      AnalyticsService.getLongestWorkoutMinutes(),
    ]);
    return buildFromStats(AchievementStats(
      totalWorkouts: results[0] as int,
      bestStreak: results[1] as int,
      totalPrs: results[2] as int,
      totalVolumeKg: results[3] as double,
      earlyWorkouts: results[4] as int,
      lateWorkouts: results[5] as int,
      weekendWorkouts: results[6] as int,
      wellnessStreak: results[7] as int,
      totalWellnessLogs: results[8] as int,
      totalBodyMetrics: results[9] as int,
      uniqueExercises: results[10] as int,
      uniqueMuscleGroups: results[11] as int,
      exportCount: results[12] as int,
      rpe10Count: results[13] as int,
      jan1Workout: results[14] as bool,
      longestWorkoutMin: results[15] as int,
    ));
  }

  /// Pure function — builds full achievement list from stats.
  static List<Achievement> buildFromStats(AchievementStats s) {
    return [
      ..._workoutAchievements(s.totalWorkouts),
      ..._streakAchievements(s.bestStreak),
      ..._prAchievements(s.totalPrs),
      ..._volumeAchievements(s.totalVolumeKg),
      ..._consistencyAchievements(s),
      ..._wellnessAchievements(s),
      ..._bodyAchievements(s),
      ..._varietyAchievements(s),
      ..._socialAchievements(s),
      ..._hiddenAchievements(s),
    ];
  }

  // ── Тренировки ─────────────────────────────────────────────────────────────

  static List<Achievement> _workoutAchievements(int total) {
    const defs = [
      (1,   '🏋', 'Первая тренировка', 'Завершена первая тренировка',       AchievementRarity.common),
      (5,   '💪', 'Начало пути',       'Завершено 5 тренировок',            AchievementRarity.common),
      (10,  '🔟', 'Десятка',           '10 тренировок позади',              AchievementRarity.uncommon),
      (25,  '🎯', 'Четверть сотни',    '25 завершённых тренировок',         AchievementRarity.uncommon),
      (50,  '⚡', 'Полсотни',          '50 тренировок — серьёзно!',         AchievementRarity.rare),
      (100, '💯', 'Сотня',             '100 тренировок — вы легенда!',      AchievementRarity.epic),
      (250, '🌟', 'Несгибаемый',       '250 тренировок — это образ жизни!', AchievementRarity.legendary),
    ];
    return _buildList(defs, total.toDouble(), 'Тренировки');
  }

  // ── Серия ──────────────────────────────────────────────────────────────────

  static List<Achievement> _streakAchievements(int streak) {
    const defs = [
      (3,   '🔥', 'Тройная серия', '3 дня подряд',                   AchievementRarity.common),
      (7,   '📅', 'Неделя',        'Тренировки 7 дней подряд',       AchievementRarity.uncommon),
      (14,  '📆', 'Две недели',    '14 дней без пропусков',          AchievementRarity.rare),
      (30,  '🗓️', 'Месяц',        '30 дней — железная воля!',       AchievementRarity.epic),
      (100, '🏆', 'Легенда серий', '100 дней подряд — невероятно!',  AchievementRarity.legendary),
    ];
    return _buildList(defs, streak.toDouble(), 'Серия');
  }

  // ── Рекорды ────────────────────────────────────────────────────────────────

  static List<Achievement> _prAchievements(int prs) {
    const defs = [
      (1,  '🥇', 'Первый рекорд',  'Установлен первый личный рекорд',  AchievementRarity.common),
      (5,  '🎖️', 'Коллекционер',  '5 личных рекордов',                AchievementRarity.uncommon),
      (10, '🏅', 'Рекордсмен',     '10 личных рекордов',               AchievementRarity.rare),
      (25, '👑', 'Чемпион',        '25 личных рекордов — элита!',      AchievementRarity.epic),
      (50, '💎', 'Бриллиант',      '50 личных рекордов',               AchievementRarity.legendary),
    ];
    return _buildList(defs, prs.toDouble(), 'Рекорды');
  }

  // ── Объём ──────────────────────────────────────────────────────────────────

  static List<Achievement> _volumeAchievements(double volumeKg) {
    final defs = [
      (1000.0,    '🪨', 'Тонна',        'Поднято суммарно 1 000 кг',    AchievementRarity.common),
      (10000.0,   '🦍', 'Горилла',      'Поднято суммарно 10 000 кг',   AchievementRarity.uncommon),
      (50000.0,   '🚛', 'Грузовик',     'Поднято суммарно 50 000 кг',   AchievementRarity.rare),
      (100000.0,  '🚀', 'В космос!',    'Поднято суммарно 100 000 кг',  AchievementRarity.epic),
      (500000.0,  '🌍', 'Титан',        'Поднято суммарно 500 000 кг',  AchievementRarity.legendary),
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
      rarity: d.$5,
    )).toList();
  }

  // ── Постоянство ────────────────────────────────────────────────────────────

  static List<Achievement> _consistencyAchievements(AchievementStats s) {
    return [
      Achievement(
        id: 'early_5',
        emoji: '🌅',
        title: 'Ранняя пташка',
        description: '5 тренировок до 8:00',
        unlocked: s.earlyWorkouts >= 5,
        category: 'Постоянство',
        progress: s.earlyWorkouts.toDouble(),
        threshold: 5,
        rarity: AchievementRarity.uncommon,
      ),
      Achievement(
        id: 'early_20',
        emoji: '☀️',
        title: 'Жаворонок',
        description: '20 тренировок до 8:00',
        unlocked: s.earlyWorkouts >= 20,
        category: 'Постоянство',
        progress: s.earlyWorkouts.toDouble(),
        threshold: 20,
        rarity: AchievementRarity.rare,
      ),
      Achievement(
        id: 'late_5',
        emoji: '🌙',
        title: 'Ночная сова',
        description: '5 тренировок после 20:00',
        unlocked: s.lateWorkouts >= 5,
        category: 'Постоянство',
        progress: s.lateWorkouts.toDouble(),
        threshold: 5,
        rarity: AchievementRarity.uncommon,
      ),
      Achievement(
        id: 'weekend_10',
        emoji: '🏖️',
        title: 'Выходной боец',
        description: '10 тренировок в выходные',
        unlocked: s.weekendWorkouts >= 10,
        category: 'Постоянство',
        progress: s.weekendWorkouts.toDouble(),
        threshold: 10,
        rarity: AchievementRarity.uncommon,
      ),
      Achievement(
        id: 'weekend_50',
        emoji: '💪🏖️',
        title: 'Нет выходных',
        description: '50 тренировок в выходные',
        unlocked: s.weekendWorkouts >= 50,
        category: 'Постоянство',
        progress: s.weekendWorkouts.toDouble(),
        threshold: 50,
        rarity: AchievementRarity.epic,
      ),
    ];
  }

  // ── Wellness ───────────────────────────────────────────────────────────────

  static List<Achievement> _wellnessAchievements(AchievementStats s) {
    return [
      Achievement(
        id: 'wellness_7',
        emoji: '🧘',
        title: 'Осознанность',
        description: '7 дней check-in подряд',
        unlocked: s.wellnessStreak >= 7,
        category: 'Wellness',
        progress: s.wellnessStreak.toDouble(),
        threshold: 7,
        rarity: AchievementRarity.uncommon,
      ),
      Achievement(
        id: 'wellness_30',
        emoji: '🧠',
        title: 'Месяц заботы',
        description: '30 check-in за всё время',
        unlocked: s.totalWellnessLogs >= 30,
        category: 'Wellness',
        progress: s.totalWellnessLogs.toDouble(),
        threshold: 30,
        rarity: AchievementRarity.rare,
      ),
      Achievement(
        id: 'wellness_streak_30',
        emoji: '💚',
        title: 'Привычка',
        description: '30 дней check-in подряд',
        unlocked: s.wellnessStreak >= 30,
        category: 'Wellness',
        progress: s.wellnessStreak.toDouble(),
        threshold: 30,
        rarity: AchievementRarity.epic,
      ),
    ];
  }

  // ── Тело ───────────────────────────────────────────────────────────────────

  static List<Achievement> _bodyAchievements(AchievementStats s) {
    return [
      Achievement(
        id: 'body_1',
        emoji: '📏',
        title: 'Первый замер',
        description: 'Сохранён первый замер тела',
        unlocked: s.totalBodyMetrics >= 1,
        category: 'Тело',
        progress: s.totalBodyMetrics.toDouble(),
        threshold: 1,
        rarity: AchievementRarity.common,
      ),
      Achievement(
        id: 'body_10',
        emoji: '📐',
        title: 'Систематик',
        description: '10 замеров тела',
        unlocked: s.totalBodyMetrics >= 10,
        category: 'Тело',
        progress: s.totalBodyMetrics.toDouble(),
        threshold: 10,
        rarity: AchievementRarity.uncommon,
      ),
      Achievement(
        id: 'body_50',
        emoji: '📊',
        title: 'Аналитик тела',
        description: '50 замеров тела',
        unlocked: s.totalBodyMetrics >= 50,
        category: 'Тело',
        progress: s.totalBodyMetrics.toDouble(),
        threshold: 50,
        rarity: AchievementRarity.rare,
      ),
    ];
  }

  // ── Разнообразие ───────────────────────────────────────────────────────────

  static List<Achievement> _varietyAchievements(AchievementStats s) {
    return [
      Achievement(
        id: 'exercises_10',
        emoji: '🔀',
        title: 'Разносторонний',
        description: 'Попробовано 10 разных упражнений',
        unlocked: s.uniqueExercises >= 10,
        category: 'Разнообразие',
        progress: s.uniqueExercises.toDouble(),
        threshold: 10,
        rarity: AchievementRarity.common,
      ),
      Achievement(
        id: 'exercises_30',
        emoji: '🎲',
        title: 'Исследователь',
        description: 'Попробовано 30 разных упражнений',
        unlocked: s.uniqueExercises >= 30,
        category: 'Разнообразие',
        progress: s.uniqueExercises.toDouble(),
        threshold: 30,
        rarity: AchievementRarity.uncommon,
      ),
      Achievement(
        id: 'exercises_60',
        emoji: '🧬',
        title: 'Энциклопедия',
        description: 'Попробовано 60 разных упражнений',
        unlocked: s.uniqueExercises >= 60,
        category: 'Разнообразие',
        progress: s.uniqueExercises.toDouble(),
        threshold: 60,
        rarity: AchievementRarity.rare,
      ),
      Achievement(
        id: 'muscle_groups_5',
        emoji: '🏋️‍♂️',
        title: 'Универсал',
        description: '5 групп мышц за последние 30 дней',
        unlocked: s.uniqueMuscleGroups >= 5,
        category: 'Разнообразие',
        progress: s.uniqueMuscleGroups.toDouble(),
        threshold: 5,
        rarity: AchievementRarity.uncommon,
      ),
    ];
  }

  // ── Социальные ─────────────────────────────────────────────────────────────

  static List<Achievement> _socialAchievements(AchievementStats s) {
    return [
      Achievement(
        id: 'export_1',
        emoji: '📤',
        title: 'Поделился',
        description: 'Первый экспорт или шаринг результата',
        unlocked: s.exportCount >= 1,
        category: 'Социальные',
        progress: s.exportCount.toDouble(),
        threshold: 1,
        rarity: AchievementRarity.common,
      ),
      Achievement(
        id: 'export_10',
        emoji: '📣',
        title: 'Амбассадор',
        description: '10 экспортов / шарингов',
        unlocked: s.exportCount >= 10,
        category: 'Социальные',
        progress: s.exportCount.toDouble(),
        threshold: 10,
        rarity: AchievementRarity.rare,
      ),
    ];
  }

  // ── Скрытые ────────────────────────────────────────────────────────────────

  static List<Achievement> _hiddenAchievements(AchievementStats s) {
    return [
      Achievement(
        id: 'hidden_marathon',
        emoji: '🏃',
        title: 'Марафонец',
        description: 'Тренировка длительностью более 90 минут',
        unlocked: s.longestWorkoutMin >= 90,
        category: 'Скрытые',
        progress: s.longestWorkoutMin.toDouble(),
        threshold: 90,
        rarity: AchievementRarity.rare,
        hidden: true,
      ),
      Achievement(
        id: 'hidden_berserker',
        emoji: '😤',
        title: 'Берсерк',
        description: 'RPE 10 в трёх тренировках',
        unlocked: s.rpe10Count >= 3,
        category: 'Скрытые',
        progress: s.rpe10Count.toDouble(),
        threshold: 3,
        rarity: AchievementRarity.epic,
        hidden: true,
      ),
      Achievement(
        id: 'hidden_jan1',
        emoji: '🎆',
        title: '1 января',
        description: 'Тренировка в первый день года',
        unlocked: s.jan1Workout,
        category: 'Скрытые',
        progress: s.jan1Workout ? 1 : 0,
        threshold: 1,
        rarity: AchievementRarity.epic,
        hidden: true,
      ),
      Achievement(
        id: 'hidden_volume_200',
        emoji: '🗿',
        title: 'Атлант',
        description: 'Суммарно 200 000 кг за всё время',
        unlocked: s.totalVolumeKg >= 200000,
        category: 'Скрытые',
        progress: s.totalVolumeKg,
        threshold: 200000,
        rarity: AchievementRarity.legendary,
        hidden: true,
      ),
    ];
  }

  // ── Helper ─────────────────────────────────────────────────────────────────

  static List<Achievement> _buildList(
    List<(int, String, String, String, AchievementRarity)> defs,
    double current,
    String category,
  ) {
    return defs.map((d) => Achievement(
      id: '${category.toLowerCase()}_${d.$1}',
      emoji: d.$2,
      title: d.$3,
      description: d.$4,
      unlocked: current >= d.$1,
      category: category,
      progress: current,
      threshold: d.$1.toDouble(),
      rarity: d.$5,
    )).toList();
  }
}
