import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/recsys_service.dart';

void main() {
  group('evaluateWellnessCorrelation', () {
    test('returns null for empty list', () {
      expect(evaluateWellnessCorrelation([]), isNull);
    });

    test('returns rec for single entry', () {
      final rec = evaluateWellnessCorrelation([
        {
          'exerciseId': 'e1',
          'exerciseName': 'Жим лёжа',
          'goodSleepAvgKg': 100.0,
          'badSleepAvgKg': 90.0,
          'dropPct': 10.0,
          'sessionCount': 20,
        },
      ]);
      expect(rec, isNotNull);
      expect(rec!.exerciseName, 'Жим лёжа');
      expect(rec.dropPct, 10.0);
      expect(rec.sessionCount, 20);
    });

    test('picks first entry (already sorted by dropPct desc)', () {
      final rec = evaluateWellnessCorrelation([
        {
          'exerciseName': 'Приседания',
          'goodSleepAvgKg': 120.0,
          'badSleepAvgKg': 100.0,
          'dropPct': 16.7,
          'sessionCount': 18,
        },
        {
          'exerciseName': 'Жим лёжа',
          'goodSleepAvgKg': 100.0,
          'badSleepAvgKg': 90.0,
          'dropPct': 10.0,
          'sessionCount': 20,
        },
      ]);
      expect(rec!.exerciseName, 'Приседания');
    });

    test('message contains exercise name', () {
      final rec = evaluateWellnessCorrelation([
        {
          'exerciseName': 'Тяга штанги',
          'goodSleepAvgKg': 100.0,
          'badSleepAvgKg': 88.0,
          'dropPct': 12.0,
          'sessionCount': 15,
        },
      ]);
      expect(rec!.message, contains('Тяга штанги'));
    });

    test('message contains drop percentage', () {
      final rec = evaluateWellnessCorrelation([
        {
          'exerciseName': 'Жим',
          'goodSleepAvgKg': 100.0,
          'badSleepAvgKg': 92.0,
          'dropPct': 8.0,
          'sessionCount': 12,
        },
      ]);
      expect(rec!.message, contains('8%'));
    });

    test('message contains session count', () {
      final rec = evaluateWellnessCorrelation([
        {
          'exerciseName': 'Жим',
          'goodSleepAvgKg': 100.0,
          'badSleepAvgKg': 90.0,
          'dropPct': 10.0,
          'sessionCount': 24,
        },
      ]);
      expect(rec!.message, contains('24'));
    });

    test('message contains both weight values (integer)', () {
      final rec = evaluateWellnessCorrelation([
        {
          'exerciseName': 'Жим',
          'goodSleepAvgKg': 100.0,
          'badSleepAvgKg': 90.0,
          'dropPct': 10.0,
          'sessionCount': 10,
        },
      ]);
      expect(rec!.message, contains('100 кг'));
      expect(rec.message, contains('90 кг'));
    });

    test('message contains decimal weights', () {
      final rec = evaluateWellnessCorrelation([
        {
          'exerciseName': 'Жим',
          'goodSleepAvgKg': 97.5,
          'badSleepAvgKg': 85.5,
          'dropPct': 12.3,
          'sessionCount': 10,
        },
      ]);
      expect(rec!.message, contains('97.5 кг'));
      expect(rec.message, contains('85.5 кг'));
    });

    test('rec fields match input data', () {
      final rec = evaluateWellnessCorrelation([
        {
          'exerciseName': 'Приседания',
          'goodSleepAvgKg': 120.0,
          'badSleepAvgKg': 105.0,
          'dropPct': 12.5,
          'sessionCount': 30,
        },
      ]);
      expect(rec!.goodSleepAvgKg, 120.0);
      expect(rec.badSleepAvgKg, 105.0);
      expect(rec.dropPct, 12.5);
      expect(rec.sessionCount, 30);
    });
  });
}
