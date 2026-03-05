import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/models/exercise.dart';

void main() {
  group('Exercise.fromJson', () {
    test('parses all fields correctly', () {
      final json = {
        'id': 'ex1',
        'name': 'Жим лёжа',
        'category': 'chest',
        'description': 'Базовое упражнение на грудь',
        'image_url': 'https://example.com/img.png',
        'is_standard': true,
      };
      final ex = Exercise.fromJson(json);

      expect(ex.id, 'ex1');
      expect(ex.name, 'Жим лёжа');
      expect(ex.category, 'chest');
      expect(ex.description, 'Базовое упражнение на грудь');
      expect(ex.imageUrl, 'https://example.com/img.png');
      expect(ex.isStandard, isTrue);
    });

    test('nullable fields are null when absent', () {
      final json = {'id': 'ex2', 'name': 'Тяга', 'category': 'back'};
      final ex = Exercise.fromJson(json);

      expect(ex.description, isNull);
      expect(ex.imageUrl, isNull);
    });

    test('isStandard defaults to true when absent', () {
      final json = {'id': 'ex3', 'name': 'Жим', 'category': 'chest'};
      final ex = Exercise.fromJson(json);

      expect(ex.isStandard, isTrue);
    });

    test('isStandard can be false', () {
      final json = {
        'id': 'ex4',
        'name': 'Моё упражнение',
        'category': 'arms',
        'is_standard': false,
      };
      final ex = Exercise.fromJson(json);

      expect(ex.isStandard, isFalse);
    });
  });

  group('Exercise.toJson', () {
    test('serialises all fields', () {
      final ex = Exercise(
        id: 'ex5',
        name: 'Приседания',
        category: 'legs',
        description: 'Ноги',
        imageUrl: null,
        isStandard: false,
      );
      final json = ex.toJson();

      expect(json['id'], 'ex5');
      expect(json['name'], 'Приседания');
      expect(json['category'], 'legs');
      expect(json['description'], 'Ноги');
      expect(json['image_url'], isNull);
      expect(json['is_standard'], isFalse);
    });

    test('round-trip fromJson → toJson → fromJson preserves data', () {
      final original = Exercise(
        id: 'ex6',
        name: 'Становая тяга',
        category: 'back',
        isStandard: true,
      );
      final restored = Exercise.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.category, original.category);
      expect(restored.isStandard, original.isStandard);
    });
  });

  group('Exercise.categoryDisplayName', () {
    test('translates all known categories to Russian', () {
      expect(Exercise.categoryDisplayName('chest'), 'Грудь');
      expect(Exercise.categoryDisplayName('back'), 'Спина');
      expect(Exercise.categoryDisplayName('legs'), 'Ноги');
      expect(Exercise.categoryDisplayName('shoulders'), 'Плечи');
      expect(Exercise.categoryDisplayName('arms'), 'Руки');
      expect(Exercise.categoryDisplayName('cardio'), 'Кардио');
    });

    test('returns raw value for unknown category', () {
      expect(Exercise.categoryDisplayName('unknown'), 'unknown');
      expect(Exercise.categoryDisplayName(''), '');
    });
  });
}
