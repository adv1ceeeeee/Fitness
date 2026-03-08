import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/models/exercise.dart';

void main() {
  // ─── Session progress bar ─────────────────────────────────────────────────

  group('Session progress calculation', () {
    double progress(int before, int currentDone, int total) {
      if (total == 0) return 0.0;
      return ((before + currentDone) / total).clamp(0.0, 1.0);
    }

    test('zero total returns 0.0', () {
      expect(progress(0, 0, 0), 0.0);
    });

    test('nothing done returns 0.0', () {
      expect(progress(0, 0, 9), 0.0);
    });

    test('first set of first exercise', () {
      expect(progress(0, 1, 9), closeTo(1 / 9, 0.001));
    });

    test('all sets of first exercise (3/9)', () {
      expect(progress(0, 3, 9), closeTo(3 / 9, 0.001));
    });

    test('moved to second exercise, 0 done (3/9)', () {
      expect(progress(3, 0, 9), closeTo(3 / 9, 0.001));
    });

    test('second exercise first set done (4/9)', () {
      expect(progress(3, 1, 9), closeTo(4 / 9, 0.001));
    });

    test('all exercises done clamps to 1.0', () {
      expect(progress(9, 0, 9), 1.0);
    });

    test('overflow is clamped to 1.0', () {
      expect(progress(10, 5, 9), 1.0);
    });
  });

  // ─── Category ordering ────────────────────────────────────────────────────

  group('Exercise category grouping order', () {
    const categoryOrder = [
      'Грудь', 'Спина', 'Плечи', 'Руки', 'Ноги', 'Кардио',
    ];

    int orderOf(String cat) {
      final i = categoryOrder.indexOf(cat);
      return i == -1 ? 999 : i;
    }

    List<String> sortCategories(List<String> cats) {
      return [...cats]..sort((a, b) => orderOf(a).compareTo(orderOf(b)));
    }

    test('known categories are ordered correctly', () {
      final input = ['Кардио', 'Грудь', 'Ноги', 'Спина'];
      expect(sortCategories(input), ['Грудь', 'Спина', 'Ноги', 'Кардио']);
    });

    test('unknown category goes to end', () {
      final result = sortCategories(['Грудь', 'Неизвестно', 'Кардио']);
      expect(result.last, 'Неизвестно');
    });

    test('all standard categories in expected order', () {
      final shuffled = ['Кардио', 'Ноги', 'Руки', 'Плечи', 'Спина', 'Грудь'];
      expect(sortCategories(shuffled), categoryOrder);
    });
  });

  // ─── Exercise.categoryDisplayName ─────────────────────────────────────────

  group('Exercise.categoryDisplayName', () {
    test('chest → Грудь', () {
      expect(Exercise.categoryDisplayName('chest'), 'Грудь');
    });

    test('back → Спина', () {
      expect(Exercise.categoryDisplayName('back'), 'Спина');
    });

    test('shoulders → Плечи', () {
      expect(Exercise.categoryDisplayName('shoulders'), 'Плечи');
    });

    test('arms → Руки', () {
      expect(Exercise.categoryDisplayName('arms'), 'Руки');
    });

    test('legs → Ноги', () {
      expect(Exercise.categoryDisplayName('legs'), 'Ноги');
    });

    test('cardio → Кардио', () {
      expect(Exercise.categoryDisplayName('cardio'), 'Кардио');
    });

    test('unknown category returns raw value', () {
      expect(Exercise.categoryDisplayName('custom'), 'custom');
    });
  });

  // ─── Last set date formatting ─────────────────────────────────────────────

  group('Last set date formatting (dd.MM)', () {
    String formatDate(String isoDate) {
      if (isoDate.length < 10) return isoDate;
      return '${isoDate.substring(8, 10)}.${isoDate.substring(5, 7)}';
    }

    test('formats 2025-03-15 as 15.03', () {
      expect(formatDate('2025-03-15'), '15.03');
    });

    test('formats 2026-01-01 as 01.01', () {
      expect(formatDate('2026-01-01'), '01.01');
    });

    test('formats 2025-12-31 as 31.12', () {
      expect(formatDate('2025-12-31'), '31.12');
    });

    test('short string is returned as-is', () {
      expect(formatDate('bad'), 'bad');
    });
  });

  // ─── Session summary validation ──────────────────────────────────────────

  group('Session summary: invalid set detection', () {
    /// Mirrors _invalidSetDescriptions logic from SessionSummaryScreen.
    List<String> invalidSetDescriptions(
        List<({String name, List<int?> repsList})> groups) {
      final result = <String>[];
      for (final group in groups) {
        for (var i = 0; i < group.repsList.length; i++) {
          final reps = group.repsList[i];
          if ((reps ?? 0) == 0) {
            result.add('${group.name}, подход ${i + 1}');
          }
        }
      }
      return result;
    }

    test('no warnings when all sets have reps', () {
      final groups = [
        (name: 'Жим лёжа', repsList: [8, 10, 8]),
        (name: 'Тяга', repsList: [12, 12]),
      ];
      expect(invalidSetDescriptions(groups), isEmpty);
    });

    test('detects null reps', () {
      final groups = [(name: 'Приседания', repsList: [null, 10])];
      final warnings = invalidSetDescriptions(groups);
      expect(warnings, ['Приседания, подход 1']);
    });

    test('detects zero reps', () {
      final groups = [(name: 'Подтягивания', repsList: [0])];
      expect(invalidSetDescriptions(groups), ['Подтягивания, подход 1']);
    });

    test('detects multiple invalid sets across exercises', () {
      final groups = [
        (name: 'Жим', repsList: [null, 8]),
        (name: 'Тяга', repsList: [0, 0]),
      ];
      final warnings = invalidSetDescriptions(groups);
      expect(warnings.length, 3);
      expect(warnings[0], 'Жим, подход 1');
      expect(warnings[1], 'Тяга, подход 1');
      expect(warnings[2], 'Тяга, подход 2');
    });

    test('positive reps 1 passes validation', () {
      final groups = [(name: 'Отжимания', repsList: [1])];
      expect(invalidSetDescriptions(groups), isEmpty);
    });
  });

  // ─── getLastSetsForExercises (pure logic) ─────────────────────────────────

  group('getLastSetsForExercises logic', () {
    /// Simulates the session-iteration logic from getLastSetsForExercises:
    /// given a weToExercise map, sessionIds (desc by date), and setsBySession,
    /// produces the result map.
    Map<String, Map<String, dynamic>> resolveLastSets({
      required Map<String, String> weToExercise,
      required List<String> sessionIds,
      required Map<String, List<Map<String, dynamic>>> setsBySession,
      required Map<String, String> sessionDates,
    }) {
      final result = <String, Map<String, dynamic>>{};
      for (final sessionId in sessionIds) {
        if (result.length == weToExercise.values.toSet().length) break;
        for (final set in setsBySession[sessionId] ?? []) {
          final weId = set['workout_exercise_id'] as String;
          final exId = weToExercise[weId];
          if (exId == null || result.containsKey(exId)) continue;
          result[exId] = {
            'weight': (set['weight'] as num).toDouble(),
            'reps': (set['reps'] as int?) ?? 0,
            'date': sessionDates[sessionId] ?? '',
          };
        }
      }
      return result;
    }

    test('returns empty map when no sessions', () {
      final result = resolveLastSets(
        weToExercise: {'we1': 'ex1'},
        sessionIds: [],
        setsBySession: {},
        sessionDates: {},
      );
      expect(result, isEmpty);
    });

    test('finds most recent set for each exercise', () {
      final result = resolveLastSets(
        weToExercise: {'we1': 'ex1', 'we2': 'ex2'},
        sessionIds: ['s2', 's1'], // s2 is more recent
        setsBySession: {
          's1': [
            {'workout_exercise_id': 'we1', 'weight': 50.0, 'reps': 8},
            {'workout_exercise_id': 'we2', 'weight': 30.0, 'reps': 12},
          ],
          's2': [
            {'workout_exercise_id': 'we1', 'weight': 55.0, 'reps': 8},
          ],
        },
        sessionDates: {'s1': '2025-03-01', 's2': '2025-03-08'},
      );
      expect(result['ex1']!['weight'], 55.0); // from s2 (more recent)
      expect(result['ex2']!['weight'], 30.0); // only in s1
    });

    test('does not overwrite with older data', () {
      final result = resolveLastSets(
        weToExercise: {'we1': 'ex1'},
        sessionIds: ['s3', 's2', 's1'],
        setsBySession: {
          's1': [{'workout_exercise_id': 'we1', 'weight': 40.0, 'reps': 8}],
          's2': [{'workout_exercise_id': 'we1', 'weight': 50.0, 'reps': 8}],
          's3': [{'workout_exercise_id': 'we1', 'weight': 60.0, 'reps': 8}],
        },
        sessionDates: {
          's1': '2025-03-01', 's2': '2025-03-08', 's3': '2025-03-15',
        },
      );
      expect(result['ex1']!['weight'], 60.0); // s3 is first (most recent)
    });
  });
}
