import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/recsys_service.dart';

void main() {
  // ── EnergyState.bucket ────────────────────────────────────────────────────

  group('EnergyState.bucket', () {
    test('reserve 100 → bucket 1', () {
      expect(const EnergyState(reserve: 100).bucket, 1);
    });
    test('reserve 95 → bucket 1', () {
      expect(const EnergyState(reserve: 95).bucket, 1);
    });
    test('reserve 90 → bucket 1 (lower bound of top range)', () {
      expect(const EnergyState(reserve: 90).bucket, 1);
    });
    test('reserve 85 → bucket 2', () {
      expect(const EnergyState(reserve: 85).bucket, 2);
    });
    test('reserve 80 → bucket 2 (lower bound)', () {
      expect(const EnergyState(reserve: 80).bucket, 2);
    });
    test('reserve 50 → bucket 5', () {
      expect(const EnergyState(reserve: 50).bucket, 5);
    });
    test('reserve 30 → bucket 7', () {
      expect(const EnergyState(reserve: 30).bucket, 7);
    });
    test('reserve 10 → bucket 9', () {
      expect(const EnergyState(reserve: 10).bucket, 9);
    });
    test('reserve 5 → bucket 10', () {
      expect(const EnergyState(reserve: 5).bucket, 10);
    });
    test('reserve 0 → bucket 10', () {
      expect(const EnergyState(reserve: 0).bucket, 10);
    });
  });

  // ── EnergyState.label ─────────────────────────────────────────────────────

  group('EnergyState.label', () {
    test('bucket 1 → Пик', () {
      expect(const EnergyState(reserve: 95).label, 'Пик');
    });
    test('bucket 3 → Хорошо', () {
      expect(const EnergyState(reserve: 75).label, 'Хорошо');
    });
    test('bucket 5 → Умеренно', () {
      expect(const EnergyState(reserve: 55).label, 'Умеренно');
    });
    test('bucket 7 → Низко', () {
      expect(const EnergyState(reserve: 35).label, 'Низко');
    });
    test('bucket 9 → Истощён', () {
      expect(const EnergyState(reserve: 5).label, 'Истощён');
    });
  });

  // ── computeEnergyStart ────────────────────────────────────────────────────

  group('computeEnergyStart', () {
    test('no prior session → returns 100', () {
      final s = computeEnergyStart(
        lastEnergyEnd: 100.0,
        hoursSinceLast: 0,
      );
      expect(s.reserve, closeTo(100.0, 0.1));
    });

    test('fully recovered after very long rest', () {
      // After 200h even a heavy session should be nearly 100
      final s = computeEnergyStart(
        lastEnergyEnd: 40.0,
        hoursSinceLast: 200,
        lastSessionRpe: 9,
      );
      expect(s.reserve, greaterThan(98.0));
    });

    test('partial recovery: heavy session, 24h later', () {
      // τ = 48h (heavy), exp(-24/48) ≈ 0.606
      // reserve = 100 - (100 - 50) × 0.606 ≈ 69.7
      final s = computeEnergyStart(
        lastEnergyEnd: 50.0,
        hoursSinceLast: 24,
        lastSessionRpe: 9,
        trainingMonths: 12,
      );
      expect(s.reserve, inInclusiveRange(65.0, 75.0));
    });

    test('light session recovers faster than heavy', () {
      final light = computeEnergyStart(
        lastEnergyEnd: 50.0,
        hoursSinceLast: 24,
        lastSessionRpe: 5, // τ = 24h
      );
      final heavy = computeEnergyStart(
        lastEnergyEnd: 50.0,
        hoursSinceLast: 24,
        lastSessionRpe: 9, // τ = 48h
      );
      expect(light.reserve, greaterThan(heavy.reserve));
    });

    test('advanced athlete recovers faster than beginner', () {
      final advanced = computeEnergyStart(
        lastEnergyEnd: 50.0,
        hoursSinceLast: 24,
        lastSessionRpe: 8,
        trainingMonths: 36, // expMod 0.85 → faster
      );
      final beginner = computeEnergyStart(
        lastEnergyEnd: 50.0,
        hoursSinceLast: 24,
        lastSessionRpe: 8,
        trainingMonths: 3, // expMod 1.2 → slower
      );
      expect(advanced.reserve, greaterThan(beginner.reserve));
    });

    test('bad sleep slows recovery', () {
      final goodSleep = computeEnergyStart(
        lastEnergyEnd: 50.0,
        hoursSinceLast: 24,
        lastSessionRpe: 8,
      );
      final badSleep = computeEnergyStart(
        lastEnergyEnd: 50.0,
        hoursSinceLast: 24,
        lastSessionRpe: 8,
        wellnessSinceLast: {'sleep_hours': 5.0, 'stress': 5, 'energy': 5},
      );
      expect(badSleep.reserve, lessThan(goodSleep.reserve));
    });

    test('all bad wellness factors stack to slow recovery', () {
      final normal = computeEnergyStart(
        lastEnergyEnd: 50.0,
        hoursSinceLast: 36,
        lastSessionRpe: 8,
      );
      final worst = computeEnergyStart(
        lastEnergyEnd: 50.0,
        hoursSinceLast: 36,
        lastSessionRpe: 8,
        wellnessSinceLast: {'sleep_hours': 4.0, 'stress': 9, 'energy': 2},
      );
      expect(worst.reserve, lessThan(normal.reserve));
    });

    test('reserve is always in [0, 100]', () {
      // Extreme cases
      for (final end in [0.0, 50.0, 100.0]) {
        for (final hours in [0.0, 12.0, 48.0, 200.0]) {
          final s = computeEnergyStart(lastEnergyEnd: end, hoursSinceLast: hours);
          expect(s.reserve, inInclusiveRange(0.0, 100.0),
              reason: 'end=$end hours=$hours');
        }
      }
    });

    test('unknown RPE (null) defaults to light τ=24h', () {
      final withNull = computeEnergyStart(
        lastEnergyEnd: 50.0,
        hoursSinceLast: 12,
        lastSessionRpe: null,
      );
      final withLight = computeEnergyStart(
        lastEnergyEnd: 50.0,
        hoursSinceLast: 12,
        lastSessionRpe: 5,
      );
      expect(withNull.reserve, closeTo(withLight.reserve, 0.01));
    });
  });

  // ── evaluateProgression energy overrides ──────────────────────────────────

  group('evaluateProgression energy overrides', () {
    final baseData = {
      'weight': 100.0,
      'reps': 10,
      'rpe': 6,
      'reps_target': 10,
    };

    test('bucket 9-10 forces decrease regardless of good RPE', () {
      final rec = evaluateProgression(
        baseData,
        energyState: const EnergyState(reserve: 5), // bucket 10
      );
      expect(rec!.direction, ProgressionDirection.decrease);
      expect(rec.suggestedWeightKg, lessThan(100.0));
    });

    test('bucket 7-8 downgrades increase to maintain', () {
      final rec = evaluateProgression(
        baseData,
        energyState: const EnergyState(reserve: 35), // bucket 7
      );
      expect(rec!.direction, ProgressionDirection.maintain);
      expect(rec.message, contains('резерв энергии'));
    });

    test('bucket 5-6 keeps increase but adds caution note', () {
      final rec = evaluateProgression(
        baseData,
        energyState: const EnergyState(reserve: 55), // bucket 5
      );
      expect(rec!.direction, ProgressionDirection.increase);
      expect(rec.message, contains('Энергия умеренная'));
    });

    test('bucket 1-4 returns increase unchanged', () {
      final rec = evaluateProgression(
        baseData,
        energyState: const EnergyState(reserve: 85), // bucket 2
      );
      expect(rec!.direction, ProgressionDirection.increase);
      expect(rec.message, isNot(contains('резерв')));
      expect(rec.message, isNot(contains('Энергия')));
    });

    test('maintain signal not overridden by low energy (already conservative)', () {
      final rec = evaluateProgression(
        {'weight': 100.0, 'reps': 7, 'reps_target': 10},
        energyState: const EnergyState(reserve: 35), // bucket 7
      );
      // Signal 1 fires (reps < target) → maintain; energy override is n/a
      expect(rec!.direction, ProgressionDirection.maintain);
    });

    test('decrease signal not overridden by low energy (already lower)', () {
      final rec = evaluateProgression(
        {
          'weight': 100.0,
          'reps': 10,
          'rpe': 9,
          'prev': {'rpe': 9, 'reps': 10},
        },
        energyState: const EnergyState(reserve: 55), // bucket 5
      );
      // Signal 2 fires (RPE 9+ twice) → decrease; energy override is n/a
      expect(rec!.direction, ProgressionDirection.decrease);
    });

    test('no energy state → normal behaviour', () {
      final rec = evaluateProgression(baseData);
      expect(rec!.direction, ProgressionDirection.increase);
    });
  });
}
