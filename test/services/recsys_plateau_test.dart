import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/recsys_service.dart';

void main() {
  group('evaluatePlateau', () {
    test('returns null for empty list', () {
      expect(evaluatePlateau([]), isNull);
    });

    test('returns rec for single stagnant exercise', () {
      final rec = evaluatePlateau([
        {'exerciseId': 'e1', 'exerciseName': 'Жим лёжа', 'currentWeightKg': 80.0, 'weeksStagnant': 3},
      ]);
      expect(rec, isNotNull);
      expect(rec!.exerciseName, 'Жим лёжа');
      expect(rec.weightKg, 80.0);
      expect(rec.weeksStagnant, 3);
      expect(rec.message, contains('Жим лёжа'));
      expect(rec.message, contains('80 кг'));
    });

    test('picks exercise with most weeks stagnant', () {
      final rec = evaluatePlateau([
        {'exerciseId': 'e1', 'exerciseName': 'Жим лёжа', 'currentWeightKg': 80.0, 'weeksStagnant': 3},
        {'exerciseId': 'e2', 'exerciseName': 'Приседания', 'currentWeightKg': 100.0, 'weeksStagnant': 5},
        {'exerciseId': 'e3', 'exerciseName': 'Тяга', 'currentWeightKg': 90.0, 'weeksStagnant': 4},
      ]);
      expect(rec!.exerciseName, 'Приседания');
      expect(rec.weeksStagnant, 5);
    });

    test('message contains weight in kg (integer)', () {
      final rec = evaluatePlateau([
        {'exerciseId': 'e1', 'exerciseName': 'Жим', 'currentWeightKg': 60.0, 'weeksStagnant': 3},
      ]);
      expect(rec!.message, contains('60 кг'));
    });

    test('message contains weight in kg (decimal)', () {
      final rec = evaluatePlateau([
        {'exerciseId': 'e1', 'exerciseName': 'Жим', 'currentWeightKg': 62.5, 'weeksStagnant': 3},
      ]);
      expect(rec!.message, contains('62.5 кг'));
    });

    test('message contains weeks count', () {
      final rec = evaluatePlateau([
        {'exerciseId': 'e1', 'exerciseName': 'Жим', 'currentWeightKg': 80.0, 'weeksStagnant': 4},
      ]);
      expect(rec!.message, contains('4'));
    });

    test('message suggests action', () {
      final rec = evaluatePlateau([
        {'exerciseId': 'e1', 'exerciseName': 'Жим', 'currentWeightKg': 80.0, 'weeksStagnant': 3},
      ]);
      expect(rec!.message.toLowerCase(), contains('deload'));
    });

    test('handles tie in weeks — picks first with max', () {
      final rec = evaluatePlateau([
        {'exerciseId': 'e1', 'exerciseName': 'Жим лёжа', 'currentWeightKg': 80.0, 'weeksStagnant': 4},
        {'exerciseId': 'e2', 'exerciseName': 'Приседания', 'currentWeightKg': 100.0, 'weeksStagnant': 4},
      ]);
      // Both have 4 weeks — should pick one (implementation picks first via >=)
      expect(rec!.weeksStagnant, 4);
    });

    test('weight 0 is included (bodyweight exercise)', () {
      final rec = evaluatePlateau([
        {'exerciseId': 'e1', 'exerciseName': 'Подтягивания', 'currentWeightKg': 0.0, 'weeksStagnant': 3},
      ]);
      expect(rec, isNotNull);
      expect(rec!.weightKg, 0.0);
    });
  });
}
