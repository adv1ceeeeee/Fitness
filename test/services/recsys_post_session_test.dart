import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/recsys_service.dart';

void main() {
  group('evaluatePostSession', () {
    test('returns empty list when streak < 2, no volume data, sets < 12', () {
      final result = evaluatePostSession(
        streak: 1,
        sessionVolume: 1000,
        recentAvgVolume: null,
        workingSetsCount: 8,
      );
      expect(result, isEmpty);
    });

    test('streak 2 → returns streak insight', () {
      final result = evaluatePostSession(
        streak: 2,
        sessionVolume: 0,
        recentAvgVolume: null,
        workingSetsCount: 0,
      );
      expect(result.any((i) => i.kind == PostSessionInsightKind.streak), isTrue);
    });

    test('streak 5 → message contains 5', () {
      final result = evaluatePostSession(
        streak: 5,
        sessionVolume: 0,
        recentAvgVolume: null,
        workingSetsCount: 0,
      );
      final ins = result.firstWhere((i) => i.kind == PostSessionInsightKind.streak);
      expect(ins.message, contains('5'));
    });

    test('volume 15% above avg → volumeUp insight', () {
      final result = evaluatePostSession(
        streak: 0,
        sessionVolume: 1150,
        recentAvgVolume: 1000,
        workingSetsCount: 0,
      );
      expect(result.any((i) => i.kind == PostSessionInsightKind.volumeUp), isTrue);
    });

    test('volume 9% above avg → no volumeUp (below 10% threshold)', () {
      final result = evaluatePostSession(
        streak: 0,
        sessionVolume: 1090,
        recentAvgVolume: 1000,
        workingSetsCount: 0,
      );
      expect(result.any((i) => i.kind == PostSessionInsightKind.volumeUp), isFalse);
    });

    test('volume 20% below avg → volumeDown insight', () {
      final result = evaluatePostSession(
        streak: 0,
        sessionVolume: 800,
        recentAvgVolume: 1000,
        workingSetsCount: 0,
      );
      expect(result.any((i) => i.kind == PostSessionInsightKind.volumeDown), isTrue);
    });

    test('volume 14% below avg → no volumeDown (above -15% threshold)', () {
      final result = evaluatePostSession(
        streak: 0,
        sessionVolume: 860,
        recentAvgVolume: 1000,
        workingSetsCount: 0,
      );
      expect(result.any((i) => i.kind == PostSessionInsightKind.volumeDown), isFalse);
    });

    test('12 working sets → setsCount insight', () {
      final result = evaluatePostSession(
        streak: 0,
        sessionVolume: 0,
        recentAvgVolume: null,
        workingSetsCount: 12,
      );
      expect(result.any((i) => i.kind == PostSessionInsightKind.setsCount), isTrue);
    });

    test('11 working sets → no setsCount insight', () {
      final result = evaluatePostSession(
        streak: 0,
        sessionVolume: 0,
        recentAvgVolume: null,
        workingSetsCount: 11,
      );
      expect(result.any((i) => i.kind == PostSessionInsightKind.setsCount), isFalse);
    });

    test('multiple insights can appear together', () {
      final result = evaluatePostSession(
        streak: 10,
        sessionVolume: 1500,
        recentAvgVolume: 1000,
        workingSetsCount: 15,
      );
      expect(result.length, greaterThanOrEqualTo(2));
    });

    test('recentAvgVolume null → no volume insights', () {
      final result = evaluatePostSession(
        streak: 0,
        sessionVolume: 2000,
        recentAvgVolume: null,
        workingSetsCount: 0,
      );
      expect(result.any((i) =>
          i.kind == PostSessionInsightKind.volumeUp ||
          i.kind == PostSessionInsightKind.volumeDown), isFalse);
    });

    test('recentAvgVolume 0 → no volume insights (avoid division by zero)', () {
      final result = evaluatePostSession(
        streak: 0,
        sessionVolume: 1000,
        recentAvgVolume: 0,
        workingSetsCount: 0,
      );
      expect(result.any((i) =>
          i.kind == PostSessionInsightKind.volumeUp ||
          i.kind == PostSessionInsightKind.volumeDown), isFalse);
    });
  });
}
