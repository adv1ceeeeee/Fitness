import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/gamification_config.dart';

void main() {
  // ─── Level curve ───────────────────────────────────────────────────────────

  group('xpForLevel', () {
    test('level 0 requires 0 XP', () {
      expect(xpForLevel(0), 0);
    });

    test('level 1 requires 100 XP', () {
      expect(xpForLevel(1), 100);
    });

    test('level 5 requires 600 XP', () {
      // 5*25 + 95*5 = 125 + 475 = 600
      expect(xpForLevel(5), 600);
    });

    test('level 10 requires 1450 XP', () {
      // 5*100 + 95*10 = 500 + 950 = 1450
      expect(xpForLevel(10), 1450);
    });

    test('level 50 requires 17250 XP', () {
      // 5*2500 + 95*50 = 12500 + 4750 = 17250
      expect(xpForLevel(50), 17250);
    });

    test('negative level returns 0', () {
      expect(xpForLevel(-1), 0);
    });
  });

  group('xpToNextLevel', () {
    test('from level 0 → 100 XP needed', () {
      expect(xpToNextLevel(0), 100);
    });

    test('from level 10 → 200 XP needed', () {
      expect(xpToNextLevel(10), 200);
    });

    test('from level 50 → 600 XP needed', () {
      expect(xpToNextLevel(50), 600);
    });
  });

  group('levelFromXp', () {
    test('0 XP → level 0', () {
      expect(levelFromXp(0), 0);
    });

    test('99 XP → level 0 (not yet 1)', () {
      expect(levelFromXp(99), 0);
    });

    test('100 XP → level 1', () {
      expect(levelFromXp(100), 1);
    });

    test('600 XP → level 5', () {
      expect(levelFromXp(600), 5);
    });

    test('601 XP → still level 5', () {
      expect(levelFromXp(601), 5);
    });

    test('1450 XP → level 10', () {
      expect(levelFromXp(1450), 10);
    });

    test('17250 XP → level 50', () {
      expect(levelFromXp(17250), 50);
    });

    test('negative XP → level 0', () {
      expect(levelFromXp(-100), 0);
    });

    test('roundtrip: xpForLevel → levelFromXp', () {
      for (int level = 0; level <= 100; level++) {
        final xp = xpForLevel(level);
        expect(levelFromXp(xp), level, reason: 'level $level with $xp XP');
      }
    });

    test('XP just below next level stays at current', () {
      for (int level = 0; level <= 50; level++) {
        final xpNeeded = xpForLevel(level + 1);
        expect(levelFromXp(xpNeeded - 1), level,
            reason: 'level $level with ${xpNeeded - 1} XP');
      }
    });
  });

  group('levelProgress', () {
    test('at level start → 0.0', () {
      expect(levelProgress(xpForLevel(5)), 0.0);
    });

    test('halfway through level → ~0.5', () {
      final start = xpForLevel(5);
      final end = xpForLevel(6);
      final mid = start + ((end - start) ~/ 2);
      final progress = levelProgress(mid);
      expect(progress, closeTo(0.5, 0.01));
    });

    test('just before next level → close to 1.0', () {
      final nextStart = xpForLevel(6);
      final progress = levelProgress(nextStart - 1);
      expect(progress, greaterThan(0.9));
    });

    test('at 0 XP → 0.0', () {
      expect(levelProgress(0), 0.0);
    });
  });

  // ─── Titles ────────────────────────────────────────────────────────────────

  group('titleForLevel', () {
    test('level 0 → Новичок', () {
      expect(titleForLevel(0).name, 'Новичок');
    });

    test('level 4 → Новичок', () {
      expect(titleForLevel(4).name, 'Новичок');
    });

    test('level 5 → Любитель', () {
      expect(titleForLevel(5).name, 'Любитель');
    });

    test('level 10 → Спортсмен', () {
      expect(titleForLevel(10).name, 'Спортсмен');
    });

    test('level 20 → Атлет', () {
      expect(titleForLevel(20).name, 'Атлет');
    });

    test('level 30 → Мастер', () {
      expect(titleForLevel(30).name, 'Мастер');
    });

    test('level 40 → Элита', () {
      expect(titleForLevel(40).name, 'Элита');
    });

    test('level 50 → Легенда', () {
      expect(titleForLevel(50).name, 'Легенда');
    });

    test('level 100 → still Легенда', () {
      expect(titleForLevel(100).name, 'Легенда');
    });
  });

  // ─── App time XP ───────────────────────────────────────────────────────────

  group('appTimeXp', () {
    test('0 seconds → 0 XP', () {
      expect(appTimeXp(0), 0);
    });

    test('5 minutes → 5 XP (1 XP/min tier)', () {
      expect(appTimeXp(5 * 60), 5);
    });

    test('10 minutes → 10 XP', () {
      expect(appTimeXp(10 * 60), 10);
    });

    test('20 minutes → 15 XP (10 + 5 from 0.5 tier)', () {
      expect(appTimeXp(20 * 60), 15);
    });

    test('30 minutes → 20 XP', () {
      expect(appTimeXp(30 * 60), 20);
    });

    test('60 minutes → 27 XP (cap)', () {
      expect(appTimeXp(60 * 60), 27);
    });

    test('120 minutes → 27 XP (still capped)', () {
      expect(appTimeXp(120 * 60), 27);
    });

    test('negative → 0', () {
      expect(appTimeXp(-60), 0);
    });
  });

  // ─── Training duration XP ─────────────────────────────────────────────────

  group('trainingDurationXp', () {
    test('0 seconds → 0 XP', () {
      expect(trainingDurationXp(0), 0);
    });

    test('10 minutes → 5 XP', () {
      expect(trainingDurationXp(10 * 60), 5);
    });

    test('30 minutes → 15 XP', () {
      expect(trainingDurationXp(30 * 60), 15);
    });

    test('60 minutes → 30 XP (cap)', () {
      expect(trainingDurationXp(60 * 60), 30);
    });

    test('90 minutes → still 30 XP (capped at 60 min)', () {
      expect(trainingDurationXp(90 * 60), 30);
    });
  });

  // ─── Daily activity multiplier ─────────────────────────────────────────────

  group('dailyActivityMultiplier', () {
    test('0 actions → 1.0x', () {
      expect(dailyActivityMultiplier(0), 1.0);
    });

    test('2 actions → 1.0x', () {
      expect(dailyActivityMultiplier(2), 1.0);
    });

    test('3 actions → 1.2x', () {
      expect(dailyActivityMultiplier(3), 1.2);
    });

    test('5 actions → 1.2x', () {
      expect(dailyActivityMultiplier(5), 1.2);
    });

    test('6 actions → 1.5x', () {
      expect(dailyActivityMultiplier(6), 1.5);
    });

    test('10 actions → 1.5x', () {
      expect(dailyActivityMultiplier(10), 1.5);
    });

    test('11 actions → 2.0x', () {
      expect(dailyActivityMultiplier(11), 2.0);
    });
  });

  // ─── Season decay ─────────────────────────────────────────────────────────

  group('applySeasonDecay', () {
    test('10000 XP → 5000 XP', () {
      expect(applySeasonDecay(10000), 5000);
    });

    test('0 XP → 0 XP', () {
      expect(applySeasonDecay(0), 0);
    });

    test('1 XP → 1 XP (rounds up)', () {
      expect(applySeasonDecay(1), 1);
    });

    test('odd number rounds correctly', () {
      expect(applySeasonDecay(17251), 8626);
    });
  });

  group('currentSeasonStart', () {
    test('returns Jan 1 or Jul 1', () {
      final start = currentSeasonStart();
      expect(start.day, 1);
      expect([1, 7], contains(start.month));
    });
  });

  group('nextSeasonStart', () {
    test('is after currentSeasonStart', () {
      expect(nextSeasonStart().isAfter(currentSeasonStart()), isTrue);
    });

    test('returns Jan 1 or Jul 1', () {
      final next = nextSeasonStart();
      expect(next.day, 1);
      expect([1, 7], contains(next.month));
    });
  });

  // ─── Convergence simulation ────────────────────────────────────────────────

  group('season convergence', () {
    test('regular player (3×/week) converges around level 35-42', () {
      // 80 XP/workout × 3/week × 26 weeks = 6240 XP/season
      const xpPerSeason = 6240;
      int xp = 0;
      for (int season = 0; season < 20; season++) {
        xp = applySeasonDecay(xp) + xpPerSeason;
      }
      final level = levelFromXp(xp);
      expect(level, inInclusiveRange(34, 42));
    });

    test('casual player (2×/week) converges around level 28-32', () {
      const xpPerSeason = 4160;
      int xp = 0;
      for (int season = 0; season < 20; season++) {
        xp = applySeasonDecay(xp) + xpPerSeason;
      }
      final level = levelFromXp(xp);
      expect(level, inInclusiveRange(26, 34));
    });

    test('hardcore player (5×/week) converges around level 48-54', () {
      const xpPerSeason = 10400;
      int xp = 0;
      for (int season = 0; season < 20; season++) {
        xp = applySeasonDecay(xp) + xpPerSeason;
      }
      final level = levelFromXp(xp);
      expect(level, inInclusiveRange(46, 56));
    });
  });
}
