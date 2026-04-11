import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/recsys_service.dart';

void main() {
  // ─── 1. Autoregulation ─────────────────────────────────────────────────────
  group('evaluateAutoregulation', () {
    test('null when fewer than 4 valid RPEs', () {
      expect(evaluateAutoregulation([9.0, 9.0, 9.0]), isNull);
      expect(evaluateAutoregulation([9.0, null, 9.0, null]), isNull);
    });

    test('decrease when avg RPE >= 8.5', () {
      final rec = evaluateAutoregulation([9.0, 8.5, 9.0, 8.5]);
      expect(rec, isNotNull);
      expect(rec!.direction, AutoregDirection.decrease);
      expect(rec.sessionsAnalyzed, 4);
    });

    test('increase when avg RPE <= 6.5', () {
      final rec = evaluateAutoregulation([6.0, 6.5, 6.0, 6.5]);
      expect(rec, isNotNull);
      expect(rec!.direction, AutoregDirection.increase);
    });

    test('null when avg RPE is in target zone', () {
      expect(evaluateAutoregulation([7.0, 7.5, 8.0, 7.5]), isNull);
    });

    test('ignores null RPEs in average', () {
      final rec = evaluateAutoregulation([9.0, null, 9.0, null, 9.0, 9.0]);
      expect(rec, isNotNull);
      expect(rec!.sessionsAnalyzed, 4);
    });
  });

  // ─── 2. Rep range diversification ───────────────────────────────────────────
  group('evaluateRepRangeDiversification', () {
    test('null when fewer than 8 weeks of data', () {
      expect(evaluateRepRangeDiversification([10, 10, 10, 10]), isNull);
    });

    test('null when block changes within the streak', () {
      final rec = evaluateRepRangeDiversification(
          [10, 10, 5, 10, 10, 10, 10, 10]);
      expect(rec, isNull);
    });

    test('triggers after 8 weeks in hypertrophy → strength', () {
      final rec = evaluateRepRangeDiversification(
          [10, 10, 10, 10, 10, 10, 10, 10]);
      expect(rec, isNotNull);
      expect(rec!.currentBlock, RepRangeBlock.hypertrophy);
      expect(rec.suggestedBlock, RepRangeBlock.strength);
      expect(rec.weeksInBlock, greaterThanOrEqualTo(8));
    });

    test('triggers after 8 weeks in strength → hypertrophy', () {
      final rec =
          evaluateRepRangeDiversification([5, 5, 5, 5, 5, 5, 5, 5]);
      expect(rec, isNotNull);
      expect(rec!.currentBlock, RepRangeBlock.strength);
      expect(rec.suggestedBlock, RepRangeBlock.hypertrophy);
    });

    test('endurance block rotates to hypertrophy', () {
      final rec = evaluateRepRangeDiversification(
          [15, 15, 15, 15, 15, 15, 15, 15]);
      expect(rec, isNotNull);
      expect(rec!.currentBlock, RepRangeBlock.endurance);
      expect(rec.suggestedBlock, RepRangeBlock.hypertrophy);
    });
  });

  // ─── 3. Consistency ─────────────────────────────────────────────────────────
  group('evaluateConsistency', () {
    test('null when baseline too low', () {
      final rec = evaluateConsistency(
          sessionsLast2Weeks: 0, baselineSessionsPer2Weeks: 1.5);
      expect(rec, isNull);
    });

    test('null when drop is under 30%', () {
      final rec = evaluateConsistency(
          sessionsLast2Weeks: 4, baselineSessionsPer2Weeks: 5);
      expect(rec, isNull);
    });

    test('triggers on 50% drop', () {
      final rec = evaluateConsistency(
          sessionsLast2Weeks: 2, baselineSessionsPer2Weeks: 5);
      expect(rec, isNotNull);
      expect(rec!.dropPct, closeTo(60, 1));
    });

    test('triggers at zero recent sessions', () {
      final rec = evaluateConsistency(
          sessionsLast2Weeks: 0, baselineSessionsPer2Weeks: 4);
      expect(rec, isNotNull);
      expect(rec!.dropPct, 100);
    });
  });

  // ─── 4. Goal alignment ──────────────────────────────────────────────────────
  group('evaluateGoalAlignment', () {
    test('null when goal is null', () {
      expect(
          evaluateGoalAlignment(userGoal: null, avgRepsInProgram: 10), isNull);
    });

    test('strength goal with high reps triggers', () {
      final rec =
          evaluateGoalAlignment(userGoal: 'strength', avgRepsInProgram: 12);
      expect(rec, isNotNull);
      expect(rec!.recommendedRange, '3-6');
    });

    test('strength goal with low reps is aligned', () {
      expect(
          evaluateGoalAlignment(userGoal: 'strength', avgRepsInProgram: 5),
          isNull);
    });

    test('mass goal with very low reps triggers', () {
      final rec =
          evaluateGoalAlignment(userGoal: 'mass', avgRepsInProgram: 4);
      expect(rec, isNotNull);
      expect(rec!.recommendedRange, '8-12');
    });

    test('endurance goal with low reps triggers', () {
      final rec =
          evaluateGoalAlignment(userGoal: 'endurance', avgRepsInProgram: 8);
      expect(rec, isNotNull);
    });

    test('unknown goal returns null', () {
      expect(
          evaluateGoalAlignment(userGoal: 'recovery', avgRepsInProgram: 5),
          isNull);
    });
  });

  // ─── 5. PR readiness ────────────────────────────────────────────────────────
  group('evaluatePrReadiness', () {
    final goodWellness = {'sleep_hours': 8.0, 'stress': 3, 'energy': 8};
    final goodCandidate = {
      'exerciseId': 'ex1',
      'exerciseName': 'Жим лёжа',
      'currentWeightKg': 80.0,
      'consecutiveFullSessions': 3,
      'daysSinceLastPr': 20,
    };

    test('null when wellness is null', () {
      expect(
          evaluatePrReadiness(wellness: null, candidate: goodCandidate), isNull);
    });

    test('null when sleep too low', () {
      expect(
          evaluatePrReadiness(
              wellness: {...goodWellness, 'sleep_hours': 6.0},
              candidate: goodCandidate),
          isNull);
    });

    test('null when too few consecutive sessions', () {
      expect(
          evaluatePrReadiness(
              wellness: goodWellness,
              candidate: {...goodCandidate, 'consecutiveFullSessions': 2}),
          isNull);
    });

    test('null when PR too recent', () {
      expect(
          evaluatePrReadiness(
              wellness: goodWellness,
              candidate: {...goodCandidate, 'daysSinceLastPr': 5}),
          isNull);
    });

    test('triggers on ideal conditions', () {
      final rec = evaluatePrReadiness(
          wellness: goodWellness, candidate: goodCandidate);
      expect(rec, isNotNull);
      expect(rec!.suggestedWeightKg, 82.5);
      expect(rec.confidence, greaterThan(0));
    });
  });

  // ─── 6. Volume landmarks ────────────────────────────────────────────────────
  group('evaluateVolumeLandmarks', () {
    test('null when all within range', () {
      final rec = evaluateVolumeLandmarks({
        'chest': 14,
        'back': 15,
        'legs': 14,
      });
      expect(rec, isNull);
    });

    test('flags below-MEV chest', () {
      final rec = evaluateVolumeLandmarks({'chest': 6});
      expect(rec, isNotNull);
      expect(rec!.zone, VolumeZone.belowMev);
      expect(rec.muscleGroup, 'chest');
    });

    test('flags above-MRV legs', () {
      final rec = evaluateVolumeLandmarks({'legs': 30});
      expect(rec, isNotNull);
      expect(rec!.zone, VolumeZone.aboveMrv);
    });

    test('picks worst deviation among several', () {
      final rec = evaluateVolumeLandmarks({
        'chest': 8, // 2 below MEV (10)
        'legs': 35, // 10 above MRV (25)
      });
      expect(rec, isNotNull);
      expect(rec!.muscleGroup, 'legs');
    });

    test('ignores unknown muscle keys', () {
      expect(evaluateVolumeLandmarks({'neck': 0}), isNull);
    });
  });

  // ─── 7. Exercise variations ─────────────────────────────────────────────────
  group('evaluateExerciseVariations', () {
    test('null when none stagnant long enough', () {
      expect(
          evaluateExerciseVariations([
            {'exerciseId': 'a', 'exerciseName': 'Жим лёжа', 'weeksStagnant': 3}
          ]),
          isNull);
    });

    test('matches known variation by substring', () {
      final rec = evaluateExerciseVariations([
        {'exerciseId': 'a', 'exerciseName': 'Жим лёжа', 'weeksStagnant': 8}
      ]);
      expect(rec, isNotNull);
      expect(rec!.suggestedVariations.isNotEmpty, true);
      expect(rec.suggestedVariations.first, contains('гантел'));
    });

    test('falls back to generic variations on unknown exercise', () {
      final rec = evaluateExerciseVariations([
        {
          'exerciseId': 'x',
          'exerciseName': 'Какое-то странное',
          'weeksStagnant': 10
        }
      ]);
      expect(rec, isNotNull);
      expect(rec!.suggestedVariations.length, 3);
    });

    test('picks the most stagnant among candidates', () {
      final rec = evaluateExerciseVariations([
        {'exerciseId': 'a', 'exerciseName': 'Приседания', 'weeksStagnant': 6},
        {
          'exerciseId': 'b',
          'exerciseName': 'Становая тяга',
          'weeksStagnant': 12
        },
      ]);
      expect(rec, isNotNull);
      expect(rec!.stagnantExerciseId, 'b');
      expect(rec.weeksStagnant, 12);
    });
  });

  // ─── 8. Frequency optimization ──────────────────────────────────────────────
  group('evaluateFrequencyOptimization', () {
    test('null when frequencies are healthy', () {
      expect(
          evaluateFrequencyOptimization(
              {'chest': 3.5, 'back': 4.0, 'legs': 5.0}),
          isNull);
    });

    test('triggers when a group is trained less than once per week', () {
      final rec =
          evaluateFrequencyOptimization({'chest': 3.5, 'legs': 10.0});
      expect(rec, isNotNull);
      expect(rec!.muscleGroup, 'legs');
    });

    test('picks worst (rarest) muscle', () {
      final rec = evaluateFrequencyOptimization(
          {'chest': 7.0, 'legs': 9.0, 'back': 8.0});
      expect(rec, isNotNull);
      expect(rec!.muscleGroup, 'legs');
    });

    test('ignores unknown muscle keys', () {
      expect(
          evaluateFrequencyOptimization({'forearms': 20.0}), isNull);
    });
  });

  // ─── 9. Volume ramp ─────────────────────────────────────────────────────────
  group('evaluateVolumeRamp', () {
    test('null when baseline is zero', () {
      expect(
          evaluateVolumeRamp(currentWeekVolume: 1000, prior4WeekAvg: 0),
          isNull);
    });

    test('null when ramp ≤ 20%', () {
      expect(
          evaluateVolumeRamp(
              currentWeekVolume: 1150, prior4WeekAvg: 1000),
          isNull);
    });

    test('warning at 21-30%', () {
      final rec = evaluateVolumeRamp(
          currentWeekVolume: 1250, prior4WeekAvg: 1000);
      expect(rec, isNotNull);
      expect(rec!.severity, VolumeRampSeverity.warning);
    });

    test('danger above 30%', () {
      final rec = evaluateVolumeRamp(
          currentWeekVolume: 1500, prior4WeekAvg: 1000);
      expect(rec, isNotNull);
      expect(rec!.severity, VolumeRampSeverity.danger);
      expect(rec.rampPct, closeTo(50, 0.1));
    });
  });

  // ─── 10. Time of day ────────────────────────────────────────────────────────
  group('evaluateTimeOfDay', () {
    List<Map<String, dynamic>> bucket(int hour, List<double> vols) =>
        vols.map((v) => {'hour': hour, 'volumeKg': v}).toList();

    test('null with too few sessions', () {
      expect(evaluateTimeOfDay([]), isNull);
    });

    test('null when buckets not all filled', () {
      final sessions = [
        ...bucket(8, [1000, 1000, 1000]),
        ...bucket(13, [1000, 1000, 1000]),
        // no evening
        ...bucket(20, [1000, 1000]),
      ];
      expect(evaluateTimeOfDay(sessions), isNull);
    });

    test('null when delta < 15%', () {
      final sessions = [
        ...bucket(8, [1000, 1010, 1000]),
        ...bucket(13, [1050, 1050, 1050]),
        ...bucket(20, [1020, 1000, 1030]),
      ];
      expect(evaluateTimeOfDay(sessions), isNull);
    });

    test('detects best time when delta > 15%', () {
      final sessions = [
        ...bucket(8, [800, 850, 800]),
        ...bucket(13, [900, 900, 900]),
        ...bucket(20, [1200, 1200, 1200]),
      ];
      final rec = evaluateTimeOfDay(sessions);
      expect(rec, isNotNull);
      expect(rec!.bestTime, TimeOfDay.evening);
      expect(rec.deltaPct, greaterThan(15));
    });
  });

  // ─── 11. DOMS ───────────────────────────────────────────────────────────────
  group('evaluateDoms', () {
    test('null when soreness is low', () {
      expect(
          evaluateDoms(
              soreness: 2,
              plannedMuscle: 'chest',
              plannedMuscleRecentlyWorked: true),
          isNull);
    });

    test('null when muscle not recently worked', () {
      expect(
          evaluateDoms(
              soreness: 5,
              plannedMuscle: 'chest',
              plannedMuscleRecentlyWorked: false),
          isNull);
    });

    test('null when planned muscle is null', () {
      expect(
          evaluateDoms(
              soreness: 5,
              plannedMuscle: null,
              plannedMuscleRecentlyWorked: true),
          isNull);
    });

    test('triggers at soreness 4 with recent work', () {
      final rec = evaluateDoms(
          soreness: 4,
          plannedMuscle: 'legs',
          plannedMuscleRecentlyWorked: true);
      expect(rec, isNotNull);
      expect(rec!.plannedMuscleLabel, 'ноги');
    });
  });

  // ─── 12. Session duration ───────────────────────────────────────────────────
  group('evaluateSessionDuration', () {
    Map<String, dynamic> s(double dur, double first, double last) => {
          'durationMin': dur,
          'firstThirdAvgVolume': first,
          'lastThirdAvgVolume': last,
        };

    test('null when too few long sessions', () {
      expect(
          evaluateSessionDuration(
              [s(80, 1000, 800), s(85, 1000, 800), s(80, 1000, 800)]),
          isNull);
    });

    test('null when all sessions are under 75 min', () {
      expect(
          evaluateSessionDuration([
            s(60, 1000, 500),
            s(60, 1000, 500),
            s(60, 1000, 500),
            s(60, 1000, 500)
          ]),
          isNull);
    });

    test('null when last-third drop is small', () {
      expect(
          evaluateSessionDuration([
            s(80, 1000, 950),
            s(85, 1000, 960),
            s(85, 1000, 950),
            s(90, 1000, 970)
          ]),
          isNull);
    });

    test('triggers when long sessions have >10% drop', () {
      final rec = evaluateSessionDuration([
        s(90, 1000, 700),
        s(90, 1000, 750),
        s(85, 1000, 700),
        s(95, 1000, 800),
      ]);
      expect(rec, isNotNull);
      expect(rec!.lastThirdDropPct, greaterThan(10));
      expect(rec.sessionsAnalyzed, 4);
    });
  });
}
