import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/screens/home/home_screen.dart';

void main() {
  // ── shouldShowWeeklySummaryOn ──────────────────────────────────────────────
  // Dart weekday: 1=Mon … 7=Sun
  // We show on Sun (7%7=0), Mon (1%7=1), Tue (2%7=2), hide Wed–Sat.

  group('shouldShowWeeklySummaryOn', () {
    test('returns true on Sunday', () {
      // 2026-03-15 is a Sunday
      expect(shouldShowWeeklySummaryOn(DateTime(2026, 3, 15)), isTrue);
    });

    test('returns true on Monday', () {
      // 2026-03-16 is a Monday
      expect(shouldShowWeeklySummaryOn(DateTime(2026, 3, 16)), isTrue);
    });

    test('returns true on Tuesday', () {
      // 2026-03-17 is a Tuesday
      expect(shouldShowWeeklySummaryOn(DateTime(2026, 3, 17)), isTrue);
    });

    test('returns false on Wednesday', () {
      expect(shouldShowWeeklySummaryOn(DateTime(2026, 3, 18)), isFalse);
    });

    test('returns false on Thursday', () {
      expect(shouldShowWeeklySummaryOn(DateTime(2026, 3, 19)), isFalse);
    });

    test('returns false on Friday', () {
      expect(shouldShowWeeklySummaryOn(DateTime(2026, 3, 20)), isFalse);
    });

    test('returns false on Saturday', () {
      expect(shouldShowWeeklySummaryOn(DateTime(2026, 3, 21)), isFalse);
    });
  });

  // ── weeklySummaryKeyFor ────────────────────────────────────────────────────
  // The key is always the "yyyy-MM-dd" of the preceding Sunday.

  group('weeklySummaryKeyFor', () {
    test('Sunday returns itself as the key', () {
      // 2026-03-15 Sun → key "2026-03-15"
      expect(weeklySummaryKeyFor(DateTime(2026, 3, 15)), '2026-03-15');
    });

    test('Monday returns the previous Sunday', () {
      // 2026-03-16 Mon → "2026-03-15"
      expect(weeklySummaryKeyFor(DateTime(2026, 3, 16)), '2026-03-15');
    });

    test('Tuesday returns the previous Sunday', () {
      // 2026-03-17 Tue → "2026-03-15"
      expect(weeklySummaryKeyFor(DateTime(2026, 3, 17)), '2026-03-15');
    });

    test('Saturday returns the previous Sunday', () {
      // 2026-03-21 Sat → "2026-03-15"
      expect(weeklySummaryKeyFor(DateTime(2026, 3, 21)), '2026-03-15');
    });

    test('month boundary: Tuesday 2026-03-03 → Sunday 2026-03-01', () {
      expect(weeklySummaryKeyFor(DateTime(2026, 3, 3)), '2026-03-01');
    });

    test('year boundary: Monday 2026-01-05 → Sunday 2026-01-04', () {
      expect(weeklySummaryKeyFor(DateTime(2026, 1, 5)), '2026-01-04');
    });

    test('key is zero-padded for single-digit months and days', () {
      // 2026-01-04 Sun → "2026-01-04"
      expect(weeklySummaryKeyFor(DateTime(2026, 1, 4)), '2026-01-04');
    });

    test('same-week Mon and Tue produce identical key', () {
      final keyMon = weeklySummaryKeyFor(DateTime(2026, 3, 16));
      final keyTue = weeklySummaryKeyFor(DateTime(2026, 3, 17));
      expect(keyMon, keyTue);
    });

    test('consecutive weeks produce different keys', () {
      final keyW1 = weeklySummaryKeyFor(DateTime(2026, 3, 15));
      final keyW2 = weeklySummaryKeyFor(DateTime(2026, 3, 22));
      expect(keyW1, isNot(keyW2));
    });
  });
}
