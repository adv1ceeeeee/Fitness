import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/services/local_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    await AppStorage.init();
  });

  // ── weeklySummaryEnabled ───────────────────────────────────────────────────

  group('AppStorage.weeklySummaryEnabled', () {
    test('returns true by default', () {
      expect(AppStorage.weeklySummaryEnabled, isTrue);
    });

    test('can be disabled and re-enabled', () async {
      await AppStorage.setWeeklySummaryEnabled(false);
      expect(AppStorage.weeklySummaryEnabled, isFalse);

      await AppStorage.setWeeklySummaryEnabled(true);
      expect(AppStorage.weeklySummaryEnabled, isTrue);
    });
  });

  // ── lastWeeklySummaryShownWeek ─────────────────────────────────────────────

  group('AppStorage.lastWeeklySummaryShownWeek', () {
    test('returns null when never set', () {
      expect(AppStorage.lastWeeklySummaryShownWeek, isNull);
    });

    test('returns value after setting it', () async {
      await AppStorage.setLastWeeklySummaryShownWeek('2026-03-15');
      expect(AppStorage.lastWeeklySummaryShownWeek, '2026-03-15');
    });

    test('overwrites previous value', () async {
      await AppStorage.setLastWeeklySummaryShownWeek('2026-03-08');
      await AppStorage.setLastWeeklySummaryShownWeek('2026-03-15');
      expect(AppStorage.lastWeeklySummaryShownWeek, '2026-03-15');
    });
  });

  // ── seenAchievementIds ─────────────────────────────────────────────────────

  group('AppStorage.seenAchievementIds', () {
    test('returns empty list when never set', () {
      expect(AppStorage.seenAchievementIds, isEmpty);
    });

    test('returns saved list after setting', () async {
      await AppStorage.setSeenAchievementIds(['workouts_1', 'streak_3']);
      expect(AppStorage.seenAchievementIds, ['workouts_1', 'streak_3']);
    });

    test('overwrites previous list', () async {
      await AppStorage.setSeenAchievementIds(['workouts_1']);
      await AppStorage.setSeenAchievementIds(['workouts_1', 'workouts_5']);
      expect(AppStorage.seenAchievementIds, ['workouts_1', 'workouts_5']);
    });

    test('empty list can be stored', () async {
      await AppStorage.setSeenAchievementIds(['workouts_1']);
      await AppStorage.setSeenAchievementIds([]);
      expect(AppStorage.seenAchievementIds, isEmpty);
    });
  });
}
