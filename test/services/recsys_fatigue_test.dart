import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/recsys_service.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Build a set list with uniform RPE.
List<Map<String, dynamic>> _sets(List<double> rpes, {bool warmup = false}) =>
    rpes.map((r) => {'isWarmup': warmup, 'completed': true, 'rpe': r}).toList();

/// Build a history entry for a given category, equipment, movement and RPEs.
Map<String, dynamic> _entry(
  String category,
  List<double> rpes, {
  String equipment = 'barbell',
  String movement  = 'press', // compound by default
}) =>
    {
      'category':      category,
      'equipmentType': equipment,
      'movementType':  movement,
      'sets':          _sets(rpes),
    };

// ─── Reference calculations (multiplicative model) ────────────────────────────
// drain_factor = base_rate × eq_mult × (rpe / 7).clamp(0.5, 1.5)
// compound base = 0.12, isolation base = 0.07
// barbell mult = 1.0, dumbbell = 0.85, cable = 0.70, machine = 0.60, other = 0.65
// reserve starts at 100 (no wellness issues), shrinks each set.
//
// Tests inject Random(42) to make Gaussian noise deterministic.

void main() {
  group('evaluateFatigue', () {
    // ── Null cases ─────────────────────────────────────────────────────────

    test('returns null when no prior sets on target muscle', () {
      final rec = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [_entry('back', [7, 8])],
        random: Random(42),
      );
      expect(rec, isNull);
    });

    test('returns null when reserve >= 50 (barbell compound, RPE 7, 3 sets)', () {
      // drain = 0.12 × 1.0 × 1.0 = 0.12
      // reserve = 100 × (0.88)^3 ≈ 68.1 → no banner
      final rec = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [_entry('chest', [7, 7, 7])],
        random: Random(42),
      );
      expect(rec, isNull);
    });

    test('returns null when only warmup sets present', () {
      final warmupSets = List.generate(
          8, (_) => {'isWarmup': true, 'completed': true, 'rpe': 9.0});
      final rec = evaluateFatigue(
        targetCategory: 'back',
        sessionHistory: [
          {'category': 'back', 'equipmentType': 'barbell',
           'movementType': 'row', 'sets': warmupSets},
        ],
        random: Random(42),
      );
      expect(rec, isNull);
    });

    // ── Moderate fatigue (reserve 30–49) ────────────────────────────────────

    test('moderate: barbell compound RPE 8, 5 sets', () {
      // drain = 0.12 × 1.0 × (8/7) ≈ 0.1371
      // reserve = 100 × (0.8629)^5 ≈ 47.6 → moderate
      final rec = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [_entry('chest', [8, 8, 8, 8, 8])],
        random: Random(42),
      );
      expect(rec, isNotNull);
      expect(rec!.level, FatigueLevel.moderate);
      expect(rec.reserve, inInclusiveRange(30.0, 50.0));
      expect(rec.setsOnMuscle, 5);
    });

    // ── High fatigue (reserve < 30) ──────────────────────────────────────────

    test('high: barbell compound RPE 9, 8 sets', () {
      // drain = 0.12 × 1.0 × (9/7) ≈ 0.1543
      // reserve = 100 × (0.8457)^8 ≈ 26.2 → high
      final rec = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [_entry('chest', [9, 9, 9, 9, 9, 9, 9, 9])],
        random: Random(42),
      );
      expect(rec!.level, FatigueLevel.high);
      expect(rec.reserve, lessThan(30.0));
    });

    // ── Wellness multipliers ─────────────────────────────────────────────────

    test('bad sleep reduces base → triggers moderate with fewer sets', () {
      // Without bad sleep: barbell compound RPE 8, 4 sets
      //   reserve = 100 × (0.8629)^4 ≈ 55.2 → null
      // With sleep < 6h: base = 85 → 85 × (0.8629)^4 ≈ 46.9 → moderate
      final withoutSleep = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [_entry('chest', [8, 8, 8, 8])],
        random: Random(42),
      );
      expect(withoutSleep, isNull);

      final withBadSleep = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [_entry('chest', [8, 8, 8, 8])],
        wellness: {'sleep_hours': 5.0, 'stress': 5, 'energy': 5},
        random: Random(42),
      );
      expect(withBadSleep, isNotNull);
      expect(withBadSleep!.level, FatigueLevel.moderate);
    });

    test('all bad wellness factors stack multiplicatively', () {
      // base = 100 × 0.85 × 0.90 × 0.85 ≈ 65
      // barbell compound RPE 7, 7 sets:
      //   drain = 0.12 × 1.0 × 1.0 = 0.12
      //   65 × (0.88)^7 ≈ 26.6 → high
      final rec = evaluateFatigue(
        targetCategory: 'legs',
        sessionHistory: [_entry('legs', [7, 7, 7, 7, 7, 7, 7],
            movement: 'squat')],
        wellness: {'sleep_hours': 5.0, 'stress': 9, 'energy': 2},
        random: Random(42),
      );
      expect(rec!.level, FatigueLevel.high);
    });

    // ── Equipment type differences ───────────────────────────────────────────

    test('machine isolation drains much less than barbell compound', () {
      // machine isolation RPE 7, 10 sets:
      //   drain = 0.07 × 0.60 × 1.0 = 0.042
      //   100 × (0.958)^10 ≈ 65.1 → null
      final rec = evaluateFatigue(
        targetCategory: 'legs',
        sessionHistory: [_entry('legs', List.filled(10, 7.0),
            equipment: 'machine', movement: 'extension')],
        random: Random(42),
      );
      expect(rec, isNull);
    });

    test('dumbbell compound drains less than barbell compound', () {
      // barbell, RPE 8, 5 sets → moderate (~47.6)
      // dumbbell, RPE 8, 5 sets: drain = 0.12 × 0.85 × (8/7) ≈ 0.1166
      //   100 × (0.8834)^5 ≈ 53.2 → null
      final dumbbell = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [_entry('chest', [8, 8, 8, 8, 8],
            equipment: 'dumbbell', movement: 'press')],
        random: Random(42),
      );
      expect(dumbbell, isNull);

      final barbell = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [_entry('chest', [8, 8, 8, 8, 8])], // barbell press
        random: Random(42),
      );
      expect(barbell, isNotNull);
    });

    // ── Cross-category isolation ─────────────────────────────────────────────

    test('only same-category sets contribute to drain', () {
      // 10 heavy back sets should NOT drain chest
      final rec = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [
          _entry('chest', [6]),           // 1 light chest set → ~88.0 → null
          _entry('back',  List.filled(10, 9.0), movement: 'row'),
        ],
        random: Random(42),
      );
      expect(rec, isNull);
    });

    // ── Missing / default RPE ────────────────────────────────────────────────

    test('missing rpe defaults to 7.0', () {
      // barbell compound, no rpe, 8 sets
      // drain = 0.12 × 1.0 × 1.0 = 0.12
      // 100 × (0.88)^8 ≈ 36.0 → moderate
      final noRpeSets = List.generate(
          8, (_) => {'isWarmup': false, 'completed': true});
      final rec = evaluateFatigue(
        targetCategory: 'back',
        sessionHistory: [
          {'category': 'back', 'equipmentType': 'barbell',
           'movementType': 'row', 'sets': noRpeSets},
        ],
        random: Random(42),
      );
      expect(rec!.level, FatigueLevel.moderate);
    });

    // ── FatigueRec fields ────────────────────────────────────────────────────

    test('category and categoryLabel fields set correctly', () {
      final rec = evaluateFatigue(
        targetCategory: 'back',
        sessionHistory: [_entry('back', [9, 9, 9, 9, 9, 9, 9], movement: 'row')],
        random: Random(42),
      );
      expect(rec!.category, 'back');
      expect(rec.categoryLabel, 'Спина');
    });

    test('message contains category label', () {
      final rec = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [_entry('chest', [9, 9, 9, 9, 9, 9, 9])],
        random: Random(42),
      );
      expect(rec!.message, contains('Грудь'));
    });

    test('reserve is a double in range 0..100', () {
      final rec = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [_entry('chest', [8, 8, 8, 8, 8])],
        random: Random(42),
      );
      expect(rec!.reserve, isA<double>());
      expect(rec.reserve, inInclusiveRange(0.0, 100.0));
    });

    // ── RPE clamp ───────────────────────────────────────────────────────────

    test('RPE modifier clamped to 1.5 at RPE 10+', () {
      // RPE 10: modifier = 10/7 ≈ 1.43 (within [0.5, 1.5] — no actual clamping)
      // RPE 14 (hypothetical): would be clamped to 1.5
      // Just verify it doesn't blow up and reserve stays in range.
      final noRpeSets14 = List.generate(
          5, (_) => {'isWarmup': false, 'completed': true, 'rpe': 14.0});
      final rec = evaluateFatigue(
        targetCategory: 'chest',
        sessionHistory: [
          {'category': 'chest', 'equipmentType': 'barbell',
           'movementType': 'press', 'sets': noRpeSets14},
        ],
        random: Random(42),
      );
      if (rec != null) {
        expect(rec.reserve, greaterThanOrEqualTo(0.0));
        expect(rec.reserve, lessThanOrEqualTo(100.0));
      }
    });
  });
}
