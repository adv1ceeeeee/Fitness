import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/models/workout.dart';

void main() {
  const createdAt = '2024-01-01T10:00:00.000Z';
  const updatedAt = '2024-01-02T10:00:00.000Z';

  group('Workout.fromJson', () {
    test('parses all fields correctly', () {
      final json = {
        'id': 'w1',
        'user_id': 'u1',
        'name': 'Грудь+трицепс',
        'days': [0, 2, 4],
        'is_standard': false,
        'cycle_weeks': 12,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
      final w = Workout.fromJson(json);

      expect(w.id, 'w1');
      expect(w.userId, 'u1');
      expect(w.name, 'Грудь+трицепс');
      expect(w.days, [0, 2, 4]);
      expect(w.isStandard, isFalse);
      expect(w.cycleWeeks, 12);
      expect(w.exercises, isNull);
    });

    test('days defaults to empty list when absent', () {
      final json = {
        'id': 'w2',
        'user_id': 'u2',
        'name': 'Test',
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
      final w = Workout.fromJson(json);

      expect(w.days, isEmpty);
    });

    test('isStandard defaults to false when absent', () {
      final json = {
        'id': 'w3',
        'user_id': 'u3',
        'name': 'Test',
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
      expect(Workout.fromJson(json).isStandard, isFalse);
    });

    test('cycleWeeks defaults to 8 when absent', () {
      final json = {
        'id': 'w4',
        'user_id': 'u4',
        'name': 'Test',
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
      expect(Workout.fromJson(json).cycleWeeks, 8);
    });

    test('days parsed from List<dynamic> containing nums', () {
      final json = {
        'id': 'w5',
        'user_id': 'u5',
        'name': 'Test',
        'days': <dynamic>[1, 3, 5],
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
      final w = Workout.fromJson(json);

      expect(w.days, [1, 3, 5]);
    });

    test('parses dates from ISO-8601 strings', () {
      final json = {
        'id': 'w6',
        'user_id': 'u6',
        'name': 'Test',
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
      final w = Workout.fromJson(json);

      expect(w.createdAt, DateTime.parse(createdAt));
      expect(w.updatedAt, DateTime.parse(updatedAt));
    });
  });

  group('Workout.daysPerWeek', () {
    test('returns number of selected days', () {
      final w = Workout(
        id: 'w7',
        userId: 'u7',
        name: 'Test',
        days: [0, 2, 4, 6],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(w.daysPerWeek, 4);
    });

    test('returns 0 when no days selected', () {
      final w = Workout(
        id: 'w8',
        userId: 'u8',
        name: 'Test',
        days: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(w.daysPerWeek, 0);
    });
  });

  group('Workout.toJson', () {
    test('round-trip preserves all data', () {
      final original = Workout(
        id: 'w9',
        userId: 'u9',
        name: 'Ноги',
        days: [1, 4],
        cycleWeeks: 10,
        isStandard: false,
        createdAt: DateTime.parse(createdAt),
        updatedAt: DateTime.parse(updatedAt),
      );
      final restored = Workout.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.name, original.name);
      expect(restored.days, original.days);
      expect(restored.cycleWeeks, original.cycleWeeks);
      expect(restored.isStandard, original.isStandard);
    });
  });
}
