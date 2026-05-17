/// Unified RecSys state — single source of truth for all recommendations.
///
/// [computeUserState] fetches all inputs once, computes every recommendation
/// from the same snapshot, and caches the result for 30 minutes. This
/// guarantees that all cards on the home screen and workout session screen
/// are always internally consistent (no contradictions between energy level,
/// wellness advice, progression, etc.).
///
/// v2 additions:
///  • 12 new evaluators integrated alongside the original 5
///  • [ScoredRec] priority scoring — UI shows top-N, not everything
///  • [RecContext] timing tags — pre-workout / post-workout / rest-day / program
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/app_cache.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/recsys_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/wellness_service.dart';

// ─── Scoring & context ─────────────────────────────────────────────────────

/// When a recommendation is most relevant.
enum RecContext {
  /// Show before the user starts a workout (DOMS, PR readiness, autoregulation).
  preWorkout,
  /// Show after a workout completes (volume ramp, session duration, consistency).
  postWorkout,
  /// Show on days without a workout (consistency, wellness, time-of-day).
  restDay,
  /// Show on the program/workouts screen (goal alignment, frequency, rep-range).
  program,
  /// Always relevant (wellness, deload, plateau, muscle balance).
  always,
}

/// A recommendation with a priority score and context tag.
/// UI should filter by context and show the top-N by priority.
class ScoredRec {
  final String id;
  final String title;
  final String message;
  final double priority;       // 0.0–1.0, higher = more urgent
  final RecContext context;
  /// Optional severity for visual treatment (red/yellow/blue).
  final RecSeverity? severity;

  const ScoredRec({
    required this.id,
    required this.title,
    required this.message,
    required this.priority,
    required this.context,
    this.severity,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'priority': priority,
    'context': context.name,
    if (severity != null) 'severity': severity!.name,
  };

  factory ScoredRec.fromJson(Map<String, dynamic> json) => ScoredRec(
    id: json['id'] as String,
    title: json['title'] as String,
    message: json['message'] as String,
    priority: (json['priority'] as num).toDouble(),
    context: RecContext.values.firstWhere(
      (e) => e.name == json['context'],
      orElse: () => RecContext.always,
    ),
    severity: json['severity'] != null
        ? RecSeverity.values.firstWhere(
            (e) => e.name == json['severity'],
            orElse: () => RecSeverity.info,
          )
        : null,
  );
}

// ─── Data class ───────────────────────────────────────────────────────────────

class UserState {
  /// Energy reserve 0–100 % with today's wellness cap applied.
  final EnergyState energyState;

  /// Today's wellness recommendation (null = no concerning indicators).
  final WellnessRec? wellnessRec;

  /// Raw today's wellness_logs row (for inline display / wellness card).
  final Map<String, dynamic>? todayWellness;

  /// User's training goal from profiles.goal.
  final String? userGoal;

  /// RPE calibration offset: median reported RPE − 7.0, clamped −2..+2.
  final double rpeCalibrationOffset;

  // ── Original recs (v1) ──────────────────────────────────────────────────
  final MuscleImbalanceRec? muscleImbalanceRec;
  final DeloadRec? deloadRec;
  final PlateauRec? plateauRec;
  final WellnessCorrelationRec? wellnessCorrelationRec;

  // ── Scored recommendations (v2) ─────────────────────────────────────────
  /// All fired recommendations, scored and tagged. Sorted by priority desc.
  final List<ScoredRec> scoredRecs;

  const UserState({
    required this.energyState,
    this.wellnessRec,
    this.todayWellness,
    this.userGoal,
    this.rpeCalibrationOffset = 0.0,
    this.muscleImbalanceRec,
    this.deloadRec,
    this.plateauRec,
    this.wellnessCorrelationRec,
    this.scoredRecs = const [],
  });

