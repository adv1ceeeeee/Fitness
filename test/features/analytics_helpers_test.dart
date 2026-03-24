import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/screens/analytics/analytics_screen.dart';

void main() {
  // ─── weekdayVolumeFrom ─────────────────────────────────────────────────────

  group('weekdayVolumeFrom', () {
    test('returns empty map for empty input', () {
      expect(weekdayVolumeFrom({}), isEmpty);
    });

    test('skips zero-volume entries', () {
      final data = {
        DateTime(2026, 3, 16): 0.0, // Mon
        DateTime(2026, 3, 17): 100.0, // Tue
      };
      final result = weekdayVolumeFrom(data);
      expect(result.containsKey(DateTime.monday), isFalse);
      expect(result[DateTime.tuesday], 100.0);
    });

    test('averages multiple entries for the same weekday', () {
      final data = {
        DateTime(2026, 3, 2): 100.0, // Mon
        DateTime(2026, 3, 9): 200.0, // Mon
        DateTime(2026, 3, 16): 300.0, // Mon
      };
      final result = weekdayVolumeFrom(data);
      expect(result[DateTime.monday], 200.0); // (100+200+300)/3
    });

    test('handles each weekday independently', () {
      final data = {
        DateTime(2026, 3, 16): 60.0, // Mon
        DateTime(2026, 3, 17): 90.0, // Tue
        DateTime(2026, 3, 18): 120.0, // Wed
      };
      final result = weekdayVolumeFrom(data);
      expect(result[DateTime.monday], 60.0);
      expect(result[DateTime.tuesday], 90.0);
      expect(result[DateTime.wednesday], 120.0);
    });

    test('negative volume entries are skipped', () {
      final data = {
        DateTime(2026, 3, 16): -5.0, // Mon — should be skipped
        DateTime(2026, 3, 17): 80.0, // Tue
      };
      final result = weekdayVolumeFrom(data);
      expect(result.containsKey(DateTime.monday), isFalse);
      expect(result[DateTime.tuesday], 80.0);
    });
  });

  // ─── bodyPeriodDelta ───────────────────────────────────────────────────────

  group('bodyPeriodDelta', () {
    test('returns null when cutoff is null', () {
      expect(
        bodyPeriodDelta(
          metricData: {'2026-01-01': 80.0, '2026-02-01': 79.0},
          cutoff: null,
          unit: ' кг',
        ),
        isNull,
      );
    });

    test('returns null when fewer than 2 entries in current window', () {
      final cutoff = DateTime(2026, 3, 1);
      // Only one entry after cutoff
      final result = bodyPeriodDelta(
        metricData: {
          '2026-01-01': 80.0,
          '2026-03-15': 79.0,
        },
        cutoff: cutoff,
        unit: ' кг',
      );
      expect(result, isNull);
    });

    test('returns null when no entries in previous window', () {
      // cutoff 90 days ago → prev window = 90 days before that = 180 days ago
      // No data at all before cutoff
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      final now = DateTime.now();
      final result = bodyPeriodDelta(
        metricData: {
          '${now.year}-${now.month.toString().padLeft(2, '0')}-01': 80.0,
          '${now.year}-${now.month.toString().padLeft(2, '0')}-10': 79.5,
        },
        cutoff: cutoff,
        unit: ' кг',
      );
      expect(result, isNull);
    });

    test('returns correct delta and unit', () {
      // cutoff = 30 days ago, so prev window = 30 days before that
      final today = DateTime.now();
      final cutoff = today.subtract(const Duration(days: 30));
      final prevDate = cutoff.subtract(const Duration(days: 15));
      final curDate1 = cutoff.add(const Duration(days: 5));
      final curDate2 = cutoff.add(const Duration(days: 20));

      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final result = bodyPeriodDelta(
        metricData: {
          fmt(prevDate): 82.0,
          fmt(curDate1): 81.0,
          fmt(curDate2): 79.5,
        },
        cutoff: cutoff,
        unit: ' кг',
      );
      expect(result, isNotNull);
      // curVal = 79.5, prevVal = 82.0 → delta = -2.5
      expect(result!.delta, closeTo(-2.5, 0.01));
      expect(result.unit, ' кг');
    });

    test('preserves unit string', () {
      final today = DateTime.now();
      final cutoff = today.subtract(const Duration(days: 30));
      final prevDate = cutoff.subtract(const Duration(days: 10));
      final curDate1 = cutoff.add(const Duration(days: 5));
      final curDate2 = cutoff.add(const Duration(days: 20));

      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final result = bodyPeriodDelta(
        metricData: {
          fmt(prevDate): 20.0,
          fmt(curDate1): 19.5,
          fmt(curDate2): 19.0,
        },
        cutoff: cutoff,
        unit: '%',
      );
      expect(result?.unit, '%');
    });
  });
}
