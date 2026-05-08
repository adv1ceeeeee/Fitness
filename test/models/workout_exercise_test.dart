import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/models/workout_exercise.dart';

void main() {
  group('WorkoutExercise.fromJson', () {
    test('parses all fields correctly', () {
      final json = {
        'id': 'we1',
        'workout_id': 'w1',
        'exercise_id': 'ex1',
        'order': 2,
        'sets': 4,
        'reps_range': '6-10',
        'rest_seconds': 120,
        'target_weight': 80.5,
        'weekly_target_weights': {'1': 80, '3': 87.5},
        'drop_set_weekly_target_weights': {'1': 45, '3': 52.5},
        'target_rpe': 8,
      };
      final we = WorkoutExercise.fromJson(json);

      expect(we.id, 'we1');
      expect(we.workoutId, 'w1');
      expect(we.exerciseId, 'ex1');
      expect(we.order, 2);
      expect(we.sets, 4);
      expect(we.repsRange, '6-10');
      expect(we.restSeconds, 120);
      expect(we.targetWeight, 80.5);
      expect(we.weeklyTargetWeights, {1: 80.0, 3: 87.5});
      expect(we.dropSetWeeklyTargetWeights, {1: 45.0, 3: 52.5});
      expect(we.targetRpe, 8);
      expect(we.exercise, isNull);
    });

    test('repsRange defaults to 8-12 when absent', () {
      final json = {
        'id': 'we2',
        'workout_id': 'w2',
        'exercise_id': 'ex2',
        'order': 1,
        'sets': 3,
      };
      expect(WorkoutExercise.fromJson(json).repsRange, '8-12');
    });

    test('restSeconds defaults to 90 when absent', () {
      final json = {
        'id': 'we3',
        'workout_id': 'w3',
        'exercise_id': 'ex3',
        'order': 1,
        'sets': 3,
      };
      expect(WorkoutExercise.fromJson(json).restSeconds, 90);
    });

    test('optional fields are null when absent', () {
      final json = {
        'id': 'we4',
        'workout_id': 'w4',
        'exercise_id': 'ex4',
        'order': 1,
        'sets': 3,
      };
      final we = WorkoutExercise.fromJson(json);

      expect(we.targetWeight, isNull);
      expect(we.targetRpe, isNull);
    });

    test('target_weight parsed from int JSON value to double', () {
      final json = {
        'id': 'we5',
        'workout_id': 'w5',
        'exercise_id': 'ex5',
        'order': 1,
        'sets': 3,
        'target_weight': 100,
      };
      final we = WorkoutExercise.fromJson(json);

      expect(we.targetWeight, isA<double>());
      expect(we.targetWeight, 100.0);
    });

    test('parses nested exercise when exercises key present', () {
      final json = {
        'id': 'we6',
        'workout_id': 'w6',
        'exercise_id': 'ex6',
        'order': 1,
        'sets': 3,
        'exercises': {
          'id': 'ex6',
          'name': 'Становая тяга',
          'category': 'back',
          'is_standard': true,
        },
      };
      final we = WorkoutExercise.fromJson(json);

      expect(we.exercise, isNotNull);
      expect(we.exercise!.id, 'ex6');
      expect(we.exercise!.name, 'Становая тяга');
      expect(we.exercise!.category, 'back');
    });

    test('exercise is null when exercises key is null', () {
      final json = {
        'id': 'we7',
        'workout_id': 'w7',
        'exercise_id': 'ex7',
        'order': 1,
        'sets': 3,
        'exercises': null,
      };
      expect(WorkoutExercise.fromJson(json).exercise, isNull);
    });
  });

  group('WorkoutExercise.toJson', () {
    test('serialises all fields without nested exercise', () {
      final we = WorkoutExercise(
        id: 'we8',
        workoutId: 'w8',
        exerciseId: 'ex8',
        order: 3,
        sets: 5,
        repsRange: '5',
        restSeconds: 180,
        targetWeight: 120.0,
        weeklyTargetWeights: {1: 120.0, 2: 122.5},
        dropSetWeeklyTargetWeights: {1: 70.0, 2: 72.5},
        targetRpe: 9,
      );
      final json = we.toJson();

      expect(json['id'], 'we8');
      expect(json['workout_id'], 'w8');
      expect(json['exercise_id'], 'ex8');
      expect(json['order'], 3);
      expect(json['sets'], 5);
      expect(json['reps_range'], '5');
      expect(json['rest_seconds'], 180);
      expect(json['target_weight'], 120.0);
      expect(json['weekly_target_weights'], {'1': 120.0, '2': 122.5});
      expect(json['drop_set_weekly_target_weights'], {'1': 70.0, '2': 72.5});
      expect(json['target_rpe'], 9);
      expect(json.containsKey('exercises'), isFalse);
    });

    test('round-trip preserves data', () {
      final original = WorkoutExercise(
        id: 'we9',
        workoutId: 'w9',
        exerciseId: 'ex9',
        order: 1,
        sets: 3,
        repsRange: '10-12',
        restSeconds: 60,
      );
      final restored = WorkoutExercise.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.sets, original.sets);
      expect(restored.repsRange, original.repsRange);
      expect(restored.restSeconds, original.restSeconds);
    });
  });

  group('WorkoutExercise.weightForWeek', () {
    test('returns weight recorded for the requested week', () {
      final we = WorkoutExercise(
        id: 'we-week',
        workoutId: 'w-week',
        exerciseId: 'ex-week',
        order: 1,
        sets: 3,
        repsRange: '8-12',
        restSeconds: 90,
        targetWeight: 70.0,
        weeklyTargetWeights: {1: 75.0, 3: 82.5},
        dropSetWeeklyTargetWeights: {1: 40.0, 3: 45.0},
      );

      expect(we.weightForWeek(3), 82.5);
      expect(we.dropSetWeightForWeek(3), 45.0);
    });

    test('falls back to previous recorded week when current week is empty', () {
      final we = WorkoutExercise(
        id: 'we-fallback',
        workoutId: 'w-fallback',
        exerciseId: 'ex-fallback',
        order: 1,
        sets: 3,
        repsRange: '8-12',
        restSeconds: 90,
        targetWeight: 70.0,
        weeklyTargetWeights: {1: 75.0, 3: 82.5},
        dropSetWeeklyTargetWeights: {1: 40.0, 3: 45.0},
      );

      expect(we.weightForWeek(4), 82.5);
      expect(we.dropSetWeightForWeek(4), 45.0);
    });

    test('falls back to targetWeight when no weekly weights exist before it',
        () {
      final we = WorkoutExercise(
        id: 'we-target',
        workoutId: 'w-target',
        exerciseId: 'ex-target',
        order: 1,
        sets: 3,
        repsRange: '8-12',
        restSeconds: 90,
        targetWeight: 70.0,
        weeklyTargetWeights: {3: 82.5},
      );

      expect(we.weightForWeek(2), 70.0);
      expect(we.dropSetWeightForWeek(2), 42.0);
    });
  });

  group('WorkoutExercise.copyWithExercise', () {
    final baseExercise = Exercise(
      id: 'ex-old',
      name: 'Жим лёжа',
      category: 'chest',
      isStandard: true,
    );
    final newExercise = Exercise(
      id: 'ex-new',
      name: 'Разводка гантелей',
      category: 'chest',
      isStandard: true,
    );

    late WorkoutExercise base;

    setUp(() {
      base = WorkoutExercise(
        id: 'we-base',
        workoutId: 'w-base',
        exerciseId: baseExercise.id,
        order: 2,
        sets: 4,
        repsRange: '8-12',
        restSeconds: 90,
        targetWeight: 80.0,
        targetRpe: 8,
        durationMinutes: null,
        supersetGroup: 1,
        weeklyTargetWeights: {1: 80.0, 3: 87.5},
        dropSetWeeklyTargetWeights: {1: 45.0, 3: 52.5},
        exercise: baseExercise,
      );
    });

    test('updates exerciseId to new exercise id', () {
      final copy = base.copyWithExercise(newExercise);
      expect(copy.exerciseId, newExercise.id);
    });

    test('updates exercise field to new exercise object', () {
      final copy = base.copyWithExercise(newExercise);
      expect(copy.exercise, newExercise);
      expect(copy.exercise!.name, 'Разводка гантелей');
    });

    test('preserves all other fields unchanged', () {
      final copy = base.copyWithExercise(newExercise);
      expect(copy.id, base.id);
      expect(copy.workoutId, base.workoutId);
      expect(copy.order, base.order);
      expect(copy.sets, base.sets);
      expect(copy.repsRange, base.repsRange);
      expect(copy.restSeconds, base.restSeconds);
      expect(copy.targetWeight, base.targetWeight);
      expect(copy.targetRpe, base.targetRpe);
      expect(copy.durationMinutes, base.durationMinutes);
      expect(copy.supersetGroup, base.supersetGroup);
      expect(copy.weeklyTargetWeights, base.weeklyTargetWeights);
      expect(copy.dropSetWeeklyTargetWeights, base.dropSetWeeklyTargetWeights);
    });

    test('original is not mutated after copy', () {
      base.copyWithExercise(newExercise);
      expect(base.exerciseId, baseExercise.id);
      expect(base.exercise!.name, 'Жим лёжа');
    });

    test('works when optional fields are null', () {
      final minimal = WorkoutExercise(
        id: 'we-min',
        workoutId: 'w-min',
        exerciseId: 'ex-min',
        order: 0,
        sets: 3,
        repsRange: '8-12',
        restSeconds: 90,
      );
      final copy = minimal.copyWithExercise(newExercise);
      expect(copy.targetWeight, isNull);
      expect(copy.targetRpe, isNull);
      expect(copy.supersetGroup, isNull);
      expect(copy.exerciseId, newExercise.id);
    });
  });
}
