import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/models/profile.dart';

const _createdAt = '2024-01-01T10:00:00.000Z';
const _updatedAt = '2024-01-02T10:00:00.000Z';

Map<String, dynamic> _baseJson() => {
      'id': 'u1',
      'created_at': _createdAt,
      'updated_at': _updatedAt,
    };

void main() {
  group('Profile.fromJson', () {
    test('parses required fields', () {
      final p = Profile.fromJson(_baseJson());

      expect(p.id, 'u1');
      expect(p.createdAt, DateTime.parse(_createdAt));
      expect(p.updatedAt, DateTime.parse(_updatedAt));
    });

    test('nullable fields are null when absent', () {
      final p = Profile.fromJson(_baseJson());

      expect(p.fullName, isNull);
      expect(p.firstName, isNull);
      expect(p.lastName, isNull);
      expect(p.middleName, isNull);
      expect(p.birthDate, isNull);
      expect(p.nickname, isNull);
      expect(p.age, isNull);
      expect(p.gender, isNull);
      expect(p.weight, isNull);
      expect(p.goal, isNull);
      expect(p.level, isNull);
      expect(p.avatarUrl, isNull);
      expect(p.city, isNull);
      expect(p.phone, isNull);
      expect(p.email, isNull);
    });

    test('parses all optional fields when present', () {
      final json = {
        ..._baseJson(),
        'full_name': 'Иван Иванов',
        'first_name': 'Иван',
        'last_name': 'Иванов',
        'middle_name': 'Петрович',
        'birth_date': '1990-05-15',
        'nickname': 'ivan98',
        'age': 33,
        'gender': 'male',
        'weight': 82.5,
        'goal': 'muscle_gain',
        'level': 'intermediate',
        'avatar_url': 'https://example.com/avatar.png',
        'city': 'Москва',
        'phone': '+79001234567',
        'email': 'ivan@example.com',
      };
      final p = Profile.fromJson(json);

      expect(p.fullName, 'Иван Иванов');
      expect(p.firstName, 'Иван');
      expect(p.lastName, 'Иванов');
      expect(p.middleName, 'Петрович');
      expect(p.birthDate, DateTime.parse('1990-05-15'));
      expect(p.nickname, 'ivan98');
      expect(p.age, 33);
      expect(p.gender, 'male');
      expect(p.weight, 82.5);
      expect(p.goal, 'muscle_gain');
      expect(p.level, 'intermediate');
      expect(p.avatarUrl, 'https://example.com/avatar.png');
      expect(p.city, 'Москва');
      expect(p.phone, '+79001234567');
      expect(p.email, 'ivan@example.com');
    });

    test('weight parsed from int to double', () {
      final json = {..._baseJson(), 'weight': 80};
      final p = Profile.fromJson(json);

      expect(p.weight, isA<double>());
      expect(p.weight, 80.0);
    });

    test('birthDate is null when field is null', () {
      final json = {..._baseJson(), 'birth_date': null};
      expect(Profile.fromJson(json).birthDate, isNull);
    });

    test('birthDate returns null for invalid date string', () {
      final json = {..._baseJson(), 'birth_date': 'not-a-date'};
      expect(Profile.fromJson(json).birthDate, isNull);
    });
  });

  group('Profile.toJson', () {
    test('serialises all non-null fields correctly', () {
      final p = Profile(
        id: 'u2',
        fullName: 'Тест Тестов',
        firstName: 'Тест',
        lastName: 'Тестов',
        nickname: 'tester',
        age: 25,
        gender: 'female',
        weight: 55.0,
        goal: 'weight_loss',
        level: 'beginner',
        createdAt: DateTime.parse(_createdAt),
        updatedAt: DateTime.parse(_updatedAt),
      );
      final json = p.toJson();

      expect(json['id'], 'u2');
      expect(json['full_name'], 'Тест Тестов');
      expect(json['first_name'], 'Тест');
      expect(json['last_name'], 'Тестов');
      expect(json['nickname'], 'tester');
      expect(json['age'], 25);
      expect(json['gender'], 'female');
      expect(json['weight'], 55.0);
      expect(json['goal'], 'weight_loss');
      expect(json['level'], 'beginner');
    });

    test('birthDate serialised as yyyy-MM-dd without time', () {
      final p = Profile(
        id: 'u3',
        birthDate: DateTime(1995, 8, 20),
        createdAt: DateTime.parse(_createdAt),
        updatedAt: DateTime.parse(_updatedAt),
      );
      expect(p.toJson()['birth_date'], '1995-08-20');
    });

    test('null birthDate serialised as null', () {
      final p = Profile(
        id: 'u4',
        createdAt: DateTime.parse(_createdAt),
        updatedAt: DateTime.parse(_updatedAt),
      );
      expect(p.toJson()['birth_date'], isNull);
    });

    test('round-trip preserves core fields', () {
      final original = Profile(
        id: 'u5',
        nickname: 'roundtrip',
        age: 30,
        gender: 'male',
        weight: 70.0,
        level: 'advanced',
        createdAt: DateTime.parse(_createdAt),
        updatedAt: DateTime.parse(_updatedAt),
      );
      final restored = Profile.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.nickname, original.nickname);
      expect(restored.age, original.age);
      expect(restored.gender, original.gender);
      expect(restored.weight, original.weight);
      expect(restored.level, original.level);
    });
  });

  group('Profile.copyWith', () {
    late Profile base;

    setUp(() {
      base = Profile(
        id: 'u6',
        nickname: 'base',
        age: 20,
        gender: 'male',
        weight: 65.0,
        level: 'beginner',
        goal: 'endurance',
        createdAt: DateTime.parse(_createdAt),
        updatedAt: DateTime.parse(_updatedAt),
      );
    });

    test('returns profile with changed fields', () {
      final updated = base.copyWith(age: 21, weight: 66.5, level: 'intermediate');

      expect(updated.id, base.id);
      expect(updated.age, 21);
      expect(updated.weight, 66.5);
      expect(updated.level, 'intermediate');
    });

    test('unchanged fields are preserved', () {
      final updated = base.copyWith(age: 21);

      expect(updated.nickname, base.nickname);
      expect(updated.gender, base.gender);
      expect(updated.goal, base.goal);
    });

    test('updatedAt is refreshed on copyWith', () {
      final before = DateTime.now();
      final updated = base.copyWith(age: 22);
      final after = DateTime.now();

      expect(updated.updatedAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(updated.updatedAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('createdAt is unchanged after copyWith', () {
      final updated = base.copyWith(age: 23);
      expect(updated.createdAt, base.createdAt);
    });

    test('id is always unchanged after copyWith', () {
      final updated = base.copyWith(nickname: 'other');
      expect(updated.id, 'u6');
    });
  });
}
