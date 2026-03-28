import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/recsys_service.dart';

void main() {
  group('evaluateMuscleBalance', () {
    test('returns null for empty balance', () {
      expect(evaluateMuscleBalance({}), isNull);
    });

    test('returns null when both groups are balanced (ratio >= 0.6)', () {
      final rec = evaluateMuscleBalance({'chest': 20, 'back': 15});
      // ratio = 15/20 = 0.75 >= 0.6 → no flag
      expect(rec, isNull);
    });

    test('flags chest >> back imbalance', () {
      final rec = evaluateMuscleBalance({'chest': 30, 'back': 10});
      // ratio = 10/30 = 0.33 < 0.6 → flagged
      expect(rec, isNotNull);
      expect(rec!.weakLabel, 'Спина');
      expect(rec.strongLabel, 'Грудь');
    });

    test('flags back >> chest imbalance', () {
      final rec = evaluateMuscleBalance({'chest': 8, 'back': 30});
      expect(rec, isNotNull);
      expect(rec!.weakLabel, 'Грудь');
      expect(rec.strongLabel, 'Спина');
    });

    test('ignores groups with fewer than 6 sets on stronger side', () {
      // 5 chest sets — not enough data
      final rec = evaluateMuscleBalance({'chest': 5, 'back': 1});
      expect(rec, isNull);
    });

    test('boundary: exactly 6 sets on stronger side is enough data', () {
      final rec = evaluateMuscleBalance({'chest': 6, 'back': 1});
      // ratio = 1/6 = 0.17 < 0.6 → flagged
      expect(rec, isNotNull);
    });

    test('boundary: ratio exactly 0.6 is not flagged', () {
      final rec = evaluateMuscleBalance({'chest': 10, 'back': 6});
      // ratio = 6/10 = 0.6 → not flagged
      expect(rec, isNull);
    });

    test('message contains percentage', () {
      final rec = evaluateMuscleBalance({'chest': 20, 'back': 6});
      // ratio = 6/20 = 0.3 → 70% difference
      expect(rec!.message, contains('70%'));
    });

    test('missing antagonist treated as zero sets', () {
      // back is missing — treated as 0
      final rec = evaluateMuscleBalance({'chest': 20});
      expect(rec, isNotNull);
      expect(rec!.weakLabel, 'Спина');
    });
  });
}