  /// Top-N recommendations filtered by context. Use from UI.
  List<ScoredRec> topRecs({RecContext? context, int limit = 3}) {
    final filtered = context == null
        ? scoredRecs
        : scoredRecs.where((r) =>
            r.context == context || r.context == RecContext.always).toList();
    return filtered.take(limit).toList();
  }

  // ── Serialization for AppCache ─────────────────────────────────────────
  Map<String, dynamic> toJson() {
    final rec = wellnessRec;
    return {
      'energyReserve': energyState.reserve,
      'todayWellness': todayWellness,
      'userGoal': userGoal,
      'rpeCalibrationOffset': rpeCalibrationOffset,
      if (rec != null) 'wellnessRec': {
        'severity': rec.severity.name,
        'title': rec.title,
        'message': rec.message,
      },
      'scoredRecs': scoredRecs.map((r) => r.toJson()).toList(),
    };
  }

  factory UserState.fromJson(Map<String, dynamic> json) {
    final wrMap = json['wellnessRec'] as Map<String, dynamic>?;
    final recsJson = json['scoredRecs'] as List?;
    return UserState(
      energyState: EnergyState(
        reserve: (json['energyReserve'] as num?)?.toDouble() ?? 100.0,
      ),
      wellnessRec: wrMap == null
          ? null
          : WellnessRec(
              severity: RecSeverity.values.firstWhere(
                (e) => e.name == wrMap['severity'],
                orElse: () => RecSeverity.info,
              ),
              title: wrMap['title'] as String,
              message: wrMap['message'] as String,
            ),
      todayWellness: (json['todayWellness'] as Map?)?.cast<String, dynamic>(),
      userGoal: json['userGoal'] as String?,
      rpeCalibrationOffset:
          (json['rpeCalibrationOffset'] as num?)?.toDouble() ?? 0.0,
      scoredRecs: recsJson
              ?.map((e) => ScoredRec.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class UserStateService {
  UserStateService._();

  static Future<UserState> computeUserState() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) {
      return const UserState(energyState: EnergyState(reserve: 100));
    }
    // Cache key includes today's date so a snapshot from yesterday
    // automatically misses on the next calendar day — previously the
    // 30-min TTL + stale-while-revalidate kept showing yesterday's
    // wellness-logged state on cold opens at midnight, hiding the
    // "Как самочувствие?" card and locking in stale energy %.
    return AppCache.get<UserState>(
      key: 'user_state:$userId:${_todayKey()}',
      ttl: const Duration(minutes: 30),
      fetch: () => _fetch(userId),
      encode: (s) => jsonEncode(s.toJson()),
      decode: (raw) => raw == null
          ? const UserState(energyState: EnergyState(reserve: 100))
          : UserState.fromJson(jsonDecode(raw) as Map<String, dynamic>),
    );
  }

  static String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static Future<void> invalidate() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    // Wipe every day's snapshot so stale ones from earlier in the week
    // can never resurface after a wellness/profile/training change.
    await AppCache.invalidatePrefix('user_state:$userId');
  }

  static Future<UserState> _fetch(String userId) async {
    // ── Phase 1: parallel data fetch ──────────────────────────────────────
    // All calls are individually guarded so a single failure never kills
    // the whole UserState.
    final results = await Future.wait([
      // Original v1 sources
      WellnessService.getTodayLog()
          .catchError((_) => null as Map<String, dynamic>?),            // [0]
      AnalyticsService.getEnergyState()
          .catchError((_) => const EnergyState(reserve: 100)),          // [1]
      ProfileService.getProfile()
          .catchError((_) => null as Profile?),                         // [2]
      AnalyticsService.getRpeCalibrationOffset()
          .catchError((_) => 0.0),                                      // [3]
      AnalyticsService.getMuscleGroupBalance()
          .catchError((_) => <String, int>{}),                          // [4]
      AnalyticsService.getDeloadMetrics()
          .catchError((_) => null as Map<String, dynamic>?),            // [5]
      AnalyticsService.getStagnantExercises()
          .catchError((_) => <Map<String, dynamic>>[]),                 // [6]
      AnalyticsService.getWellnessPerformanceCorrelation()
          .catchError((_) => <Map<String, dynamic>>[]),                 // [7]

      // v2 sources for new evaluators
      AnalyticsService.getRecentRpes()
          .catchError((_) => <double?>[]),                              // [8]
      AnalyticsService.getConsistencyData()
          .catchError((_) => <String, dynamic>{}),                      // [9]
      AnalyticsService.getAvgRepsInProgram()
          .catchError((_) => 0.0),                                      // [10]
      AnalyticsService.getCurrentWeekSetsByMuscle()
          .catchError((_) => <String, int>{}),                          // [11]
      AnalyticsService.getAvgDaysBetweenSessionsByMuscle()
          .catchError((_) => <String, double>{}),                       // [12]
      AnalyticsService.getVolumeRampData()
          .catchError((_) => <String, double>{}),                       // [13]
      AnalyticsService.getSessionsByTimeOfDay()
          .catchError((_) => <Map<String, dynamic>>[]),                 // [14]
      AnalyticsService.getSessionDurationSplits()
          .catchError((_) => <Map<String, dynamic>>[]),                 // [15]
      AnalyticsService.getPrCandidate()
          .catchError((_) => null as Map<String, dynamic>?),            // [16]
      AnalyticsService.getAvgRepsPerWeek()
          .catchError((_) => <double>[]),                               // [17]
      AnalyticsService.getRecentlyTrainedCategories()
          .catchError((_) => <String>{}),                               // [18]
      TrainingService.getTodayWorkout()
          .catchError((_) => null),                                     // [19]
    ]);

    // ── Unpack results ────────────────────────────────────────────────────
    final todayWellness    = results[0] as Map<String, dynamic>?;
    final energyState      = results[1] as EnergyState;
    final profile          = results[2] as Profile?;
    final rpeOffset        = results[3] as double;
    final muscleBalance    = results[4] as Map<String, int>;
    final deloadMetrics    = results[5] as Map<String, dynamic>?;
    final stagnant         = results[6] as List<Map<String, dynamic>>;
    final wellnessCorr     = results[7] as List<Map<String, dynamic>>;
    final recentRpes       = results[8] as List<double?>;
    final consistencyData  = results[9] as Map<String, dynamic>;
    final avgRepsInProgram = results[10] as double;
    final weeklyMuscle     = results[11] as Map<String, int>;
    final daysPerMuscle    = results[12] as Map<String, double>;
    final volumeRampData   = results[13] as Map<String, double>;
    final todSessions      = results[14] as List<Map<String, dynamic>>;
    final durSplits        = results[15] as List<Map<String, dynamic>>;
    final prCandidate      = results[16] as Map<String, dynamic>?;
    final avgRepsPerWeek   = results[17] as List<double>;
    final recentMuscles    = results[18] as Set<String>;

    // ── Phase 2: evaluate all recommendations ─────────────────────────────
    // Original v1 recs (kept for backward compat with existing UI).
    final wellnessRec = evaluateWellness(todayWellness);
    final muscleImbalanceRec = evaluateMuscleBalance(muscleBalance);
    final plateauRec = evaluatePlateau(stagnant);
    final wellnessCorrelationRec = evaluateWellnessCorrelation(wellnessCorr);

    DeloadRec? deloadRec;
    if (deloadMetrics != null) {
      deloadRec = evaluateDeload(
        recentAvgVolume:   (deloadMetrics['recentAvgVolume']   as num).toDouble(),
        baselineAvgVolume: (deloadMetrics['baselineAvgVolume'] as num).toDouble(),
        consecutiveWeeks:  deloadMetrics['consecutiveWeeks']   as int,
      );
    }

    // v2 recs — all pure functions, no DB access.
    final autoregRec     = evaluateAutoregulation(recentRpes);
    final repRangeRec    = evaluateRepRangeDiversification(avgRepsPerWeek);
    final consistencyRec = evaluateConsistency(
      sessionsLast2Weeks: (consistencyData['last2Weeks'] as num?)?.toInt() ?? 0,
      baselineSessionsPer2Weeks: (consistencyData['baseline'] as num?)?.toDouble() ?? 0,
    );
    final goalAlignRec = evaluateGoalAlignment(
      userGoal: profile?.goal,
      avgRepsInProgram: avgRepsInProgram,
    );
    final prReadyRec = evaluatePrReadiness(
      wellness: todayWellness,
      candidate: prCandidate,
    );
    final volumeLandmarkRec = evaluateVolumeLandmarks(weeklyMuscle);
    final exerciseVarRec    = evaluateExerciseVariations(stagnant);
    final freqOptRec        = evaluateFrequencyOptimization(daysPerMuscle);

    VolumeRampRec? volumeRampRec;
    if (volumeRampData.isNotEmpty) {
      volumeRampRec = evaluateVolumeRamp(
        currentWeekVolume: volumeRampData['currentWeekVolume'] ?? 0,
        prior4WeekAvg: volumeRampData['prior4WeekAvg'] ?? 0,
      );
    }

    final todRec          = evaluateTimeOfDay(todSessions);
    final sessionDurRec   = evaluateSessionDuration(durSplits);

    // DOMS: check if today's planned workout hits a recently trained muscle
    DomsRec? domsRec;
    final soreness = (todayWellness?['soreness'] as num?)?.toInt();
    final todayWorkout = results[19] as Workout?;
    if (soreness != null && soreness >= 4 && todayWorkout != null) {
      try {
        final weList =
            await TrainingService.getWorkoutExercisesForToday(todayWorkout.id);
        for (final we in weList) {
          final cat = we.exercise?.category;
          if (cat != null && recentMuscles.contains(cat)) {
            domsRec = evaluateDoms(
              soreness: soreness,
              plannedMuscle: cat,
              plannedMuscleRecentlyWorked: true,
            );
            break;
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[UserState] DOMS check error: $e');
      }
    }

    // ── Phase 3: score & rank ─────────────────────────────────────────────
    final scored = <ScoredRec>[];

    void add(String id, String title, String message, double priority,
        RecContext ctx, [RecSeverity? severity]) {
      scored.add(ScoredRec(
        id: id, title: title, message: message,
        priority: priority, context: ctx, severity: severity,
      ));
    }

    // Original v1 recs → scored
    if (wellnessRec != null) {
      add('wellness', wellnessRec.title, wellnessRec.message,
          wellnessRec.severity == RecSeverity.critical ? 1.0 : 0.75,
          RecContext.always, wellnessRec.severity);
    }
    if (muscleImbalanceRec != null) {
      add('muscle_imbalance', 'Дисбаланс мышц',
          muscleImbalanceRec.message, 0.50, RecContext.program);
    }
    if (deloadRec != null) {
      final deloadPriority = deloadRec.overloadPct > 30 ? 0.90 : 0.70;
      final deloadSev = deloadRec.overloadPct > 30
          ? RecSeverity.critical : RecSeverity.warning;
      add('deload', 'Пора разгрузиться', deloadRec.message,
          deloadPriority, RecContext.always, deloadSev);
    }
    if (plateauRec != null) {
      add('plateau', 'Плато', plateauRec.message, 0.55, RecContext.program);
    }
    if (wellnessCorrelationRec != null) {
      add('wellness_correlation', 'Сон и результат',
          wellnessCorrelationRec.message, 0.40, RecContext.restDay);
    }

    // v2 recs → scored
    if (autoregRec != null) {
      final p = autoregRec.direction == AutoregDirection.decrease ? 0.85 : 0.60;
      add('autoregulation', 'Авторегуляция нагрузки',
          autoregRec.message, p, RecContext.preWorkout);
    }
    if (repRangeRec != null) {
      add('rep_range', 'Смена диапазона повторов',
          repRangeRec.message, 0.45, RecContext.program);
    }
    if (consistencyRec != null) {
      add('consistency', 'Частота упала',
          consistencyRec.message, 0.65, RecContext.restDay,
          RecSeverity.warning);
    }
    if (goalAlignRec != null) {
      add('goal_alignment', 'Цель и программа',
          goalAlignRec.message, 0.50, RecContext.program);
    }
    if (prReadyRec != null) {
      add('pr_readiness', 'Готов к рекорду!',
          prReadyRec.message, 0.80, RecContext.preWorkout);
    }
    if (volumeLandmarkRec != null) {
      final p = volumeLandmarkRec.zone == VolumeZone.aboveMrv ? 0.75 : 0.55;
      add('volume_landmark', 'Объём тренировок',
          volumeLandmarkRec.message, p, RecContext.program,
          volumeLandmarkRec.zone == VolumeZone.aboveMrv
              ? RecSeverity.warning : RecSeverity.info);
    }
    if (exerciseVarRec != null) {
      add('exercise_variation', 'Замена упражнения',
          exerciseVarRec.message, 0.50, RecContext.program);
    }
    if (freqOptRec != null) {
      add('frequency', 'Частота по группе',
          freqOptRec.message, 0.45, RecContext.program);
    }
    if (volumeRampRec != null) {
      final p = volumeRampRec.severity == VolumeRampSeverity.danger ? 0.90 : 0.65;
      add('volume_ramp', 'Скачок объёма',
          volumeRampRec.message, p, RecContext.postWorkout,
          volumeRampRec.severity == VolumeRampSeverity.danger
              ? RecSeverity.critical : RecSeverity.warning);
    }
    if (todRec != null) {
      add('time_of_day', 'Лучшее время',
          todRec.message, 0.35, RecContext.restDay);
    }
    if (domsRec != null) {
      add('doms', 'Крепатура',
          domsRec.message, 0.70, RecContext.preWorkout,
          RecSeverity.warning);
    }
    if (sessionDurRec != null) {
      add('session_duration', 'Длительность тренировок',
          sessionDurRec.message, 0.45, RecContext.postWorkout);
    }

    // Sort by priority descending
    scored.sort((a, b) => b.priority.compareTo(a.priority));

    // Subjective-energy ceiling on the displayed reserve. computeEnergyStart
    // already nudges recovery via wellnessMod, but with high physical reserve
    // (e.g. 95) and low reported energy (3/10) the headline label still ends
    // up "Хорошо 79%" — which contradicts the "Энергия низкая" warning
    // banner right below. Cap the displayed reserve at the user's reported
    // bucket so the two read-outs agree. Only triggers when subjective ≤ 4;
    // higher subjective never restricts the physical model.
    final subjective = (todayWellness?['energy'] as num?)?.toInt();
    EnergyState shownEnergy = energyState;
    if (subjective != null && subjective <= 4) {
      // Map subjective bucket → ceiling: 1→16, 2→27, 3→38, 4→49.
      final ceiling = (subjective * 11 + 5).toDouble();
      if (energyState.reserve > ceiling) {
        shownEnergy = EnergyState(reserve: ceiling);
      }
    }

    return UserState(
      energyState:             shownEnergy,
      wellnessRec:             wellnessRec,
      todayWellness:           todayWellness,
      userGoal:                profile?.goal,
      rpeCalibrationOffset:    rpeOffset,
      muscleImbalanceRec:      muscleImbalanceRec,
      deloadRec:               deloadRec,
      plateauRec:              plateauRec,
      wellnessCorrelationRec:  wellnessCorrelationRec,
      scoredRecs:              scored,
    );
  }
}
