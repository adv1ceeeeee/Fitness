import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/recsys_service.dart';

void main() {
  group('evaluateWellness', () {
    test('returns null when wellness is null', () {
      expect(evaluateWellness(null), isNull);
    });

    test('returns null when all indicators are healthy', () {
      final rec = evaluateWellness({
        'sleep_hours': 8.0,
        'stress': 3,
        'energy': 7,
        'soreness': 2,
      });
      expect(rec, isNull);
    });

    test('critical: bad sleep + high stress', () {
      final rec = evaluateWellness({
        'sleep_hours': 4.5,
        'stress': 9,
        'energy': 5,
        'soreness': 1,
      });
      expect(rec, isNotNull);
      expect(rec!.severity, RecSeverity.critical);
    });

    test('warning: bad sleep alone', () {
      final rec = evaluateWellness({
        'sleep_hours': 5.0,
        'stress': 4,
        'energy': 6,
        'soreness': 1,
      });
      expect(rec, isNotNull);
      expect(rec!.severity, RecSeverity.warning);
      expect(rec.message, contains('5ч'));
    });

    test('warning: high stress alone', () {
      final rec = evaluateWellness({
        'sleep_hours': 7.5,
        'stress': 8,
        'energy': 6,
        'soreness': 1,
      });
      expect(rec, isNotNull);
      expect(rec!.severity, RecSeverity.warning);
      expect(rec.message, contains('8/10'));
    });

    test('warning: low energy', () {
      final rec = evaluateWellness({
        'sleep_hours': 7.0,
        'stress': 4,
        'energy': 3,
        'soreness': 1,
      });
      expect(rec, isNotNull);
      expect(rec!.severity, RecSeverity.warning);
      expect(rec.message, contains('3/10'));
    });

    test('info: high soreness', () {
      final rec = evaluateWellness({
        'sleep_hours': 7.5,
        'stress': 3,
        'energy': 7,
        'soreness': 4,
      });
      expect(rec, isNotNull);
      expect(rec!.severity, RecSeverity.info);
      expect(rec.message, contains('4/5'));
    });

    test('critical takes priority over low energy', () {
      final rec = evaluateWellness({
        'sleep_hours': 4.0,
        'stress': 9,
        'energy': 2,
        'soreness': 5,
      });
      expect(rec!.severity, RecSeverity.critical);
    });

    test('handles null individual fields gracefully', () {
      expect(
        () => evaluateWellness({'sleep_hours': null, 'stress': null, 'energy': null, 'soreness': null}),
        returnsNormally,
      );
    });

    test('sleep boundary: exactly 6h is not bad sleep', () {
      final rec = evaluateWellness({
        'sleep_hours': 6.0,
        'stress': 4,
        'energy': 6,
        'soreness': 1,
      });
      expect(rec, isNull);
    });

    test('stress boundary: exactly 8 triggers warning', () {
      final rec = evaluateWellness({
        'sleep_hours': 7.0,
        'stress': 8,
        'energy': 6,
        'soreness': 1,
      });
      expect(rec!.severity, RecSeverity.warning);
    });

    test('energy boundary: exactly 3 triggers warning', () {
      final rec = evaluateWellness({
        'sleep_hours': 7.0,
        'stress': 4,
        'energy': 3,
        'soreness': 1,
      });
      expect(rec!.severity, RecSeverity.warning);
    });

    test('soreness boundary: exactly 4 triggers info', () {
      final rec = evaluateWellness({
        'sleep_hours': 7.0,
        'stress': 4,
        'energy': 7,
        'soreness': 4,
      });
      expect(rec!.severity, RecSeverity.info);
    });
  });
}
