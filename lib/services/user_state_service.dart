/// Unified RecSys state — single source of truth for all recommendations.
///
/// [computeUserState] fetches all inputs once, computes every recommendation
/// from the same snapshot, and caches the result for 30 minutes. This
/// guarantees that all cards on the home screen and workout session screen
/// are always internally consistent (no contradictions between energy level,
/// wellness advice, progression, etc.).
library;

import 'dart:convert';

import 'package:sportwai/models/profile.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/app_cache.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/recsys_service.dart';
import 'package:sportwai/services/wellness_service.dart';

// ─── Data class ───────────────────────────────────────────────────────────────

class UserState {
  /// Energy reserve 0–100 % with today's wellness cap applied.
  /// This is the single authoritative energy value — all cards read from here.
  final EnergyState energyState;

  /// Today's wellness recommendation (null = no concerning indicators).
  /// Derived from the same [todayWellness] snapshot as [energyState].
  final WellnessRec? wellnessRec;

  /// Raw today's wellness_logs row (for inline display / wellness card).
  final Map<String, dynamic>? todayWellness;

  /// User's training goal from profiles.goal (strength / weight_loss / etc.).
  final String? userGoal;

  /// RPE calibration offset: median reported RPE − 7.0, clamped −2..+2.
  /// Used by [evaluateProgression] to adjust thresholds.
  final double rpeCalibrationOffset;

  /// Worst antagonist muscle imbalance over the last 30 days (null = balanced).
  final MuscleImbalanceRec? muscleImbalanceRec;

  /// Deload recommendation when recent load is consistently above baseline (null = OK).
  final DeloadRec? deloadRec;

  /// Plateau recommendation for the most stagnant exercise (null = no plateau).
  final PlateauRec? plateauRec;

  /// Sleep ↔ performance correlation (null = insufficient data).
  final WellnessCorrelationRec? wellnessCorrelationRec;

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
  });

  // ── Serialization for AppCache ─────────────────────────────────────────────
  // Heavy recs (muscle, deload, plateau, correlation) are NOT serialized here
  // because their sub-service calls already have their own AppCache keys. On a
  // cache hit for user_state, the fast fields are restored instantly; the heavy
  // recs are recomputed from their own caches on the next _fetch() call.

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
    };
  }

  factory UserState.fromJson(Map<String, dynamic> json) {
    final wrMap = json['wellnessRec'] as Map<String, dynamic>?;
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
    );
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class UserStateService {
  UserStateService._();

  /// Returns the unified RecSys state for the current user.
  ///
  /// Fast path: returns from AppCache within 30-min TTL.
  /// Slow path: runs all sub-service fetches in parallel, computes every
  /// recommendation deterministically from the same snapshot, caches result.
  ///
  /// Cache is invalidated by:
  ///  • [AnalyticsService.invalidateStatsCache()] — called on workout completion
  ///  • [invalidate()] — call after saving a wellness log
  static Future<UserState> computeUserState() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) {
      return const UserState(energyState: EnergyState(reserve: 100));
    }

    return AppCache.get<UserState>(
      key: 'user_state:$userId',
      ttl: const Duration(minutes: 30),
      fetch: () => _fetch(userId),
      encode: (s) => jsonEncode(s.toJson()),
      decode: (raw) => raw == null
          ? const UserState(energyState: EnergyState(reserve: 100))
          : UserState.fromJson(jsonDecode(raw) as Map<String, dynamic>),
    );
  }

  /// Invalidates the cached UserState (call after saving a wellness log so
  /// the next [computeUserState] picks up the new energy/wellness values).
  static Future<void> invalidate() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    await AppCache.invalidatePrefix('user_state:$userId');
  }

  static Future<UserState> _fetch(String userId) async {
    // Run all sub-service calls in parallel. Each is individually guarded so
    // a single DB error (missing column, network blip) never kills the whole
    // UserState — callers always get a valid object back.
    final results = await Future.wait([
      WellnessService.getTodayLog()
          .catchError((_) => null as Map<String, dynamic>?),        // [0]
      AnalyticsService.getEnergyState()
          .catchError((_) => const EnergyState(reserve: 100)),      // [1]
      ProfileService.getProfile()
          .catchError((_) => null as Profile?),                     // [2]
      AnalyticsService.getRpeCalibrationOffset()
          .catchError((_) => 0.0),                                  // [3]
      AnalyticsService.getMuscleGroupBalance()
          .catchError((_) => <String, int>{}),                      // [4]
      AnalyticsService.getDeloadMetrics()
          .catchError((_) => null as Map<String, dynamic>?),        // [5]
      AnalyticsService.getStagnantExercises()
          .catchError((_) => <Map<String, dynamic>>[]),             // [6]
      AnalyticsService.getWellnessPerformanceCorrelation()
          .catchError((_) => <Map<String, dynamic>>[]),             // [7]
    ]);

    final todayWellness = results[0] as Map<String, dynamic>?;
    final energyState   = results[1] as EnergyState;
    final profile       = results[2] as Profile?;
    final rpeOffset     = results[3] as double;
    final muscleBalance = results[4] as Map<String, int>;
    final deloadMetrics = results[5] as Map<String, dynamic>?;
    final stagnant      = results[6] as List<Map<String, dynamic>>;
    final wellnessCorr  = results[7] as List<Map<String, dynamic>>;

    // All recs computed from the same snapshot — consistency guaranteed.
    final wellnessRec        = evaluateWellness(todayWellness);
    final muscleImbalanceRec = evaluateMuscleBalance(muscleBalance);
    final plateauRec         = evaluatePlateau(stagnant);
    final wellnessCorrelationRec = evaluateWellnessCorrelation(wellnessCorr);

    DeloadRec? deloadRec;
    if (deloadMetrics != null) {
      deloadRec = evaluateDeload(
        recentAvgVolume:   (deloadMetrics['recentAvgVolume']   as num).toDouble(),
        baselineAvgVolume: (deloadMetrics['baselineAvgVolume'] as num).toDouble(),
        consecutiveWeeks:  deloadMetrics['consecutiveWeeks']   as int,
      );
    }

    return UserState(
      energyState:             energyState,
      wellnessRec:             wellnessRec,
      todayWellness:           todayWellness,
      userGoal:                profile?.goal,
      rpeCalibrationOffset:    rpeOffset,
      muscleImbalanceRec:      muscleImbalanceRec,
      deloadRec:               deloadRec,
      plateauRec:              plateauRec,
      wellnessCorrelationRec:  wellnessCorrelationRec,
    );
  }
}
