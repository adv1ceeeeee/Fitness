import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/recsys_service.dart';

void main() {
  group('evaluateProgression', () {
    test('returns null when last is null', () {
      expect(evaluateProgression(null), isNull);
    });

    test('returns null when weight is zero', () {
      final rec = evaluateProgression(
          {'weight': 0.0, 'reps': 10, 'rpe': 6, 'reps_target': 10});
      expect(rec, isNull);
    });

    test('returns null when weight is missing', () {
      final rec = evaluateProgression({'reps': 10, 'rpe': 6});
      expect(rec, isNull);
    });

    test('decrease: RPE >= 9 in both sessions', () {
      final rec = evaluateProgression({
        'weight': 100.0, 'reps': 8, 'reps_target': 8, 'rpe': 9,
        'prev': {'weight': 100.0, 'reps': 8, 'reps_target': 8, 'rpe': 9},
      });
      expect(rec!.direction, ProgressionDirection.decrease);
    });

    test('decrease not triggered when only last session has RPE 9', () {
      final rec = evaluateProgression({
        'weight': 100.0, 'reps': 8, 'reps_target': 8, 'rpe': 9,
        'prev': {'weight': 100.0, 'reps': 8, 'reps_target': 8, 'rpe': 7},
      });
      expect(rec?.direction, isNot(ProgressionDirection.decrease));
    });

    test('maintain: failed reps vs target', () {
      final rec = evaluateProgression({
        'weight': 100.0, 'reps': 6, 'reps_target': 8, 'rpe': 8,
      });
      expect(rec!.direction, ProgressionDirection.maintain);
      expect(rec.message, contains('6 из 8'));
    });

    test('maintain takes priority over decrease when reps failed', () {
      final rec = evaluateProgression({
        'weight': 100.0, 'reps': 5, 'reps_target': 8, 'rpe': 9,
        'prev': {'weight': 100.0, 'reps': 6, 'reps_target': 8, 'rpe': 9},
      });
      // decrease requires both sessions RPE >= 9, but failed reps = maintain
      expect(rec!.direction, ProgressionDirection.maintain);
    });

    test('increase: RPE <= 7 in both sessions + hit target', () {
      final rec = evaluateProgression({
        'weight': 80.0, 'reps': 10, 'reps_target': 10, 'rpe': 7,
        'prev': {'weight': 80.0, 'reps': 10, 'reps_target': 10, 'rpe': 6},
      });
      expect(rec!.direction, ProgressionDirection.increase);
      expect(rec.message, contains('7'));
      expect(rec.message, contains('6'));
    });

    test('increase: RPE <= 6 in single session + hit target', () {
      final rec = evaluateProgression({
        'weight': 80.0, 'reps': 10, 'reps_target': 10, 'rpe': 6,
      });
      expect(rec!.direction, ProgressionDirection.increase);
    });

    test('no increase when RPE 7 in single session only', () {
      final rec = evaluateProgression({
        'weight': 80.0, 'reps': 10, 'reps_target': 10, 'rpe': 7,
      });
      expect(rec, isNull);
    });

    test('no recommendation when rpe is null', () {
      final rec = evaluateProgression({
        'weight': 80.0, 'reps': 10, 'reps_target': 10, 'rpe': null,
      });
      expect(rec, isNull);
    });

    test('hit target when reps_target is null', () {
      // no target = always considered hit
      final rec = evaluateProgression({
        'weight': 80.0, 'reps': 10, 'reps_target': null, 'rpe': 6,
        'prev': {'weight': 80.0, 'reps': 10, 'reps_target': null, 'rpe': 7},
      });
      expect(rec!.direction, ProgressionDirection.increase);
    });
  });
}
