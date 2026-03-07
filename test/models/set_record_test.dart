import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/models/set_record.dart';

void main() {
  group('SetRecord.fromJson', () {
    test('parses all fields correctly', () {
      final json = {
        'id': 'sr1',
        'training_session_id': 'ts1',
        'workout_exercise_id': 'we1',
        'set_number': 2,
        'weight': 80.5,
        'reps': 10,
        'rpe': 8,
        'completed': true,
      };
      final s = SetRecord.fromJson(json);

      expect(s.id, 'sr1');
      expect(s.trainingSessionId, 'ts1');
      expect(s.workoutExerciseId, 'we1');
      expect(s.setNumber, 2);
      expect(s.weight, 80.5);
      expect(s.reps, 10);
      expect(s.rpe, 8);
      expect(s.completed, isTrue);
    });

    test('completed defaults to false when absent', () {
      final json = {
        'id': 'sr2',
        'training_session_id': 'ts2',
        'workout_exercise_id': 'we2',
        'set_number': 1,
      };
      expect(SetRecord.fromJson(json).completed, isFalse);
    });

    test('completed defaults to false when null', () {
      final json = {
        'id': 'sr3',
        'training_session_id': 'ts3',
        'workout_exercise_id': 'we3',
        'set_number': 1,
        'completed': null,
      };
      expect(SetRecord.fromJson(json).completed, isFalse);
    });

    test('nullable fields are null when absent', () {
      final json = {
        'id': 'sr4',
        'training_session_id': 'ts4',
        'workout_exercise_id': 'we4',
        'set_number': 1,
      };
      final s = SetRecord.fromJson(json);

      expect(s.weight, isNull);
      expect(s.reps, isNull);
      expect(s.rpe, isNull);
    });

    test('weight parsed from int JSON value to double', () {
      final json = {
        'id': 'sr5',
        'training_session_id': 'ts5',
        'workout_exercise_id': 'we5',
        'set_number': 1,
        'weight': 100,
      };
      final s = SetRecord.fromJson(json);

      expect(s.weight, isA<double>());
      expect(s.weight, 100.0);
    });
  });

  group('SetRecord.toJson', () {
    test('serialises all fields', () {
      final s = SetRecord(
        id: 'sr6',
        trainingSessionId: 'ts6',
        workoutExerciseId: 'we6',
        setNumber: 3,
        weight: 60.0,
        reps: 12,
        rpe: 7,
        completed: true,
      );
      final json = s.toJson();

      expect(json['id'], 'sr6');
      expect(json['training_session_id'], 'ts6');
      expect(json['workout_exercise_id'], 'we6');
      expect(json['set_number'], 3);
      expect(json['weight'], 60.0);
      expect(json['reps'], 12);
      expect(json['rpe'], 7);
      expect(json['completed'], isTrue);
    });

    test('null fields are preserved as null in JSON', () {
      final s = SetRecord(
        id: 'sr7',
        trainingSessionId: 'ts7',
        workoutExerciseId: 'we7',
        setNumber: 1,
      );
      final json = s.toJson();

      expect(json['weight'], isNull);
      expect(json['reps'], isNull);
      expect(json['rpe'], isNull);
      expect(json['completed'], isFalse);
    });

    test('round-trip fromJson → toJson → fromJson preserves all fields', () {
      final original = SetRecord(
        id: 'sr8',
        trainingSessionId: 'ts8',
        workoutExerciseId: 'we8',
        setNumber: 2,
        weight: 75.5,
        reps: 8,
        rpe: 9,
        completed: true,
      );
      final restored = SetRecord.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.trainingSessionId, original.trainingSessionId);
      expect(restored.workoutExerciseId, original.workoutExerciseId);
      expect(restored.setNumber, original.setNumber);
      expect(restored.weight, original.weight);
      expect(restored.reps, original.reps);
      expect(restored.rpe, original.rpe);
      expect(restored.completed, original.completed);
    });
  });
}
