import 'package:flutter_test/flutter_test.dart';

// Pure deduplication logic mirroring AnalyticsService.getPersonalRecords().
//
// Input:
//   weRows  — list of workout_exercise rows with nested 'exercises' map
//   maxPerWe — map of workout_exercise_id → max weight recorded
//   datePerWe — map of workout_exercise_id → date string
//
// Output:
//   map of exercise_id → best record (highest weight across all workout variants)
//   sorted by exerciseName.

Map<String, Map<String, dynamic>> deduplicatePersonalRecords(
  List<Map<String, dynamic>> weRows,
  Map<String, double> maxPerWe,
  Map<String, String> datePerWe,
) {
  final bestByExercise = <String, Map<String, dynamic>>{};
  for (final we in weRows) {
    final ex = we['exercises'] as Map<String, dynamic>?;
    if (ex == null) continue;
    final exerciseId = ex['id'] as String;
    final weId = we['id'] as String;
    final w = maxPerWe[weId] ?? 0;
    if (!bestByExercise.containsKey(exerciseId) ||
        w > (bestByExercise[exerciseId]!['weightKg'] as double)) {
      bestByExercise[exerciseId] = {
        'exerciseId': exerciseId,
        'exerciseName': ex['name'] as String,
        'weightKg': w,
        'date': datePerWe[weId] ?? '',
      };
    }
  }
  return bestByExercise;
}

List<Map<String, dynamic>> sortedRecords(
        Map<String, Map<String, dynamic>> best) =>
    best.values.toList()
      ..sort((a, b) =>
          (a['exerciseName'] as String).compareTo(b['exerciseName'] as String));

