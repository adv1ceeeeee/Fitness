import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/screens/tools/calculators_screen.dart';

void main() {
  // ─── calculatePlates (greedy) ──────────────────────────────────────────────

  group('calculatePlates', () {
    const kg = plateWeightsKg;

    test('target equals bar — no plates', () {
      expect(calculatePlates(20, 20, kg), isEmpty);
    });

    test('target below bar — no plates', () {
      expect(calculatePlates(15, 20, kg), isEmpty);
    });

    test('100 kg on 20 kg bar → 25+15 per side', () {
      // perSide = 40: 25 fits (rem=15), then 15 fits (rem=0)
      expect(calculatePlates(100, 20, kg), [25.0, 15.0]);
    });

    test('60 kg on 20 kg bar → 1×20 per side', () {
      expect(calculatePlates(60, 20, kg), [20.0]);
    });

    test('90 kg on 20 kg bar → 25+10 per side', () {
      expect(calculatePlates(90, 20, kg), [25.0, 10.0]);
    });

    test('25 kg on 20 kg bar → 2.5 per side', () {
      expect(calculatePlates(25, 20, kg), [2.5]);
    });

    test('exact fit with fractional plates', () {
      // 22.5 kg bar included: (22.5 - 20) / 2 = 1.25 per side
      expect(calculatePlates(22.5, 20, kg), [1.25]);
    });

    test('large weight uses multiple plate types', () {
      // 185 kg: per side = 82.5 → 3×25 + 7.5 → 3×25 + 5 + 2.5
      expect(calculatePlates(185, 20, kg), [25.0, 25.0, 25.0, 5.0, 2.5]);
    });
  });

  // ─── calculatePlatesWithPrimary ────────────────────────────────────────────

  group('calculatePlatesWithPrimary', () {
    const kg = plateWeightsKg;
    const bar = 20.0;

    test('target = bar — empty regardless of primary', () {
      expect(calculatePlatesWithPrimary(20, bar, 25, kg), isEmpty);
    });

    test('primary 25: 90 kg → [25, 10]', () {
      expect(calculatePlatesWithPrimary(90, bar, 25, kg), [25.0, 10.0]);
    });

    test('primary 20: 90 kg → [20, 15]', () {
      expect(calculatePlatesWithPrimary(90, bar, 20, kg), [20.0, 15.0]);
    });

    test('primary 15: 90 kg → [15, 15, 5]', () {
      expect(calculatePlatesWithPrimary(90, bar, 15, kg), [15.0, 15.0, 5.0]);
    });

    test('primary 10: 90 kg → [10, 10, 10, 5]', () {
      expect(calculatePlatesWithPrimary(90, bar, 10, kg), [10.0, 10.0, 10.0, 5.0]);
    });

    test('primary 25 dominates: 120 kg → [25, 25, 5]', () {
      // per side = 50: 2×25 + 0, or with rounding 2×25 exactly
      expect(calculatePlatesWithPrimary(120, bar, 25, kg), [25.0, 25.0]);
    });

    test('primary 25 with remainder: 105 kg → [25, 15, 2.5]', () {
      // perSide = 42.5: 1×25 (rem=17.5), skip 25/20, 1×15 (rem=2.5), 1×2.5
      expect(calculatePlatesWithPrimary(105, bar, 25, kg), [25.0, 15.0, 2.5]);
    });

    test('primary larger than perSide: falls back to smaller plates', () {
      // target=30, bar=20, perSide=5; primary=25 can't fit
      // smaller plates: skip 25, skip 20, try 15: nope, try 10: nope, try 5: yes
      expect(calculatePlatesWithPrimary(30, bar, 25, kg), [5.0]);
    });

    test('primary 25 not included when it cannot fit → hasPrimary=false scenario', () {
      // target=24, bar=20, perSide=2; skip 25/20/15/10/5/2.5, only 1.25 fits
      final result = calculatePlatesWithPrimary(24, bar, 25, kg);
      expect(result, [1.25]);
      expect(result.any((p) => (p - 25).abs() < 0.001), false);
    });
  });

  // ─── groupPlates ───────────────────────────────────────────────────────────

  group('groupPlates', () {
    test('empty list returns empty map', () {
      expect(groupPlates([]), isEmpty);
    });

    test('single plate', () {
      expect(groupPlates([25.0]), {25.0: 1});
    });

    test('two same plates', () {
      expect(groupPlates([25.0, 25.0]), {25.0: 2});
    });

    test('mixed plates', () {
      expect(groupPlates([25.0, 25.0, 10.0]), {25.0: 2, 10.0: 1});
    });

    test('many plate types', () {
      final result = groupPlates([25.0, 25.0, 10.0, 5.0, 2.5]);
      expect(result[25.0], 2);
      expect(result[10.0], 1);
      expect(result[5.0], 1);
      expect(result[2.5], 1);
    });
  });

  // ─── buildWarmupSets ───────────────────────────────────────────────────────

  group('buildWarmupSets', () {
    test('first set is always joint warmup', () {
      final sets = buildWarmupSets(100, 20, true);
      expect(sets.first.type, WarmupSetType.joint);
      expect(sets.first.weight, 0);
      expect(sets.first.reps, 0);
    });

    test('second set is always bar-only general warmup', () {
      final sets = buildWarmupSets(100, 20, true);
      expect(sets[1].type, WarmupSetType.general);
      expect(sets[1].weight, 20);
      expect(sets[1].reps, 10);
    });

    test('target barely above bar (ratio < 1.5) — only joint + bar', () {
      final sets = buildWarmupSets(25, 20, true); // ratio = 1.25
      expect(sets.length, 2);
      expect(sets[0].type, WarmupSetType.joint);
      expect(sets[1].type, WarmupSetType.general);
    });

    test('ratio 1.5–2.5 adds 1 leadIn set', () {
      final sets = buildWarmupSets(40, 20, true); // ratio = 2.0
      expect(sets.length, 3);
      expect(sets.last.type, WarmupSetType.leadIn);
    });

    test('ratio 2.5–4.0 adds specific + leadIn', () {
      final sets = buildWarmupSets(70, 20, true); // ratio = 3.5
      final types = sets.map((s) => s.type).toList();
      expect(types.contains(WarmupSetType.specific), true);
      expect(types.last, WarmupSetType.leadIn);
    });

    test('ratio 4.0–6.0 adds 2 specific + leadIn', () {
      final sets = buildWarmupSets(100, 20, true); // ratio = 5.0
      final programSets = sets.skip(2).toList(); // skip joint + bar
      expect(programSets.length, 3);
      expect(programSets[0].type, WarmupSetType.specific);
      expect(programSets[1].type, WarmupSetType.specific);
      expect(programSets[2].type, WarmupSetType.leadIn);
    });

    test('ratio >= 6.0 adds 3 specific + leadIn', () {
      final sets = buildWarmupSets(140, 20, true); // ratio = 7.0
      final programSets = sets.skip(2).toList();
      expect(programSets.length, 4);
      expect(programSets.last.type, WarmupSetType.leadIn);
    });

    test('intermediate weights rounded to 2.5 kg step', () {
      final sets = buildWarmupSets(100, 20, true);
      for (final s in sets) {
        if (s.weight > 0 && s.weight != 100) {
          expect(s.weight % 2.5, closeTo(0, 0.001),
              reason: 'weight ${s.weight} not a 2.5 multiple');
        }
      }
    });

    test('lb mode: intermediate weights rounded to 5 lb step', () {
      final sets = buildWarmupSets(225, 45, false);
      for (final s in sets) {
        if (s.weight > 0 && s.weight != 225) {
          expect(s.weight % 5.0, closeTo(0, 0.001),
              reason: 'lb weight ${s.weight} not a 5 multiple');
        }
      }
    });

    test('no duplicate intermediate weights', () {
      final sets = buildWarmupSets(100, 20, true);
      final weights = sets.map((s) => s.weight).toList();
      expect(weights.toSet().length, weights.length);
    });

    test('intermediate weights between bar and target', () {
      const target = 100.0;
      const bar = 20.0;
      final sets = buildWarmupSets(target, bar, true);
      for (final s in sets.skip(2)) {
        expect(s.weight, greaterThanOrEqualTo(bar));
        expect(s.weight, lessThan(target));
      }
    });

    test('last set before working weight is leadIn', () {
      final sets = buildWarmupSets(100, 20, true);
      // Last in sets (before appended working weight row in UI) should be leadIn
      final programSets = sets.where((s) => s.type != WarmupSetType.joint
          && s.type != WarmupSetType.general).toList();
      expect(programSets.last.type, WarmupSetType.leadIn);
    });
  });
}
