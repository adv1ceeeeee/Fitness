import 'package:flutter_test/flutter_test.dart';

// Pure validation logic mirroring OnboardingScreen._finish() bounds checks.
// Age: 1–120 inclusive; empty string = valid (optional field).
// Weight: 1–500 inclusive; empty string = valid (optional field).
// Comma is accepted as decimal separator for weight.

bool isAgeValid(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return true;
  final age = int.tryParse(text);
  return age != null && age >= 1 && age <= 120;
}

bool isWeightValid(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return true;
  final weight = double.tryParse(text);
  return weight != null && weight >= 1 && weight <= 500;
}

void main() {
  group('Onboarding age validation', () {
    test('empty string is valid (optional field)', () {
      expect(isAgeValid(''), isTrue);
      expect(isAgeValid('  '), isTrue);
    });

    test('boundary minimum: 1 is valid', () {
      expect(isAgeValid('1'), isTrue);
    });

    test('boundary maximum: 120 is valid', () {
      expect(isAgeValid('120'), isTrue);
    });

    test('typical value is valid', () {
      expect(isAgeValid('25'), isTrue);
      expect(isAgeValid('60'), isTrue);
    });

    test('zero is invalid', () {
      expect(isAgeValid('0'), isFalse);
    });

    test('negative is invalid', () {
      expect(isAgeValid('-1'), isFalse);
    });

    test('above max (121) is invalid', () {
      expect(isAgeValid('121'), isFalse);
    });

    test('large number is invalid', () {
      expect(isAgeValid('999'), isFalse);
    });

    test('non-numeric string is invalid', () {
      expect(isAgeValid('abc'), isFalse);
      expect(isAgeValid('2o'), isFalse);
    });

    test('decimal is invalid for age (not parseable as int)', () {
      expect(isAgeValid('25.5'), isFalse);
    });
  });

  group('Onboarding weight validation', () {
    test('empty string is valid (optional field)', () {
      expect(isWeightValid(''), isTrue);
      expect(isWeightValid('  '), isTrue);
    });

    test('boundary minimum: 1 is valid', () {
      expect(isWeightValid('1'), isTrue);
    });

    test('boundary maximum: 500 is valid', () {
      expect(isWeightValid('500'), isTrue);
    });

    test('typical value is valid', () {
      expect(isWeightValid('75'), isTrue);
      expect(isWeightValid('90.5'), isTrue);
    });

    test('zero is invalid', () {
      expect(isWeightValid('0'), isFalse);
    });

    test('negative is invalid', () {
      expect(isWeightValid('-1'), isFalse);
    });

    test('above max (501) is invalid', () {
      expect(isWeightValid('501'), isFalse);
    });

    test('non-numeric string is invalid', () {
      expect(isWeightValid('abc'), isFalse);
      expect(isWeightValid('75kg'), isFalse);
    });

    test('comma decimal separator is accepted', () {
      expect(isWeightValid('75,5'), isTrue);
      expect(isWeightValid('100,0'), isTrue);
    });

    test('fractional boundary: 0.5 is invalid (< 1)', () {
      expect(isWeightValid('0.5'), isFalse);
    });

    test('fractional boundary: 500.5 is invalid (> 500)', () {
      expect(isWeightValid('500.5'), isFalse);
    });
  });
}
