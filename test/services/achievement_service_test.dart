import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/achievement_service.dart';

void main() {
  // Helper: build with defaults for new params (prs=0, volumeKg=0)
  List<Achievement> build(int workouts, int streak,
          {int prs = 0, double volumeKg = 0}) =>
      AchievementService.buildFromStats(workouts, streak, prs, volumeKg);

  group('AchievementService.buildFromStats', () {
    test('returns 19 achievements total (6 workout + 5 streak + 4 pr + 4 volume)', () {
      final list = build(0, 0);
      expect(list.length, 19);
    });

    test('all locked when no workouts and no streak', () {
      final list = build(0, 0);
      expect(list.every((a) => !a.unlocked), isTrue);
    });

    test('first workout unlocks workouts_1 only', () {
      final list = build(1, 0);
      final unlocked = list.where((a) => a.unlocked).map((a) => a.id).toSet();
      expect(unlocked, {'workouts_1'});
    });

    test('5 workouts unlocks workouts_1 and workouts_5', () {
      final list = build(5, 0);
      final unlocked = list.where((a) => a.unlocked).map((a) => a.id).toSet();
      expect(unlocked.contains('workouts_1'), isTrue);
      expect(unlocked.contains('workouts_5'), isTrue);
      expect(unlocked.contains('workouts_10'), isFalse);
    });

    test('10 workouts unlocks 1,5,10 but not 25', () {
      final list = build(10, 0);
      final unlocked = list.where((a) => a.unlocked).map((a) => a.id).toSet();
      expect(unlocked.containsAll(['workouts_1', 'workouts_5', 'workouts_10']), isTrue);
      expect(unlocked.contains('workouts_25'), isFalse);
    });

    test('100 workouts unlocks all workout achievements', () {
      final list = build(100, 0);
      final workoutAchievements = list.where((a) => a.id.startsWith('workouts_'));
      expect(workoutAchievements.every((a) => a.unlocked), isTrue);
    });

    test('boundary: 24 workouts does not unlock workouts_25', () {
      final list = build(24, 0);
      expect(list.firstWhere((a) => a.id == 'workouts_25').unlocked, isFalse);
    });

    test('boundary: 25 workouts unlocks workouts_25', () {
      final list = build(25, 0);
      expect(list.firstWhere((a) => a.id == 'workouts_25').unlocked, isTrue);
    });

    test('3-day streak unlocks streak_3 only', () {
      final list = build(0, 3);
      final unlocked = list.where((a) => a.unlocked).map((a) => a.id).toSet();
      expect(unlocked, {'streak_3'});
    });

    test('7-day streak unlocks streak_3 and streak_7, not streak_14', () {
      final list = build(0, 7);
      final unlocked = list.where((a) => a.unlocked).map((a) => a.id).toSet();
      expect(unlocked.containsAll(['streak_3', 'streak_7']), isTrue);
      expect(unlocked.contains('streak_14'), isFalse);
    });

    test('100-day streak unlocks all streak achievements', () {
      final list = build(0, 100);
      final streakAchievements = list.where((a) => a.id.startsWith('streak_'));
      expect(streakAchievements.every((a) => a.unlocked), isTrue);
    });

    test('mixed stats unlock correct subsets', () {
      final list = build(10, 7);
      final unlocked = list.where((a) => a.unlocked).map((a) => a.id).toSet();
      expect(unlocked.containsAll(['workouts_1', 'workouts_5', 'workouts_10']), isTrue);
      expect(unlocked.containsAll(['streak_3', 'streak_7']), isTrue);
      expect(unlocked.contains('workouts_25'), isFalse);
      expect(unlocked.contains('streak_14'), isFalse);
    });

    test('1 PR unlocks prs_1 only', () {
      final list = build(0, 0, prs: 1);
      final unlocked = list.where((a) => a.unlocked).map((a) => a.id).toSet();
      expect(unlocked, {'prs_1'});
    });

    test('25 PRs unlocks all PR achievements', () {
      final list = build(0, 0, prs: 25);
      final prAchievements = list.where((a) => a.id.startsWith('prs_'));
      expect(prAchievements.every((a) => a.unlocked), isTrue);
    });

    test('1000 kg volume unlocks volume_1000 only', () {
      final list = build(0, 0, volumeKg: 1000);
      final unlocked = list.where((a) => a.unlocked).map((a) => a.id).toSet();
      expect(unlocked, {'volume_1000'});
    });

    test('100000 kg volume unlocks all volume achievements', () {
      final list = build(0, 0, volumeKg: 100000);
      final volAchievements = list.where((a) => a.id.startsWith('volume_'));
      expect(volAchievements.every((a) => a.unlocked), isTrue);
    });

    test('each achievement has non-empty id, emoji, title, description', () {
      final list = build(0, 0);
      for (final a in list) {
        expect(a.id, isNotEmpty);
        expect(a.emoji, isNotEmpty);
        expect(a.title, isNotEmpty);
        expect(a.description, isNotEmpty);
      }
    });

    test('achievement ids are unique', () {
      final list = build(0, 0);
      final ids = list.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('progressFraction clamps between 0 and 1', () {
      final list = build(200, 200, prs: 100, volumeKg: 200000);
      for (final a in list) {
        expect(a.progressFraction, inInclusiveRange(0.0, 1.0));
      }
    });

    test('category field is non-empty for all achievements', () {
      final list = build(0, 0);
      for (final a in list) {
        expect(a.category, isNotEmpty);
      }
    });
  });
}
