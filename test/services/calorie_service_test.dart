import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/calorie_service.dart';

void main() {
  group('estimateSetKcal', () {
    test('returns 0.0 for zero reps', () {
      expect(estimateSetKcal(category: 'chest', reps: 0), 0.0);
    });

    test('returns 0.0 for negative reps', () {
      expect(estimateSetKcal(category: 'chest', reps: -5), 0.0);
    });

    test('clamps result to minimum 0.3 kcal', () {
      // 1 rep at low RPE, light bodyweight -> still at least 0.3
      final result = estimateSetKcal(category: 'arms', reps: 1, rpe: 1, userWeightKg: 40.0);
      expect(result, greaterThanOrEqualTo(0.3));
    });

    test('clamps result to maximum 50 kcal', () {
      // extreme: 200 reps, heavy bodyweight, max RPE
      final result = estimateSetKcal(category: 'legs', reps: 200, rpe: 10, userWeightKg: 200.0);
      expect(result, lessThanOrEqualTo(50.0));
    });

    test('uses fallback MET 4.5 for unknown category', () {
      final known = estimateSetKcal(category: 'arms', reps: 10, rpe: 7, userWeightKg: 75.0);
      final unknown = estimateSetKcal(category: 'unknown', reps: 10, rpe: 7, userWeightKg: 75.0);
      // Unknown category (MET 4.5) vs arms (MET 3.5): unknown should be higher
      expect(unknown, greaterThan(known));
    });

    test('higher RPE yields more kcal (same reps and weight)', () {
      final low = estimateSetKcal(category: 'chest', reps: 10, rpe: 5, userWeightKg: 75.0);
      final high = estimateSetKcal(category: 'chest', reps: 10, rpe: 9, userWeightKg: 75.0);
      expect(high, greaterThan(low));
    });

    test('heavier user yields more kcal', () {
      final light = estimateSetKcal(category: 'legs', reps: 10, rpe: 7, userWeightKg: 60.0);
      final heavy = estimateSetKcal(category: 'legs', reps: 10, rpe: 7, userWeightKg: 100.0);
      expect(heavy, greaterThan(light));
    });

    test('cardio category yields more kcal than arms category', () {
      final arms = estimateSetKcal(category: 'arms', reps: 15, rpe: 7, userWeightKg: 75.0);
      final cardio = estimateSetKcal(category: 'cardio', reps: 15, rpe: 7, userWeightKg: 75.0);
      expect(cardio, greaterThan(arms));
    });

    test('defaults to RPE 7 when rpe is null', () {
      final withNull = estimateSetKcal(category: 'back', reps: 10, rpe: null, userWeightKg: 75.0);
      final with7 = estimateSetKcal(category: 'back', reps: 10, rpe: 7, userWeightKg: 75.0);
      expect(withNull, equals(with7));
    });

    test('defaults to 75 kg when userWeightKg is null', () {
      final withNull = estimateSetKcal(category: 'chest', reps: 10, rpe: 7, userWeightKg: null);
      final with75 = estimateSetKcal(category: 'chest', reps: 10, rpe: 7, userWeightKg: 75.0);
      expect(withNull, equals(with75));
    });

    test('result is rounded to 1 decimal place', () {
      final result = estimateSetKcal(category: 'chest', reps: 8, rpe: 7, userWeightKg: 75.0);
      final asString = result.toString();
      final decimals = asString.contains('.') ? asString.split('.').last.length : 0;
      expect(decimals, lessThanOrEqualTo(1));
    });
  });

  group('totalSessionKcal', () {
    test('sums all kcal values', () {
      expect(totalSessionKcal([1.5, 2.3, 3.2]), closeTo(7.0, 0.001));
    });

    test('returns 0 for empty iterable', () {
      expect(totalSessionKcal([]), 0.0);
    });

    test('handles single value', () {
      expect(totalSessionKcal([4.2]), 4.2);
    });
  });
}
