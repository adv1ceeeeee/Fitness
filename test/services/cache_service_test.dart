import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';

// Pure serialisation tests — no file I/O, no path_provider needed.

void main() {
  group('Workout serialisation round-trip (used by CacheService)', () {
    final now = DateTime(2025, 3, 8, 12, 0);

    final workout = Workout(
      id: 'w1',
      userId: 'u1',
      name: 'Грудь+Бицепс',
      days: [0, 2, 4],
      cycleWeeks: 8,
      warmupMinutes: 5,
      cooldownMinutes: 10,
      createdAt: now,
      updatedAt: now,
    );

    test('toJson → fromJson preserves all fields', () {
      final json = workout.toJson();
      final restored = Workout.fromJson(json);

      expect(restored.id, workout.id);
      expect(restored.userId, workout.userId);
      expect(restored.name, workout.name);
      expect(restored.days, workout.days);
      expect(restored.cycleWeeks, workout.cycleWeeks);
      expect(restored.warmupMinutes, workout.warmupMinutes);
      expect(restored.cooldownMinutes, workout.cooldownMinutes);
    });

    test('toJson → jsonEncode → jsonDecode → fromJson round-trip', () {
      final encoded = jsonEncode(workout.toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final restored = Workout.fromJson(decoded);

      expect(restored.id, workout.id);
      expect(restored.name, workout.name);
      expect(restored.days, [0, 2, 4]);
      expect(restored.warmupMinutes, 5);
      expect(restored.cooldownMinutes, 10);
    });

    test('list of workouts serialises correctly', () {
      final workouts = [workout, workout];
      final encoded = jsonEncode(workouts.map((w) => w.toJson()).toList());
      final decoded = (jsonDecode(encoded) as List)
          .map((e) => Workout.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(decoded.length, 2);
      expect(decoded[0].id, 'w1');
    });
  });

  group('WorkoutExercise serialisation round-trip (used by CacheService)', () {
    final we = WorkoutExercise(
      id: 'we1',
      workoutId: 'w1',
      exerciseId: 'ex1',
      order: 0,
      sets: 3,
      repsRange: '8-12',
      restSeconds: 90,
      targetWeight: 60.0,
      supersetGroup: 1,
    );

    test('toJson → fromJson preserves all fields', () {
      final json = we.toJson();
      final restored = WorkoutExercise.fromJson(json);

      expect(restored.id, we.id);
      expect(restored.sets, we.sets);
      expect(restored.repsRange, we.repsRange);
      expect(restored.restSeconds, we.restSeconds);
      expect(restored.targetWeight, we.targetWeight);
      expect(restored.supersetGroup, we.supersetGroup);
    });

    test('null targetWeight and supersetGroup survive round-trip', () {
      final minimal = WorkoutExercise(
        id: 'we2',
        workoutId: 'w1',
        exerciseId: 'ex2',
        order: 1,
        sets: 4,
        repsRange: '5',
        restSeconds: 120,
      );
      final restored = WorkoutExercise.fromJson(minimal.toJson());
      expect(restored.targetWeight, isNull);
      expect(restored.supersetGroup, isNull);
    });
  });
}
