import 'package:flutter_test/flutter_test.dart';

// Mirror of _ExerciseParams from calendar_screen.dart — tests the pure
// data logic without depending on the widget layer.

class ExerciseParams {
  final int sets;
  final String repsRange;
  final int restSeconds;

  const ExerciseParams({
    this.sets = 3,
    this.repsRange = '8-12',
    this.restSeconds = 90,
  });

  ExerciseParams copyWith({int? sets, String? repsRange, int? restSeconds}) =>
      ExerciseParams(
        sets: sets ?? this.sets,
        repsRange: repsRange ?? this.repsRange,
        restSeconds: restSeconds ?? this.restSeconds,
      );
}

void main() {
  group('ExerciseParams defaults', () {
    test('default sets is 3', () {
      expect(const ExerciseParams().sets, 3);
    });

    test('default repsRange is 8-12', () {
      expect(const ExerciseParams().repsRange, '8-12');
    });

    test('default restSeconds is 90', () {
      expect(const ExerciseParams().restSeconds, 90);
    });
  });

  group('ExerciseParams.copyWith', () {
    const base = ExerciseParams(sets: 3, repsRange: '8-12', restSeconds: 90);

    test('copyWith sets updates only sets', () {
      final updated = base.copyWith(sets: 5);
      expect(updated.sets, 5);
      expect(updated.repsRange, '8-12');
      expect(updated.restSeconds, 90);
    });

    test('copyWith repsRange updates only repsRange', () {
      final updated = base.copyWith(repsRange: '6-8');
      expect(updated.sets, 3);
      expect(updated.repsRange, '6-8');
      expect(updated.restSeconds, 90);
    });

    test('copyWith restSeconds updates only restSeconds', () {
      final updated = base.copyWith(restSeconds: 120);
      expect(updated.sets, 3);
      expect(updated.repsRange, '8-12');
      expect(updated.restSeconds, 120);
    });

    test('copyWith with no args returns equivalent object', () {
      final updated = base.copyWith();
      expect(updated.sets, base.sets);
      expect(updated.repsRange, base.repsRange);
      expect(updated.restSeconds, base.restSeconds);
    });

    test('copyWith all fields at once', () {
      final updated =
          base.copyWith(sets: 4, repsRange: '10', restSeconds: 60);
      expect(updated.sets, 4);
      expect(updated.repsRange, '10');
      expect(updated.restSeconds, 60);
    });

    test('immutability: original is unchanged after copyWith', () {
      base.copyWith(sets: 99);
      expect(base.sets, 3);
    });
  });

  group('ExerciseParams rest presets', () {
    const presets = [60, 90, 120, 180];

    test('all standard rest presets are valid positive integers', () {
      for (final sec in presets) {
        expect(sec, greaterThan(0));
      }
    });

    test('default restSeconds (90) is among the standard presets', () {
      expect(presets.contains(const ExerciseParams().restSeconds), isTrue);
    });
  });
}
