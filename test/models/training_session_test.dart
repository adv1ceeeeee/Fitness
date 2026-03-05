import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/models/training_session.dart';

void main() {
  group('TrainingSession.fromJson', () {
    test('parses all fields correctly', () {
      final json = {
        'id': 'ts1',
        'user_id': 'u1',
        'workout_id': 'w1',
        'date': '2024-06-15',
        'completed': true,
        'notes': 'Хорошая тренировка',
        'created_at': '2024-06-15T09:00:00.000Z',
      };
      final s = TrainingSession.fromJson(json);

      expect(s.id, 'ts1');
      expect(s.userId, 'u1');
      expect(s.workoutId, 'w1');
      expect(s.date, DateTime.parse('2024-06-15'));
      expect(s.completed, isTrue);
      expect(s.notes, 'Хорошая тренировка');
      expect(s.createdAt, isNotNull);
    });

    test('completed defaults to false when absent', () {
      final json = {
        'id': 'ts2',
        'user_id': 'u2',
        'workout_id': 'w2',
        'date': '2024-06-16',
      };
      expect(TrainingSession.fromJson(json).completed, isFalse);
    });

    test('nullable fields are null when absent', () {
      final json = {
        'id': 'ts3',
        'user_id': 'u3',
        'workout_id': 'w3',
        'date': '2024-06-17',
      };
      final s = TrainingSession.fromJson(json);

      expect(s.notes, isNull);
      expect(s.createdAt, isNull);
    });

    test('createdAt is null when field is null in JSON', () {
      final json = {
        'id': 'ts4',
        'user_id': 'u4',
        'workout_id': 'w4',
        'date': '2024-06-18',
        'created_at': null,
      };
      expect(TrainingSession.fromJson(json).createdAt, isNull);
    });
  });

  group('TrainingSession.toJson', () {
    test('formats date as yyyy-MM-dd without time component', () {
      final s = TrainingSession(
        id: 'ts5',
        userId: 'u5',
        workoutId: 'w5',
        date: DateTime(2024, 6, 20),
        completed: false,
      );
      final json = s.toJson();

      expect(json['date'], '2024-06-20');
    });

    test('does not include created_at in output', () {
      final s = TrainingSession(
        id: 'ts6',
        userId: 'u6',
        workoutId: 'w6',
        date: DateTime(2024, 1, 1),
        createdAt: DateTime(2024, 1, 1),
      );
      expect(s.toJson().containsKey('created_at'), isFalse);
    });

    test('round-trip preserves core fields', () {
      final original = TrainingSession(
        id: 'ts7',
        userId: 'u7',
        workoutId: 'w7',
        date: DateTime(2024, 3, 15),
        completed: true,
        notes: 'Заметка',
      );
      final restored = TrainingSession.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.workoutId, original.workoutId);
      expect(restored.date.year, original.date.year);
      expect(restored.date.month, original.date.month);
      expect(restored.date.day, original.date.day);
      expect(restored.completed, original.completed);
      expect(restored.notes, original.notes);
    });
  });
}
