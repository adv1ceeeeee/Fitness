import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/achievement_service.dart';

void main() {
  AchievementStats stats({
    int totalWorkouts = 0,
    int bestStreak = 0,
    int totalPrs = 0,
    double totalVolumeKg = 0,
    int earlyWorkouts = 0,
    int lateWorkouts = 0,
    int weekendWorkouts = 0,
    int wellnessStreak = 0,
    int totalWellnessLogs = 0,
    int totalBodyMetrics = 0,
    int uniqueExercises = 0,
    int uniqueMuscleGroups = 0,
    int exportCount = 0,
    int rpe10Count = 0,
    bool jan1Workout = false,
    int longestWorkoutMin = 0,
  }) =>
      AchievementStats(
        totalWorkouts: totalWorkouts,
        bestStreak: bestStreak,
        totalPrs: totalPrs,
        totalVolumeKg: totalVolumeKg,
        earlyWorkouts: earlyWorkouts,
        lateWorkouts: lateWorkouts,
        weekendWorkouts: weekendWorkouts,
        wellnessStreak: wellnessStreak,
        totalWellnessLogs: totalWellnessLogs,
        totalBodyMetrics: totalBodyMetrics,
        uniqueExercises: uniqueExercises,
        uniqueMuscleGroups: uniqueMuscleGroups,
        exportCount: exportCount,
        rpe10Count: rpe10Count,
        jan1Workout: jan1Workout,
        longestWorkoutMin: longestWorkoutMin,
      );

  List<Achievement> build({
    int totalWorkouts = 0,
    int bestStreak = 0,
    int totalPrs = 0,
    double totalVolumeKg = 0,
    int earlyWorkouts = 0,
    int lateWorkouts = 0,
    int weekendWorkouts = 0,
    int wellnessStreak = 0,
    int totalWellnessLogs = 0,
    int totalBodyMetrics = 0,
    int uniqueExercises = 0,
    int uniqueMuscleGroups = 0,
    int exportCount = 0,
    int rpe10Count = 0,
    bool jan1Workout = false,
    int longestWorkoutMin = 0,
  }) =>
      AchievementService.buildFromStats(stats(
        totalWorkouts: totalWorkouts,
        bestStreak: bestStreak,
        totalPrs: totalPrs,
        totalVolumeKg: totalVolumeKg,
        earlyWorkouts: earlyWorkouts,
        lateWorkouts: lateWorkouts,
        weekendWorkouts: weekendWorkouts,
        wellnessStreak: wellnessStreak,
        totalWellnessLogs: totalWellnessLogs,
        totalBodyMetrics: totalBodyMetrics,
        uniqueExercises: uniqueExercises,
        uniqueMuscleGroups: uniqueMuscleGroups,
        exportCount: exportCount,
        rpe10Count: rpe10Count,
        jan1Workout: jan1Workout,
        longestWorkoutMin: longestWorkoutMin,
      ));

  // ── Core categories ───────────────────────────────────────────────────────

  group('workout achievements', () {
    test('all locked when no workouts', () {
      final list = build();
      final workouts = list.where((a) => a.category == 'Тренировки');
      expect(workouts.every((a) => !a.unlocked), isTrue);
    });

    test('1 workout unlocks first only', () {
      final list = build(totalWorkouts: 1);
      final unlocked = list.where((a) => a.unlocked).map((a) => a.id).toSet();
      expect(unlocked.contains('тренировки_1'), isTrue);
    });

    test('250 workouts unlocks all workout achievements', () {
      final list = build(totalWorkouts: 250);
      final workoutAchievements = list.where((a) => a.category == 'Тренировки');
      expect(workoutAchievements.every((a) => a.unlocked), isTrue);
    });

    test('250 workouts unlocks legendary achievement', () {
      final list = build(totalWorkouts: 250);
      final legendary = list.where(
          (a) => a.category == 'Тренировки' && a.rarity == AchievementRarity.legendary);
      expect(legendary.every((a) => a.unlocked), isTrue);
    });
  });

  group('streak achievements', () {
    test('3-day streak unlocks first streak', () {
      final list = build(bestStreak: 3);
      final unlocked = list.where((a) => a.unlocked && a.category == 'Серия');
      expect(unlocked.length, 1);
    });

    test('100-day streak unlocks all streak achievements', () {
      final list = build(bestStreak: 100);
      final streaks = list.where((a) => a.category == 'Серия');
      expect(streaks.every((a) => a.unlocked), isTrue);
    });
  });

  group('PR achievements', () {
    test('1 PR unlocks first', () {
      final list = build(totalPrs: 1);
      final unlocked = list.where((a) => a.unlocked && a.category == 'Рекорды');
      expect(unlocked.length, 1);
    });

    test('50 PRs unlocks all PR achievements', () {
      final list = build(totalPrs: 50);
      final prs = list.where((a) => a.category == 'Рекорды');
      expect(prs.every((a) => a.unlocked), isTrue);
    });
  });

  group('volume achievements', () {
    test('1000 kg unlocks first volume', () {
      final list = build(totalVolumeKg: 1000);
      final unlocked = list.where((a) => a.unlocked && a.category == 'Объём');
      expect(unlocked.length, 1);
    });

    test('500000 kg unlocks all volume achievements', () {
      final list = build(totalVolumeKg: 500000);
      final volumes = list.where((a) => a.category == 'Объём');
      expect(volumes.every((a) => a.unlocked), isTrue);
    });
  });

  // ── New categories ────────────────────────────────────────────────────────

  group('consistency achievements', () {
    test('5 early workouts unlocks early bird', () {
      final list = build(earlyWorkouts: 5);
      final unlocked = list.where((a) => a.unlocked && a.category == 'Постоянство');
      expect(unlocked.length, 1);
      expect(unlocked.first.id, 'early_5');
    });

    test('5 late workouts unlocks night owl', () {
      final list = build(lateWorkouts: 5);
      final unlocked = list.where((a) => a.unlocked && a.category == 'Постоянство');
      expect(unlocked.length, 1);
      expect(unlocked.first.id, 'late_5');
    });

    test('50 weekend workouts unlocks all weekend achievements', () {
      final list = build(weekendWorkouts: 50);
      final weekend = list.where(
          (a) => a.category == 'Постоянство' && a.id.startsWith('weekend_'));
      expect(weekend.every((a) => a.unlocked), isTrue);
    });
  });

  group('wellness achievements', () {
    test('7-day wellness streak unlocks first', () {
      final list = build(wellnessStreak: 7);
      final unlocked = list.where((a) => a.unlocked && a.category == 'Wellness');
      expect(unlocked.length, 1);
    });

    test('30 logs and 30-day streak unlocks all wellness', () {
      final list = build(wellnessStreak: 30, totalWellnessLogs: 30);
      final wellness = list.where((a) => a.category == 'Wellness');
      expect(wellness.every((a) => a.unlocked), isTrue);
    });
  });

  group('body achievements', () {
    test('1 body metric unlocks first', () {
      final list = build(totalBodyMetrics: 1);
      final unlocked = list.where((a) => a.unlocked && a.category == 'Тело');
      expect(unlocked.length, 1);
    });

    test('50 body metrics unlocks all body achievements', () {
      final list = build(totalBodyMetrics: 50);
      final body = list.where((a) => a.category == 'Тело');
      expect(body.every((a) => a.unlocked), isTrue);
    });
  });

  group('variety achievements', () {
    test('10 unique exercises unlocks first', () {
      final list = build(uniqueExercises: 10);
      final unlocked = list.where((a) => a.unlocked && a.category == 'Разнообразие');
      expect(unlocked.length, 1);
    });

    test('60 exercises + 5 muscle groups unlocks all variety', () {
      final list = build(uniqueExercises: 60, uniqueMuscleGroups: 5);
      final variety = list.where((a) => a.category == 'Разнообразие');
      expect(variety.every((a) => a.unlocked), isTrue);
    });
  });

  group('social achievements', () {
    test('1 export unlocks first', () {
      final list = build(exportCount: 1);
      final unlocked = list.where((a) => a.unlocked && a.category == 'Социальные');
      expect(unlocked.length, 1);
    });

    test('10 exports unlocks all social', () {
      final list = build(exportCount: 10);
      final social = list.where((a) => a.category == 'Социальные');
      expect(social.every((a) => a.unlocked), isTrue);
    });
  });

  // ── Hidden achievements ────────────────────────────────────────────────────

  group('hidden achievements', () {
    test('all hidden achievements have hidden=true', () {
      final list = build();
      final hidden = list.where((a) => a.category == 'Скрытые');
      expect(hidden.every((a) => a.hidden), isTrue);
    });

    test('90 min workout unlocks marathon', () {
      final list = build(longestWorkoutMin: 90);
      final marathon = list.firstWhere((a) => a.id == 'hidden_marathon');
      expect(marathon.unlocked, isTrue);
    });

    test('3 RPE-10 sessions unlocks berserker', () {
      final list = build(rpe10Count: 3);
      final berserker = list.firstWhere((a) => a.id == 'hidden_berserker');
      expect(berserker.unlocked, isTrue);
    });

    test('jan1 workout unlocks jan1 achievement', () {
      final list = build(jan1Workout: true);
      final jan1 = list.firstWhere((a) => a.id == 'hidden_jan1');
      expect(jan1.unlocked, isTrue);
    });

    test('200000 kg volume unlocks hidden atlas', () {
      final list = build(totalVolumeKg: 200000);
      final atlas = list.firstWhere((a) => a.id == 'hidden_volume_200');
      expect(atlas.unlocked, isTrue);
    });
  });

  // ── Rarity ─────────────────────────────────────────────────────────────────

  group('rarity', () {
    test('every achievement has a rarity', () {
      final list = build();
      for (final a in list) {
        expect(AchievementRarity.values.contains(a.rarity), isTrue);
      }
    });

    test('xpReward values match rarity tiers', () {
      expect(AchievementRarity.common.xpReward, 50);
      expect(AchievementRarity.uncommon.xpReward, 75);
      expect(AchievementRarity.rare.xpReward, 100);
      expect(AchievementRarity.epic.xpReward, 150);
      expect(AchievementRarity.legendary.xpReward, 200);
    });

    test('legendary achievements exist', () {
      final list = build();
      final legendaries =
          list.where((a) => a.rarity == AchievementRarity.legendary);
      expect(legendaries.isNotEmpty, isTrue);
    });
  });

  // ── General properties ─────────────────────────────────────────────────────

  group('general properties', () {
    test('each achievement has non-empty id, emoji, title, description', () {
      final list = build();
      for (final a in list) {
        expect(a.id, isNotEmpty);
        expect(a.emoji, isNotEmpty);
        expect(a.title, isNotEmpty);
        expect(a.description, isNotEmpty);
      }
    });

    test('achievement ids are unique', () {
      final list = build();
      final ids = list.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('progressFraction clamps between 0 and 1', () {
      final list = build(
        totalWorkouts: 999,
        bestStreak: 999,
        totalPrs: 999,
        totalVolumeKg: 999999,
        earlyWorkouts: 999,
        lateWorkouts: 999,
        weekendWorkouts: 999,
        wellnessStreak: 999,
        totalWellnessLogs: 999,
        totalBodyMetrics: 999,
        uniqueExercises: 999,
        uniqueMuscleGroups: 999,
        exportCount: 999,
        rpe10Count: 999,
        jan1Workout: true,
        longestWorkoutMin: 999,
      );
      for (final a in list) {
        expect(a.progressFraction, inInclusiveRange(0.0, 1.0));
      }
    });

    test('category field is non-empty for all achievements', () {
      final list = build();
      for (final a in list) {
        expect(a.category, isNotEmpty);
      }
    });

    test('total achievement count is ~40', () {
      final list = build();
      expect(list.length, greaterThanOrEqualTo(35));
      expect(list.length, lessThanOrEqualTo(50));
    });
  });
}
