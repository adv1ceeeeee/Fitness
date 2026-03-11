import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/screens/home/home_screen.dart';
import 'package:sportwai/services/analytics_service.dart';

void main() {
  // ─── fmtMetricValue ────────────────────────────────────────────────────────

  group('fmtMetricValue', () {
    test('integer value shows no decimal', () {
      expect(fmtMetricValue(75), '75');
      expect(fmtMetricValue(100), '100');
    });

    test('fractional value shows one decimal place', () {
      expect(fmtMetricValue(75.5), '75.5');
      expect(fmtMetricValue(12.3), '12.3');
    });

    test('zero is formatted as integer', () {
      expect(fmtMetricValue(0), '0');
    });
  });

  // ─── bodyProgressGoalReached ───────────────────────────────────────────────

  group('bodyProgressGoalReached', () {
    test('returns false when target is null', () {
      expect(bodyProgressGoalReached(70, null), false);
    });

    test('returns true when difference < 0.05', () {
      expect(bodyProgressGoalReached(70.0, 70.0), true);
      expect(bodyProgressGoalReached(70.04, 70.0), true);
    });

    test('returns false when difference is clearly >= 0.05', () {
      expect(bodyProgressGoalReached(70.1, 70.0), false);
      expect(bodyProgressGoalReached(80.0, 70.0), false);
    });

    test('works when current is below target', () {
      expect(bodyProgressGoalReached(69.97, 70.0), true);
      expect(bodyProgressGoalReached(69.0, 70.0), false);
    });
  });

  // ─── bodyProgressRemainingText ─────────────────────────────────────────────

  group('bodyProgressRemainingText', () {
    test('no target shows setup hint', () {
      expect(bodyProgressRemainingText(70, null, 'кг'),
          'Нажмите на «Цель» для установки');
    });

    test('goal reached shows celebration text', () {
      expect(bodyProgressRemainingText(70.0, 70.0, 'кг'), 'Цель достигнута!');
    });

    test('current > target shows minus sign (need to decrease)', () {
      final text = bodyProgressRemainingText(80.0, 70.0, 'кг');
      expect(text, contains('−'));
      expect(text, contains('10'));
    });

    test('current < target shows plus sign (need to increase)', () {
      final text = bodyProgressRemainingText(65.0, 70.0, 'кг');
      expect(text, contains('+'));
      expect(text, contains('5'));
    });

    test('includes unit in output', () {
      final text = bodyProgressRemainingText(80.0, 75.0, 'кг');
      expect(text, contains('кг'));
    });

    test('fractional diff formatted correctly', () {
      final text = bodyProgressRemainingText(75.5, 70.0, 'кг');
      expect(text, contains('5.5'));
    });
  });

  // ─── achievementDiffText ───────────────────────────────────────────────────

  group('achievementDiffText', () {
    WorkoutInsight makeInsight({
      required double prev,
      required double next,
      required bool isWeight,
    }) =>
        (
          exerciseName: 'Жим лёжа',
          prevValue: prev,
          newValue: next,
          isWeight: isWeight,
          sessionDate: '01.01',
        );

    test('weight improvement shows кг', () {
      final text = achievementDiffText(makeInsight(prev: 80, next: 85, isWeight: true));
      expect(text, '+5 кг');
    });

    test('reps improvement shows повт.', () {
      final text = achievementDiffText(makeInsight(prev: 10, next: 12, isWeight: false));
      expect(text, '+2 повт.');
    });

    test('fractional weight improvement formatted', () {
      final text = achievementDiffText(makeInsight(prev: 80, next: 82.5, isWeight: true));
      expect(text, '+2.5 кг');
    });
  });

  // ─── elapsedGoalText ───────────────────────────────────────────────────────

  group('elapsedGoalText', () {
    DateTime daysAgo(int n) => DateTime.now().subtract(Duration(days: n));

    test('1 day ago → "за 1 дн."', () {
      expect(elapsedGoalText(daysAgo(1)), 'за 1 дн.');
    });

    test('5 days ago → "за 5 дн."', () {
      expect(elapsedGoalText(daysAgo(5)), 'за 5 дн.');
    });

    test('7 days ago → "за 1 нед."', () {
      expect(elapsedGoalText(daysAgo(7)), 'за 1 нед.');
    });

    test('14 days ago → "за 2 нед."', () {
      expect(elapsedGoalText(daysAgo(14)), 'за 2 нед.');
    });

    test('30 days ago → "за 1 мес."', () {
      expect(elapsedGoalText(daysAgo(30)), 'за 1 мес.');
    });

    test('60 days ago → "за 2 мес."', () {
      expect(elapsedGoalText(daysAgo(60)), 'за 2 мес.');
    });
  });
}