void main() {
  group('Personal records deduplication', () {
    test('empty input returns empty result', () {
      final result = deduplicatePersonalRecords([], {}, {});
      expect(result, isEmpty);
    });

    test('single exercise with one workout_exercise entry', () {
      final weRows = [
        {
          'id': 'we-1',
          'exercises': {'id': 'ex-1', 'name': 'Жим лёжа'},
        }
      ];
      final maxPerWe = {'we-1': 100.0};
      final datePerWe = {'we-1': '2026-01-10'};

      final result = deduplicatePersonalRecords(weRows, maxPerWe, datePerWe);

      expect(result.length, 1);
      expect(result['ex-1']!['weightKg'], 100.0);
      expect(result['ex-1']!['exerciseName'], 'Жим лёжа');
      expect(result['ex-1']!['date'], '2026-01-10');
    });

    test('same exercise used in two workouts — keeps highest weight', () {
      final weRows = [
        {
          'id': 'we-1',
          'exercises': {'id': 'ex-squat', 'name': 'Приседания'},
        },
        {
          'id': 'we-2',
          'exercises': {'id': 'ex-squat', 'name': 'Приседания'},
        },
      ];
      final maxPerWe = {'we-1': 80.0, 'we-2': 120.0};
      final datePerWe = {'we-1': '2025-12-01', 'we-2': '2026-02-15'};

      final result = deduplicatePersonalRecords(weRows, maxPerWe, datePerWe);

      expect(result.length, 1);
      expect(result['ex-squat']!['weightKg'], 120.0);
      expect(result['ex-squat']!['date'], '2026-02-15');
    });

    test('same exercise in two workouts — first entry wins if it has higher weight', () {
      final weRows = [
        {
          'id': 'we-a',
          'exercises': {'id': 'ex-dl', 'name': 'Становая тяга'},
        },
        {
          'id': 'we-b',
          'exercises': {'id': 'ex-dl', 'name': 'Становая тяга'},
        },
      ];
      final maxPerWe = {'we-a': 200.0, 'we-b': 150.0};
      final datePerWe = {'we-a': '2026-03-01', 'we-b': '2025-11-01'};

      final result = deduplicatePersonalRecords(weRows, maxPerWe, datePerWe);

      expect(result['ex-dl']!['weightKg'], 200.0);
      expect(result['ex-dl']!['date'], '2026-03-01');
    });

    test('equal weights for same exercise — first entry is kept', () {
      final weRows = [
        {
          'id': 'we-x',
          'exercises': {'id': 'ex-bp', 'name': 'Жим'},
        },
        {
          'id': 'we-y',
          'exercises': {'id': 'ex-bp', 'name': 'Жим'},
        },
      ];
      final maxPerWe = {'we-x': 90.0, 'we-y': 90.0};
      final datePerWe = {'we-x': '2026-01-01', 'we-y': '2026-02-01'};

      final result = deduplicatePersonalRecords(weRows, maxPerWe, datePerWe);

      expect(result.length, 1);
      expect(result['ex-bp']!['weightKg'], 90.0);
    });

    test('multiple distinct exercises each get their own record', () {
      final weRows = [
        {
          'id': 'we-1',
          'exercises': {'id': 'ex-1', 'name': 'Жим лёжа'},
        },
        {
          'id': 'we-2',
          'exercises': {'id': 'ex-2', 'name': 'Тяга в наклоне'},
        },
        {
          'id': 'we-3',
          'exercises': {'id': 'ex-3', 'name': 'Приседания'},
        },
      ];
      final maxPerWe = {'we-1': 100.0, 'we-2': 80.0, 'we-3': 140.0};
      final datePerWe = {'we-1': '2026-01-01', 'we-2': '2026-01-02', 'we-3': '2026-01-03'};

      final result = deduplicatePersonalRecords(weRows, maxPerWe, datePerWe);

      expect(result.length, 3);
      expect(result['ex-1']!['weightKg'], 100.0);
      expect(result['ex-2']!['weightKg'], 80.0);
      expect(result['ex-3']!['weightKg'], 140.0);
    });

    test('workout_exercise with null exercises is skipped', () {
      final weRows = [
        {'id': 'we-null', 'exercises': null},
        {
          'id': 'we-ok',
          'exercises': {'id': 'ex-ok', 'name': 'Подтягивания'},
        },
      ];
      final maxPerWe = {'we-null': 60.0, 'we-ok': 70.0};
      final datePerWe = {'we-null': '2026-01-01', 'we-ok': '2026-01-02'};

      final result = deduplicatePersonalRecords(weRows, maxPerWe, datePerWe);

      expect(result.length, 1);
      expect(result.containsKey('ex-ok'), isTrue);
    });

    test('missing weight in maxPerWe defaults to 0', () {
      final weRows = [
        {
          'id': 'we-missing',
          'exercises': {'id': 'ex-m', 'name': 'Планка'},
        },
      ];
      final result = deduplicatePersonalRecords(weRows, {}, {});
      expect(result['ex-m']!['weightKg'], 0.0);
      expect(result['ex-m']!['date'], '');
    });
  });

  group('Personal records sorting', () {
    test('results are sorted alphabetically by exercise name', () {
      final records = {
        'ex-c': {'exerciseId': 'ex-c', 'exerciseName': 'Приседания', 'weightKg': 140.0, 'date': ''},
        'ex-a': {'exerciseId': 'ex-a', 'exerciseName': 'Жим лёжа', 'weightKg': 100.0, 'date': ''},
        'ex-b': {'exerciseId': 'ex-b', 'exerciseName': 'Подтягивания', 'weightKg': 90.0, 'date': ''},
      };

      final sorted = sortedRecords(records);

      expect(sorted[0]['exerciseName'], 'Жим лёжа');
      expect(sorted[1]['exerciseName'], 'Подтягивания');
      expect(sorted[2]['exerciseName'], 'Приседания');
    });

    test('single entry sorted list has one item', () {
      final records = {
        'ex-1': {'exerciseId': 'ex-1', 'exerciseName': 'Жим', 'weightKg': 100.0, 'date': ''}
      };
      expect(sortedRecords(records).length, 1);
    });

    test('empty map returns empty list', () {
      expect(sortedRecords({}), isEmpty);
    });
  });
}
