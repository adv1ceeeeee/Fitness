import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/app_cache.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/streak_freeze_service.dart';

/// Compact data about one notable improvement vs the previous session.
typedef WorkoutInsight = ({
  String exerciseName,
  double prevValue,
  double newValue,
  bool isWeight, // true = weight kg, false = total reps
  String sessionDate, // 'yyyy-MM-dd'
});

class AnalyticsService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<int> getTotalWorkouts() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;
    return AppCache.get<int>(
      key: 'total_workouts:$userId',
      ttl: const Duration(minutes: 5),
      fetch: () async {
        final res = await _client
            .from('training_sessions')
            .select()
            .eq('user_id', userId)
            .eq('completed', true);
        return (res as List).length;
      },
      encode: (v) => '$v',
      decode: (s) => s == null ? 0 : (int.tryParse(s) ?? 0),
    );
  }

  /// Invalidates stat caches after a workout is completed.
  static Future<void> invalidateStatsCache() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    await AppCache.invalidatePrefix('total_workouts:$userId');
    await AppCache.invalidatePrefix('best_streak:$userId');
    await AppCache.invalidatePrefix('workouts_week:$userId');
    await AppCache.invalidatePrefix('volume_week:$userId');
  }

  /// Current consecutive workout streak ending today or yesterday.
  /// Automatically applies a streak freeze for a 1-day gap if one is available.
  static Future<int> getCurrentStreak() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;

    final res = await _client
        .from('training_sessions')
        .select('date')
        .eq('user_id', userId)
        .eq('completed', true)
        .order('date', ascending: false);

    final dates = (res as List)
        .map((e) => DateTime.parse(e['date'] as String))
        .toList();

    if (dates.isEmpty) return 0;

    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);

    // Streak must touch today or yesterday (or today covered by freeze) to be current
    final latestNorm = DateTime(dates[0].year, dates[0].month, dates[0].day);
    final lagDays = todayNorm.difference(latestNorm).inDays;
    if (lagDays > 2) return 0;
    if (lagDays == 2) {
      // Today was skipped — try covering with a freeze
      final skipped = todayNorm.subtract(const Duration(days: 1));
      if (!StreakFreezeService.applyIfAvailable(skipped)) return 0;
    }

    int streak = 1;
    bool freezeUsedInChain = false;
    for (var i = 1; i < dates.length; i++) {
      final prev = DateTime(dates[i].year, dates[i].month, dates[i].day);
      final curr = DateTime(dates[i - 1].year, dates[i - 1].month, dates[i - 1].day);
      final diff = curr.difference(prev).inDays;
      if (diff == 1) {
        streak++;
      } else if (diff == 2 && !freezeUsedInChain) {
        // One day gap — try covering with freeze (only once per chain)
        final skipped = prev.add(const Duration(days: 1));
        if (StreakFreezeService.applyIfAvailable(skipped)) {
          freezeUsedInChain = true;
          streak++;
        } else {
          break;
        }
      } else {
        break;
      }
    }
    return streak;
  }

  static Future<int> getBestStreak() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;
    return AppCache.get<int>(
      key: 'best_streak:$userId',
      ttl: const Duration(minutes: 5),
      fetch: () async {
        final res = await _client
            .from('training_sessions')
            .select('date')
            .eq('user_id', userId)
            .eq('completed', true)
            .order('date');
        final dates = (res as List)
            .map((e) => DateTime.parse(e['date'] as String))
            .toList();
        if (dates.isEmpty) return 0;
        int streak = 1;
        int best = 1;
        for (var i = 1; i < dates.length; i++) {
          final diff = dates[i].difference(dates[i - 1]).inDays;
          if (diff == 1) {
            streak++;
            if (streak > best) best = streak;
          } else {
            streak = 1;
          }
        }
        return best;
      },
      encode: (v) => '$v',
      decode: (s) => s == null ? 0 : (int.tryParse(s) ?? 0),
    );
  }

  static Future<Map<String, double>> getExerciseMaxWeight(String exerciseId) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};

    final weRes = await _client
        .from('workout_exercises')
        .select('id')
        .eq('exercise_id', exerciseId);

    final weIds = (weRes as List).map((e) => e['id'] as String).toList();
    if (weIds.isEmpty) return {};

    final sessionsRes = await _client
        .from('training_sessions')
        .select('id, date')
        .eq('user_id', userId);

    final sessionIds = (sessionsRes as List).map((e) => e['id'] as String).toList();
    if (sessionIds.isEmpty) return {};

    final setsRes = await _client
        .from('sets')
        .select('training_session_id, weight')
        .inFilter('workout_exercise_id', weIds)
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .not('weight', 'is', null);

    final dateMap = <String, String>{};
    for (final s in sessionsRes as List) {
      final id = s['id'] as String?;
      final date = s['date'] as String?;
      if (id != null && date != null) dateMap[id] = date;
    }

    final result = <String, double>{};
    for (final set in setsRes as List) {
      final sid = set['training_session_id'] as String?;
      if (sid == null) continue;
      final w = (set['weight'] as num).toDouble();
      final date = dateMap[sid];
      if (date != null) {
        final current = result[date] ?? 0;
        if (w > current) result[date] = w;
      }
    }
    return result;
  }

  /// Returns per-session history for one exercise: max weight, total volume,
  /// total reps, and best set. Sorted ascending by date.
  /// Each entry: { 'date': String, 'maxWeight': double, 'volume': double, 'reps': int }
  static Future<List<Map<String, dynamic>>> getExerciseHistory(
      String exerciseId) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    final weRes = await _client
        .from('workout_exercises')
        .select('id')
        .eq('exercise_id', exerciseId);

    final weIds = (weRes as List).map((e) => e['id'] as String).toList();
    if (weIds.isEmpty) return [];

    final sessRes = await _client
        .from('training_sessions')
        .select('id, date')
        .eq('user_id', userId)
        .eq('completed', true)
        .order('date', ascending: true);

    final sessionIds = (sessRes as List).map((e) => e['id'] as String).toList();
    if (sessionIds.isEmpty) return [];
    final dateMap = {for (final s in sessRes as List) s['id'] as String: s['date'] as String};

    final setsRes = await _client
        .from('sets')
        .select('training_session_id, weight, reps')
        .inFilter('workout_exercise_id', weIds)
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .eq('is_warmup', false);

    // Aggregate per session
    final bySession = <String, Map<String, dynamic>>{};
    for (final set in setsRes as List) {
      final sid = set['training_session_id'] as String?;
      if (sid == null) continue;
      final w = (set['weight'] as num?)?.toDouble() ?? 0.0;
      final r = (set['reps'] as num?)?.toInt() ?? 0;
      final entry = bySession.putIfAbsent(sid, () => {'maxWeight': 0.0, 'volume': 0.0, 'reps': 0, 'oneRepMax': 0.0});
      if (w > (entry['maxWeight'] as double)) entry['maxWeight'] = w;
      entry['volume'] = (entry['volume'] as double) + w * r;
      entry['reps'] = (entry['reps'] as int) + r;
      // Epley 1RM: weight × (1 + reps/30), valid for 1–30 reps
      if (w > 0 && r > 0) {
        final orm = r <= 30 ? w * (1.0 + r / 30.0) : w;
        if (orm > (entry['oneRepMax'] as double)) entry['oneRepMax'] = orm;
      }
    }

    final result = <Map<String, dynamic>>[];
    for (final sid in sessionIds) {
      if (!bySession.containsKey(sid)) continue;
      final agg = bySession[sid]!;
      result.add({
        'date': dateMap[sid]!,
        'maxWeight': agg['maxWeight'] as double,
        'volume': agg['volume'] as double,
        'reps': agg['reps'] as int,
        'oneRepMax': agg['oneRepMax'] as double,
      });
    }
    return result;
  }

  /// Returns categories of exercises trained in the last [hours] hours.
  /// Used to warn about muscle fatigue before starting a new session.
  static Future<Set<String>> getRecentlyTrainedCategories({int hours = 48}) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};

    final cutoff = DateTime.now().subtract(Duration(hours: hours)).toUtc().toIso8601String();

    final setsRes = await _client
        .from('sets')
        .select('workout_exercise_id')
        .eq('completed', true)
        .not('workout_exercise_id', 'is', null)
        .gte('performed_at', cutoff);

    final weIds = (setsRes as List)
        .map((e) => e['workout_exercise_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (weIds.isEmpty) return {};

    // Filter by user's sessions
    final sessRes = await _client
        .from('training_sessions')
        .select('id')
        .eq('user_id', userId)
        .gte('created_at', cutoff);
    final userSessIds = (sessRes as List).map((e) => e['id'] as String).toSet();

    final setsWithSession = await _client
        .from('sets')
        .select('workout_exercise_id, training_session_id')
        .inFilter('workout_exercise_id', weIds)
        .eq('completed', true)
        .gte('performed_at', cutoff);

    final userWeIds = (setsWithSession as List)
        .where((e) => userSessIds.contains(e['training_session_id'] as String))
        .map((e) => e['workout_exercise_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (userWeIds.isEmpty) return {};

    final exRes = await _client
        .from('workout_exercises')
        .select('exercise_id')
        .inFilter('id', userWeIds);
    final exIds = (exRes as List).map((e) => e['exercise_id'] as String).toSet().toList();

    final exercisesRes = await _client
        .from('exercises')
        .select('category')
        .inFilter('id', exIds);

    return (exercisesRes as List)
        .map((e) => e['category'] as String?)
        .whereType<String>()
        .toSet();
  }

  static Future<int> getWorkoutsThisWeek() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;
    return AppCache.get<int>(
      key: 'workouts_week:$userId',
      ttl: const Duration(minutes: 5),
      fetch: () async {
        final startStr = DateTime.now()
            .subtract(const Duration(days: 7))
            .toIso8601String()
            .split('T')[0];
        final res = await _client
            .from('training_sessions')
            .select()
            .eq('user_id', userId)
            .eq('completed', true)
            .gte('date', startStr);
        return (res as List).length;
      },
      encode: (v) => '$v',
      decode: (s) => s == null ? 0 : (int.tryParse(s) ?? 0),
    );
  }

  static Future<int> getWorkoutsThisMonth() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;

    final startStr = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String()
        .split('T')[0];

    final res = await _client
        .from('training_sessions')
        .select()
        .eq('user_id', userId)
        .eq('completed', true)
        .gte('date', startStr);

    return (res as List).length;
  }

  static Future<int> getWorkoutsThisYear() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;

    final startStr = DateTime.now()
        .subtract(const Duration(days: 365))
        .toIso8601String()
        .split('T')[0];

    final res = await _client
        .from('training_sessions')
        .select()
        .eq('user_id', userId)
        .eq('completed', true)
        .gte('date', startStr);

    return (res as List).length;
  }

  /// Returns exercises the user has ever logged a weighted set for.
  /// Each map has 'id' and 'name'.
  static Future<List<Map<String, dynamic>>> getTrackedExercises() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    return AppCache.get<List<Map<String, dynamic>>>(
      key: 'tracked_exercises:$userId',
      ttl: const Duration(minutes: 10),
      fetch: () async {
        final sessRes = await _client
            .from('training_sessions')
            .select('id')
            .eq('user_id', userId);
        final sessIds = (sessRes as List).map((e) => e['id'] as String).toList();
        if (sessIds.isEmpty) return [];

        final setsRes = await _client
            .from('sets')
            .select('workout_exercise_id')
            .inFilter('training_session_id', sessIds)
            .eq('completed', true)
            .not('weight', 'is', null)
            .not('workout_exercise_id', 'is', null);

        final weIds = (setsRes as List)
            .map((e) => e['workout_exercise_id'] as String?)
            .whereType<String>()
            .toSet()
            .toList();
        if (weIds.isEmpty) return [];

        final weRes = await _client
            .from('workout_exercises')
            .select('exercise_id, exercises(id, name)')
            .inFilter('id', weIds);

        final seen = <String>{};
        final result = <Map<String, dynamic>>[];
        for (final we in weRes as List) {
          final ex = we['exercises'] as Map<String, dynamic>?;
          if (ex != null) {
            final id = ex['id'] as String;
            if (seen.add(id)) {
              result.add({'id': id, 'name': ex['name'] as String});
            }
          }
        }
        result.sort((a, b) =>
            (a['name'] as String).compareTo(b['name'] as String));
        return result;
      },
      encode: (v) => jsonEncode(v),
      decode: (s) => s == null
          ? []
          : (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
    );
  }

  /// Returns the most recent completed weighted set for each exercise in the list.
  /// Result map key = exerciseId, value = {weight: double, reps: int, date: String}.
  static Future<Map<String, Map<String, dynamic>>> getLastSetsForExercises(
      List<String> exerciseIds) async {
    if (exerciseIds.isEmpty) return {};
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};

    final weRes = await _client
        .from('workout_exercises')
        .select('id, exercise_id')
        .inFilter('exercise_id', exerciseIds);

    final weToExercise = <String, String>{};
    for (final row in weRes as List) {
      weToExercise[row['id'] as String] = row['exercise_id'] as String;
    }
    if (weToExercise.isEmpty) return {};

    final sessRes = await _client
        .from('training_sessions')
        .select('id, date')
        .eq('user_id', userId)
        .eq('completed', true)
        .order('date', ascending: false)
        .limit(30);

    final sessionIds = (sessRes as List).map((e) => e['id'] as String).toList();
    if (sessionIds.isEmpty) return {};

    final sessionDates = <String, String>{
      for (final s in sessRes as List)
        s['id'] as String: s['date'] as String,
    };

    final setsRes = await _client
        .from('sets')
        .select('workout_exercise_id, weight, reps, training_session_id')
        .inFilter('workout_exercise_id', weToExercise.keys.toList())
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .not('weight', 'is', null);

    final setsBySession = <String, List<Map<String, dynamic>>>{};
    for (final set in setsRes as List) {
      final sessId = set['training_session_id'] as String;
      setsBySession.putIfAbsent(sessId, () => []).add(set as Map<String, dynamic>);
    }

    final result = <String, Map<String, dynamic>>{};
    for (final sessionId in sessionIds) {
      if (result.length == exerciseIds.length) break;
      for (final set in setsBySession[sessionId] ?? []) {
        final weId = set['workout_exercise_id'] as String;
        final exId = weToExercise[weId];
        if (exId == null || result.containsKey(exId)) continue;
        result[exId] = {
          'weight': (set['weight'] as num).toDouble(),
          'reps': (set['reps'] as int?) ?? 0,
          'date': sessionDates[sessionId] ?? '',
        };
      }
    }
    return result;
  }

  /// For each exerciseId, checks whether the last [n] completed sessions all
  /// had every set's reps >= [topReps]. Returns set of exerciseIds that qualify.
  /// Used to show "try +2.5 kg" auto-progress suggestion.
  static Future<Set<String>> getConsecutiveFullRepsExercises(
    List<String> exerciseIds,
    Map<String, int> topRepsPerExercise, {
    int n = 3,
  }) async {
    if (exerciseIds.isEmpty) return {};
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};

    // Workout exercises mapping
    final weRes = await _client
        .from('workout_exercises')
        .select('id, exercise_id')
        .inFilter('exercise_id', exerciseIds);
    final weToExercise = <String, String>{};
    for (final row in weRes as List) {
      weToExercise[row['id'] as String] = row['exercise_id'] as String;
    }
    if (weToExercise.isEmpty) return {};

    // Last n*3 sessions to have enough data
    final sessRes = await _client
        .from('training_sessions')
        .select('id')
        .eq('user_id', userId)
        .eq('completed', true)
        .order('date', ascending: false)
        .limit(n * 3);
    final sessionIds =
        (sessRes as List).map((e) => e['id'] as String).toList();
    if (sessionIds.isEmpty) return {};

    final setsRes = await _client
        .from('sets')
        .select('workout_exercise_id, reps, training_session_id')
        .inFilter('workout_exercise_id', weToExercise.keys.toList())
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .not('workout_exercise_id', 'is', null);

    // Group by exerciseId → sessionId → list of reps
    final byExercise = <String, Map<String, List<int>>>{};
    for (final s in setsRes as List) {
      final weId = s['workout_exercise_id'] as String?;
      if (weId == null) continue;
      final exId = weToExercise[weId];
      if (exId == null) continue;
      final sessId = s['training_session_id'] as String;
      final reps = (s['reps'] as int?) ?? 0;
      byExercise.putIfAbsent(exId, () => {})[sessId] =
          (byExercise[exId]![sessId] ?? [])..add(reps);
    }

    final result = <String>{};
    for (final exId in exerciseIds) {
      final topReps = topRepsPerExercise[exId];
      if (topReps == null) continue;
      final sessMap = byExercise[exId] ?? {};
      // Sessions ordered: sessionIds is already DESC by date
      final orderedSessIds =
          sessionIds.where((id) => sessMap.containsKey(id)).take(n).toList();
      if (orderedSessIds.length < n) continue;
      final allFull = orderedSessIds.every((sid) =>
          (sessMap[sid] ?? []).every((r) => r >= topReps));
      if (allFull) result.add(exId);
    }
    return result;
  }

  /// Compares the last two completed sessions of the same workout and returns
  /// the most notable improvement (weight PR or reps increase), or null if
  /// there is nothing to highlight.
  static Future<WorkoutInsight?> getLastWorkoutInsight() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    // Last 5 completed sessions (enough to find a pair for the same workout)
    final sessRes = await _client
        .from('training_sessions')
        .select('id, workout_id, date')
        .eq('user_id', userId)
        .eq('completed', true)
        .order('date', ascending: false)
        .limit(5);

    final sessions = (sessRes as List).cast<Map<String, dynamic>>();
    if (sessions.length < 2) return null;

    final latest = sessions[0];

    // Find the most recent previous session for the same workout
    Map<String, dynamic>? prev;
    for (int i = 1; i < sessions.length; i++) {
      if (sessions[i]['workout_id'] == latest['workout_id']) {
        prev = sessions[i];
        break;
      }
    }
    if (prev == null) return null;

    final latestId = latest['id'] as String;
    final prevId = prev['id'] as String;

    // Sets for both sessions
    final allSets = await _client
        .from('sets')
        .select('training_session_id, workout_exercise_id, weight, reps')
        .inFilter('training_session_id', [latestId, prevId])
        .eq('completed', true)
        .not('workout_exercise_id', 'is', null);

    final sets = (allSets as List).cast<Map<String, dynamic>>();
    if (sets.isEmpty) return null;

    // Exercise names for the workout_exercise IDs in these sets
    final weIds = sets
        .map((s) => s['workout_exercise_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    final weRes = await _client
        .from('workout_exercises')
        .select('id, exercises(name)')
        .inFilter('id', weIds);

    final exerciseNames = <String, String>{};
    for (final we in weRes as List) {
      final ex = (we as Map)['exercises'] as Map?;
      if (ex != null) exerciseNames[we['id'] as String] = ex['name'] as String;
    }

    // Aggregate per session
    final latestMaxW = <String, double>{};
    final latestReps = <String, int>{};
    final prevMaxW = <String, double>{};
    final prevReps = <String, int>{};

    for (final s in sets) {
      final sid = s['training_session_id'] as String;
      final weId = s['workout_exercise_id'] as String?;
      if (weId == null) continue;
      final w = (s['weight'] as num?)?.toDouble() ?? 0;
      final r = (s['reps'] as num?)?.toInt() ?? 0;

      if (sid == latestId) {
        latestMaxW[weId] = max(latestMaxW[weId] ?? 0, w);
        latestReps[weId] = (latestReps[weId] ?? 0) + r;
      } else if (sid == prevId) {
        prevMaxW[weId] = max(prevMaxW[weId] ?? 0, w);
        prevReps[weId] = (prevReps[weId] ?? 0) + r;
      }
    }

    // Best weight improvement
    String? bestWeId;
    double bestDiff = 0;
    for (final weId in latestMaxW.keys) {
      if (!exerciseNames.containsKey(weId)) continue;
      final lw = latestMaxW[weId] ?? 0;
      final pw = prevMaxW[weId] ?? 0;
      if (lw > 0 && pw > 0 && lw > pw && (lw - pw) > bestDiff) {
        bestDiff = lw - pw;
        bestWeId = weId;
      }
    }
    if (bestWeId != null) {
      return (
        exerciseName: exerciseNames[bestWeId]!,
        prevValue: prevMaxW[bestWeId]!,
        newValue: latestMaxW[bestWeId]!,
        isWeight: true,
        sessionDate: latest['date'] as String,
      );
    }

    // Best reps improvement (only if weight unchanged or exercise has no weight)
    for (final weId in latestReps.keys) {
      if (!exerciseNames.containsKey(weId)) continue;
      final lr = latestReps[weId] ?? 0;
      final pr = prevReps[weId] ?? 0;
      if (lr > pr && pr > 0) {
        return (
          exerciseName: exerciseNames[weId]!,
          prevValue: pr.toDouble(),
          newValue: lr.toDouble(),
          isWeight: false,
          sessionDate: latest['date'] as String,
        );
      }
    }

    return null;
  }

  static Future<double> getVolumeThisWeek() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;
    return AppCache.get<double>(
      key: 'volume_week:$userId',
      ttl: const Duration(minutes: 5),
      fetch: () async {
        final now = DateTime.now();
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final startStr = startOfWeek.toIso8601String().split('T')[0];
        final sessionsRes = await _client
            .from('training_sessions')
            .select('id')
            .eq('user_id', userId)
            .gte('date', startStr);
        final sessionIds =
            (sessionsRes as List).map((e) => e['id'] as String).toList();
        if (sessionIds.isEmpty) return 0.0;
        final setsRes = await _client
            .from('sets')
            .select('weight, reps')
            .inFilter('training_session_id', sessionIds)
            .eq('completed', true)
            .eq('is_warmup', false);
        double volume = 0;
        for (final s in setsRes as List) {
          final w = (s['weight'] as num?)?.toDouble() ?? 0;
          final r = (s['reps'] as int?) ?? 0;
          volume += w * r;
        }
        return volume;
      },
      encode: (v) => '$v',
      decode: (s) => s == null ? 0.0 : (double.tryParse(s) ?? 0.0),
    );
  }

  /// Returns {volumeThisWeek, volumeLastWeek, sessionsThisWeek, sessionsLastWeek}.
  static Future<({double volumeThisWeek, double volumeLastWeek, int sessionsThisWeek, int sessionsLastWeek})>
      getWeekComparison() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) {
      return (volumeThisWeek: 0.0, volumeLastWeek: 0.0, sessionsThisWeek: 0, sessionsLastWeek: 0);
    }

    final record = await AppCache.get<Map<String, dynamic>>(
      key: 'week_comparison:$userId',
      ttl: const Duration(minutes: 5),
      fetch: () async {
        final now = DateTime.now();
        final thisMonday = now.subtract(Duration(days: now.weekday - 1));
        final lastMonday = thisMonday.subtract(const Duration(days: 7));
        final thisMondayStr = thisMonday.toIso8601String().split('T')[0];
        final lastMondayStr = lastMonday.toIso8601String().split('T')[0];

        final sessionsRes = await _client
            .from('training_sessions')
            .select('id, date')
            .eq('user_id', userId)
            .eq('completed', true)
            .gte('date', lastMondayStr);

        final sessions = (sessionsRes as List).cast<Map<String, dynamic>>();
        final thisWeekIds = <String>[];
        final lastWeekIds = <String>[];
        for (final s in sessions) {
          final date = s['date'] as String;
          if (date.compareTo(thisMondayStr) >= 0) {
            thisWeekIds.add(s['id'] as String);
          } else {
            lastWeekIds.add(s['id'] as String);
          }
        }

        final allIds = [...thisWeekIds, ...lastWeekIds];
        double volumeThis = 0;
        double volumeLast = 0;

        if (allIds.isNotEmpty) {
          final setsRes = await _client
              .from('sets')
              .select('training_session_id, weight, reps')
              .inFilter('training_session_id', allIds)
              .eq('completed', true)
              .eq('is_warmup', false);

          for (final s in setsRes as List) {
            final sid = s['training_session_id'] as String;
            final w = (s['weight'] as num?)?.toDouble() ?? 0;
            final r = (s['reps'] as num?)?.toInt() ?? 0;
            if (thisWeekIds.contains(sid)) {
              volumeThis += w * r;
            } else {
              volumeLast += w * r;
            }
          }
        }

        return {
          'volumeThisWeek': volumeThis,
          'volumeLastWeek': volumeLast,
          'sessionsThisWeek': thisWeekIds.length,
          'sessionsLastWeek': lastWeekIds.length,
        };
      },
      encode: (v) => jsonEncode(v),
      decode: (s) => s == null
          ? {'volumeThisWeek': 0.0, 'volumeLastWeek': 0.0, 'sessionsThisWeek': 0, 'sessionsLastWeek': 0}
          : (jsonDecode(s) as Map<String, dynamic>),
    );

    return (
      volumeThisWeek: (record['volumeThisWeek'] as num).toDouble(),
      volumeLastWeek: (record['volumeLastWeek'] as num).toDouble(),
      sessionsThisWeek: (record['sessionsThisWeek'] as num).toInt(),
      sessionsLastWeek: (record['sessionsLastWeek'] as num).toInt(),
    );
  }

  /// Returns average sessions per week per muscle group over the past [weeks] weeks.
  /// Result: Map<category, avgSessionsPerWeek>
  static Future<Map<String, double>> getMuscleGroupFrequency(
      {int weeks = 4}) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};

    return AppCache.get<Map<String, double>>(
      key: 'muscle_freq:$userId',
      ttl: const Duration(minutes: 10),
      fetch: () => _fetchMuscleGroupFrequency(userId, weeks),
      encode: (v) => jsonEncode(v),
      decode: (s) => s == null
          ? {}
          : (jsonDecode(s) as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }

  static Future<Map<String, double>> _fetchMuscleGroupFrequency(
      String userId, int weeks) async {
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: 7 * weeks));
    final startStr = startDate.toIso8601String().split('T')[0];

    final sessionsRes = await _client
        .from('training_sessions')
        .select('id, date')
        .eq('user_id', userId)
        .eq('completed', true)
        .gte('date', startStr);

    if ((sessionsRes as List).isEmpty) return {};

    final sessionMap = <String, String>{
      for (final s in sessionsRes as List) s['id'] as String: s['date'] as String,
    };
    final sessionIds = sessionMap.keys.toList();

    final setsRes = await _client
        .from('sets')
        .select('training_session_id, workout_exercise_id')
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .not('workout_exercise_id', 'is', null);

    final weIds = (setsRes as List)
        .map((e) => e['workout_exercise_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (weIds.isEmpty) return {};

    final weRes = await _client
        .from('workout_exercises')
        .select('id, exercises(category)')
        .inFilter('id', weIds);

    final weCategory = <String, String>{};
    for (final we in weRes as List) {
      final ex = we['exercises'] as Map<String, dynamic>?;
      if (ex != null) {
        weCategory[we['id'] as String] = ex['category'] as String? ?? 'other';
      }
    }

    // For each week, collect distinct sessions per category
    // weekKey (Monday date) -> category -> Set<sessionId>
    final weekCatSessions = <String, Map<String, Set<String>>>{};
    for (final set in setsRes as List) {
      final sid = set['training_session_id'] as String?;
      final weId = set['workout_exercise_id'] as String?;
      if (sid == null || weId == null) continue;
      final cat = weCategory[weId];
      if (cat == null) continue;
      final date = sessionMap[sid];
      if (date == null) continue;
      final d = DateTime.parse(date);
      final monday = d.subtract(Duration(days: d.weekday - 1));
      final weekKey = monday.toIso8601String().split('T')[0];
      weekCatSessions
          .putIfAbsent(weekKey, () => {})
          .putIfAbsent(cat, () => {})
          .add(sid);
    }

    // Average sessions per category across weeks
    final catTotal = <String, int>{};
    for (final weekData in weekCatSessions.values) {
      for (final entry in weekData.entries) {
        catTotal[entry.key] = (catTotal[entry.key] ?? 0) + entry.value.length;
      }
    }

    return catTotal.map((cat, total) => MapEntry(cat, total / weeks));
  }

  /// Returns weekly training volume (kg×reps) for the past [weeks] weeks.
  /// Result: list of {label: 'DD.MM', volume: double}, oldest first.
  /// Returns true if the user has trained 4+ consecutive weeks above their
  /// personal average volume — signal to suggest a deload week.
  /// Requires at least 6 weeks of data (4 recent + 2 baseline).
  static Future<bool> shouldSuggestDeload() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return false;

    final now = DateTime.now();
    final thisMonday = now.subtract(Duration(days: now.weekday - 1));
    // Fetch 8 weeks of sessions
    final earliest = thisMonday.subtract(const Duration(days: 7 * 8));
    final earliestStr = earliest.toIso8601String().split('T')[0];

    final sessRes = await _client
        .from('training_sessions')
        .select('id, date')
        .eq('user_id', userId)
        .gte('date', earliestStr);

    if ((sessRes as List).length < 3) return false;

    final sessionDates = {for (final s in sessRes) s['id'] as String: s['date'] as String};
    final sessionIds = sessionDates.keys.toList();

    final setsRes = await _client
        .from('sets')
        .select('training_session_id, weight, reps')
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .eq('is_warmup', false);

    // Bucket volume by ISO week (Monday)
    final weekVolume = <String, double>{};
    for (final set in setsRes as List) {
      final sid = set['training_session_id'] as String?;
      if (sid == null) continue;
      final dateStr = sessionDates[sid];
      if (dateStr == null) continue;
      final d = DateTime.parse(dateStr);
      final monday = d.subtract(Duration(days: d.weekday - 1));
      final key = monday.toIso8601String().split('T')[0];
      final w = (set['weight'] as num?)?.toDouble() ?? 0;
      final r = (set['reps'] as num?)?.toInt() ?? 0;
      weekVolume[key] = (weekVolume[key] ?? 0) + w * r;
    }

    if (weekVolume.length < 5) return false;

    final sorted = weekVolume.keys.toList()..sort();
    // Exclude current (possibly incomplete) week
    final current = thisMonday.toIso8601String().split('T')[0];
    final complete = sorted.where((k) => k != current).toList();
    if (complete.length < 5) return false;

    // Last 4 complete weeks vs older weeks as baseline
    final recent4 = complete.sublist(complete.length - 4);
    final baseline = complete.sublist(0, complete.length - 4);

    final recentAvg = recent4.fold(0.0, (s, k) => s + (weekVolume[k] ?? 0)) / 4;
    final baselineAvg = baseline.fold(0.0, (s, k) => s + (weekVolume[k] ?? 0)) / baseline.length;

    // Suggest deload if recent avg >= 110% of baseline and all 4 weeks > 0
    return recentAvg >= baselineAvg * 1.1 &&
        recent4.every((k) => (weekVolume[k] ?? 0) > 0);
  }

  static Future<List<Map<String, dynamic>>> getWeeklyVolumeHistory(
      {int weeks = 26}) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    return AppCache.get<List<Map<String, dynamic>>>(
      key: 'weekly_volume:$userId:$weeks',
      ttl: const Duration(minutes: 10),
      fetch: () => _fetchWeeklyVolumeHistory(userId, weeks),
      encode: (v) => jsonEncode(v),
      decode: (s) => s == null
          ? []
          : (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
    );
  }

  static Future<List<Map<String, dynamic>>> _fetchWeeklyVolumeHistory(
      String userId, int weeks) async {
    final now = DateTime.now();
    // Snap to start of current week (Monday)
    final thisMonday =
        now.subtract(Duration(days: now.weekday - 1));
    final earliest = thisMonday.subtract(Duration(days: 7 * (weeks - 1)));
    final earliestStr = earliest.toIso8601String().split('T')[0];

    final sessionsRes = await _client
        .from('training_sessions')
        .select('id, date')
        .eq('user_id', userId)
        .gte('date', earliestStr);

    if ((sessionsRes as List).isEmpty) {
      return List.generate(weeks, (i) {
        final monday = earliest.add(Duration(days: 7 * i));
        return {'label': '${monday.day}.${monday.month.toString().padLeft(2, '0')}', 'volume': 0.0};
      });
    }

    final sessionIds = sessionsRes.map((e) => e['id'] as String).toList();
    final setsRes = await _client
        .from('sets')
        .select('training_session_id, weight, reps')
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .eq('is_warmup', false);

    // Build date -> volume map
    final dateVolume = <String, double>{};
    final sessionDates = <String, String>{};
    for (final s in sessionsRes) {
      sessionDates[s['id'] as String] = s['date'] as String;
    }
    for (final set in setsRes as List) {
      final sid = set['training_session_id'] as String?;
      if (sid == null) continue;
      final date = sessionDates[sid];
      if (date == null) continue;
      final w = (set['weight'] as num?)?.toDouble() ?? 0;
      final r = (set['reps'] as num?)?.toInt() ?? 0;
      dateVolume[date] = (dateVolume[date] ?? 0) + w * r;
    }

    // Group by ISO week start (Monday)
    final weekVolume = <String, double>{};
    dateVolume.forEach((date, vol) {
      final d = DateTime.parse(date);
      final monday = d.subtract(Duration(days: d.weekday - 1));
      final key = monday.toIso8601String().split('T')[0];
      weekVolume[key] = (weekVolume[key] ?? 0) + vol;
    });

    return List.generate(weeks, (i) {
      final monday = earliest.add(Duration(days: 7 * i));
      final key = monday.toIso8601String().split('T')[0];
      final label =
          '${monday.day}.${monday.month.toString().padLeft(2, '0')}';
      return {'label': label, 'volume': weekVolume[key] ?? 0.0, 'week_start': key};
    });
  }

  /// Returns total completed sets per muscle group for the past [days] days.
  /// Result: {category: setCount}, e.g. {'chest': 24, 'back': 18, ...}
  static Future<Map<String, int>> getMuscleGroupBalance(
      {int days = 30}) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};

    return AppCache.get<Map<String, int>>(
      key: 'muscle_balance:$userId',
      ttl: const Duration(minutes: 10),
      fetch: () => _fetchMuscleGroupBalance(userId, days),
      encode: (v) => jsonEncode(v),
      decode: (s) => s == null
          ? {}
          : (jsonDecode(s) as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, (v as num).toInt())),
    );
  }

  static Future<Map<String, int>> _fetchMuscleGroupBalance(
      String userId, int days) async {
    final startStr = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .split('T')[0];

    final sessionsRes = await _client
        .from('training_sessions')
        .select('id')
        .eq('user_id', userId)
        .eq('completed', true)
        .gte('date', startStr);

    final sessionIds =
        (sessionsRes as List).map((e) => e['id'] as String).toList();
    if (sessionIds.isEmpty) return {};

    final setsRes = await _client
        .from('sets')
        .select('workout_exercise_id')
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .not('workout_exercise_id', 'is', null);

    final weIds = (setsRes as List)
        .map((e) => e['workout_exercise_id'] as String?)
        .whereType<String>()
        .toList();
    if (weIds.isEmpty) return {};

    final weRes = await _client
        .from('workout_exercises')
        .select('id, exercises(category)')
        .inFilter('id', weIds);

    // Build weId -> category map
    final weCategory = <String, String>{};
    for (final we in weRes as List) {
      final ex = we['exercises'] as Map<String, dynamic>?;
      if (ex != null) {
        weCategory[we['id'] as String] = ex['category'] as String? ?? 'other';
      }
    }

    final balance = <String, int>{};
    for (final set in setsRes) {
      final weId = set['workout_exercise_id'] as String?;
      if (weId == null) continue;
      final cat = weCategory[weId];
      if (cat != null) {
        balance[cat] = (balance[cat] ?? 0) + 1;
      }
    }
    return balance;
  }

  /// Returns the all-time personal best (max weight) per exercise.
  /// Result: list of {exerciseName, exerciseId, weightKg, date}.
  static Future<List<Map<String, dynamic>>> getPersonalRecords() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];
    return AppCache.get<List<Map<String, dynamic>>>(
      key: 'personal_records:$userId',
      ttl: const Duration(minutes: 15),
      fetch: () => _fetchPersonalRecords(userId),
      encode: (v) => jsonEncode(v),
      decode: (s) => s == null
          ? []
          : (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
    );
  }

  static Future<List<Map<String, dynamic>>> _fetchPersonalRecords(
      String userId) async {
    final sessionsRes = await _client
        .from('training_sessions')
        .select('id')
        .eq('user_id', userId)
        .eq('completed', true);
    final sessionIds =
        (sessionsRes as List).map((e) => e['id'] as String).toList();
    if (sessionIds.isEmpty) return [];

    final setsRes = await _client
        .from('sets')
        .select('workout_exercise_id, weight, training_session_id')
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .not('weight', 'is', null)
        .not('workout_exercise_id', 'is', null);

    // Find max weight per workout_exercise_id
    final maxPerWe = <String, double>{};
    final datePerWe = <String, String>{};
    final sessionDates = <String, String>{};
    final sessionsListRes = await _client
        .from('training_sessions')
        .select('id, date')
        .inFilter('id', sessionIds);
    for (final s in sessionsListRes as List) {
      sessionDates[s['id'] as String] = s['date'] as String;
    }
    for (final set in setsRes as List) {
      final weId = set['workout_exercise_id'] as String?;
      if (weId == null) continue;
      final w = (set['weight'] as num).toDouble();
      final sid = set['training_session_id'] as String;
      if (!maxPerWe.containsKey(weId) || w > maxPerWe[weId]!) {
        maxPerWe[weId] = w;
        datePerWe[weId] = sessionDates[sid] ?? '';
      }
    }
    if (maxPerWe.isEmpty) return [];

    final weRes = await _client
        .from('workout_exercises')
        .select('id, exercises(id, name)')
        .inFilter('id', maxPerWe.keys.toList());

    // Deduplicate by exercise_id — keep the highest weight
    final bestByExercise = <String, Map<String, dynamic>>{};
    for (final we in weRes as List) {
      final ex = we['exercises'] as Map<String, dynamic>?;
      if (ex == null) continue;
      final exerciseId = ex['id'] as String;
      final weId = we['id'] as String;
      final w = maxPerWe[weId] ?? 0;
      if (!bestByExercise.containsKey(exerciseId) ||
          w > (bestByExercise[exerciseId]!['weightKg'] as double)) {
        bestByExercise[exerciseId] = {
          'exerciseId': exerciseId,
          'exerciseName': ex['name'] as String,
          'weightKg': w,
          'date': datePerWe[weId] ?? '',
        };
      }
    }

    final result = bestByExercise.values.toList();
    result.sort((a, b) => (a['exerciseName'] as String)
        .compareTo(b['exerciseName'] as String));
    return result;
  }

  /// Returns all personal record entries for [exerciseId], oldest first.
  /// Each entry: {weight_kg: double, achieved_at: String (ISO date)}.
  static Future<List<Map<String, dynamic>>> getExercisePrHistory(
      String exerciseId) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];
    return AppCache.get<List<Map<String, dynamic>>>(
      key: 'pr_history:$userId:$exerciseId',
      ttl: const Duration(minutes: 15),
      fetch: () async {
        final res = await _client
            .from('personal_records')
            .select('weight_kg, achieved_at')
            .eq('user_id', userId)
            .eq('exercise_id', exerciseId)
            .order('achieved_at', ascending: true);
        return (res as List)
            .map((r) => {
                  'weight_kg': (r['weight_kg'] as num).toDouble(),
                  'achieved_at': (r['achieved_at'] as String).substring(0, 10),
                })
            .toList();
      },
      encode: (v) => jsonEncode(v),
      decode: (s) => s == null
          ? []
          : (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
    );
  }

  /// Returns last [limit] completed sessions with kcal_total, oldest first.
  /// Only sessions that have kcal_total != null are included.
  static Future<List<Map<String, dynamic>>> getCaloriesPerSession({
    int limit = 60,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    return AppCache.get<List<Map<String, dynamic>>>(
      key: 'calories_sessions:$userId:$limit',
      ttl: const Duration(minutes: 10),
      fetch: () async {
        final res = await _client
            .from('training_sessions')
            .select('date, kcal_total')
            .eq('user_id', userId)
            .eq('completed', true)
            .not('kcal_total', 'is', null)
            .order('date', ascending: false)
            .limit(limit);

        return (res as List)
            .cast<Map<String, dynamic>>()
            .reversed
            .toList();
      },
      encode: (v) => jsonEncode(v),
      decode: (s) => s == null
          ? []
          : (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
    );
  }

  /// Community average max weight for an exercise over the last 7 days (across all users).
  /// Returns null if no data or RPC unavailable.
  static Future<double?> getCommunityAvgExerciseWeight(
      String exerciseId) async {
    if (AuthService.currentUser == null) return null;
    try {
      final res = await _client.rpc(
        'get_community_avg_exercise_weight',
        params: {'p_exercise_id': exerciseId},
      );
      if (res == null) return null;
      return (res as num).toDouble();
    } catch (e) {
      return null;
    }
  }

  /// Community average weekly volume (kg × reps) over the last 8 weeks.
  /// Returns null if no data or RPC unavailable.
  static Future<double?> getCommunityAvgWeeklyVolume() async {
    if (AuthService.currentUser == null) return null;
    return AppCache.get<double?>(
      key: 'community_avg_vol',
      ttl: const Duration(minutes: 30),
      fetch: () async {
        try {
          final res = await _client.rpc('get_community_avg_weekly_volume');
          if (res == null) return null;
          return (res as num).toDouble();
        } catch (e) {
          return null;
        }
      },
      encode: (v) => v == null ? null : '$v',
      decode: (s) => s == null ? null : double.tryParse(s),
    );
  }

  /// Average workouts per week across all users who trained in the last 4 weeks.
  /// Minimum 3 active users required — returns null otherwise.
  static Future<double?> getCommunityAvgWorkoutsPerWeek() async {
    if (AuthService.currentUser == null) return null;
    return AppCache.get<double?>(
      key: 'community_avg_freq',
      ttl: const Duration(minutes: 30),
      fetch: () async {
        try {
          final since = DateTime.now()
              .subtract(const Duration(days: 28))
              .toIso8601String()
              .split('T')[0];
          // Count completed sessions per user in last 4 weeks
          final res = await _client
              .from('training_sessions')
              .select('user_id')
              .eq('completed', true)
              .gte('date', since);
          final rows = res as List;
          if (rows.isEmpty) return null;
          final perUser = <String, int>{};
          for (final r in rows) {
            final uid = r['user_id'] as String;
            perUser[uid] = (perUser[uid] ?? 0) + 1;
          }
          if (perUser.length < 3) return null; // not enough users for meaningful avg
          final avgSessions = perUser.values.reduce((a, b) => a + b) / perUser.length;
          return avgSessions / 4; // per week
        } catch (_) {
          return null;
        }
      },
      encode: (v) => v == null ? null : '$v',
      decode: (s) => s == null ? null : double.tryParse(s),
    );
  }

  /// Returns kcal burned per session for a specific exercise.
  /// Result: map of date → kcal (sum of kcal_estimated for all sets of that exercise in that session).
  static Future<Map<String, double>> getCaloriesPerExercise(
      String exerciseId) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};

    // Get workout_exercise IDs for this exercise
    final weRes = await _client
        .from('workout_exercises')
        .select('id')
        .eq('exercise_id', exerciseId);
    final weIds = (weRes as List).map((e) => e['id'] as String).toList();
    if (weIds.isEmpty) return {};

    // Get user's completed sessions with dates
    final sessRes = await _client
        .from('training_sessions')
        .select('id, date')
        .eq('user_id', userId)
        .eq('completed', true)
        .not('date', 'is', null)
        .order('date', ascending: false)
        .limit(30);
    final sessionIds = (sessRes as List).map((e) => e['id'] as String).toList();
    if (sessionIds.isEmpty) return {};
    final sessionDates = <String, String>{
      for (final s in sessRes as List) s['id'] as String: s['date'] as String,
    };

    // Get sets for those exercises in those sessions
    final setsRes = await _client
        .from('sets')
        .select('training_session_id, kcal_estimated')
        .inFilter('workout_exercise_id', weIds)
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .not('kcal_estimated', 'is', null);

    final result = <String, double>{};
    for (final s in setsRes as List) {
      final sid = s['training_session_id'] as String?;
      final kcal = (s['kcal_estimated'] as num?)?.toDouble();
      if (sid == null || kcal == null) continue;
      final date = sessionDates[sid];
      if (date == null) continue;
      result[date] = (result[date] ?? 0.0) + kcal;
    }
    return result;
  }

  /// Returns workout dates + volume for the past [weeks] weeks for the heatmap.
  /// Result: map of normalized date → volume_kg (or 1.0 if no sets data).
  static Future<Map<DateTime, double>> getWorkoutHeatmap({int weeks = 26}) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};

    final rawMap = await AppCache.get<Map<String, dynamic>>(
      key: 'workout_heatmap:$userId',
      ttl: const Duration(minutes: 5),
      fetch: () => _fetchWorkoutHeatmap(userId, weeks),
      encode: (v) => jsonEncode(v),
      decode: (s) => s == null ? {} : (jsonDecode(s) as Map<String, dynamic>),
    );

    return rawMap.map((k, v) =>
        MapEntry(DateTime.parse(k), (v as num).toDouble()));
  }

  static Future<Map<String, dynamic>> _fetchWorkoutHeatmap(
      String userId, int weeks) async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: weeks * 7));
    final fromStr = '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';

    final res = await _client
        .from('training_sessions')
        .select('date, id')
        .eq('user_id', userId)
        .eq('completed', true)
        .gte('date', fromStr);

    if ((res as List).isEmpty) return {};

    final sessionIds = res.map((e) => e['id'] as String).toList();

    // Fetch volume per session
    final setsRes = await _client
        .from('sets')
        .select('training_session_id, weight, reps, is_warmup')
        .inFilter('training_session_id', sessionIds)
        .eq('is_warmup', false);

    final volumeBySession = <String, double>{};
    for (final s in (setsRes as List)) {
      final sid = s['training_session_id'] as String?;
      final w = (s['weight'] as num?)?.toDouble() ?? 0;
      final r = (s['reps'] as num?)?.toInt() ?? 0;
      if (sid == null) continue;
      volumeBySession[sid] = (volumeBySession[sid] ?? 0) + w * r;
    }

    final result = <String, dynamic>{};
    for (final row in res) {
      final date = DateTime.parse(row['date'] as String);
      final norm = DateTime(date.year, date.month, date.day);
      final key = norm.toIso8601String().split('T')[0];
      final vol = volumeBySession[row['id'] as String] ?? 1.0;
      result[key] = (result[key] as double? ?? 0.0) + vol;
    }
    return result;
  }

  /// Compact stats for the weekly summary push notification.
  static Future<({int workouts, double volumeKg, int streak, int prs})>
      getWeeklySummaryData() async {
    final results = await Future.wait([
      getWeekComparison(),
      getCurrentStreak(),
      _getWeeklyPrCount(),
    ]);
    final cmp = results[0] as ({
      double volumeThisWeek,
      double volumeLastWeek,
      int sessionsThisWeek,
      int sessionsLastWeek
    });
    return (
      workouts: cmp.sessionsThisWeek,
      volumeKg: cmp.volumeThisWeek,
      streak: results[1] as int,
      prs: results[2] as int,
    );
  }

  /// Count personal records achieved this week.
  static Future<int> _getWeeklyPrCount() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final mondayStr = '${monday.year}-${monday.month.toString().padLeft(2,'0')}-${monday.day.toString().padLeft(2,'0')}';
    final res = await _client
        .from('personal_records')
        .select('id')
        .eq('user_id', userId)
        .gte('achieved_at', mondayStr);
    return (res as List).length;
  }

  /// Total personal records count for this user (all time).
  static Future<int> getTotalPrCount() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;
    try {
      final res = await _client
          .from('personal_records')
          .select('id')
          .eq('user_id', userId);
      return (res as List).length;
    } catch (e) {
      debugPrint('[AnalyticsService] getTotalPrCount error: $e');
      return 0;
    }
  }

  /// Total weight lifted across all completed sets (weight_kg × reps), all time.
  static Future<double> getTotalVolumeKg() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;
    try {
      // Join via training_sessions to scope to this user
      final res = await _client
          .from('sets')
          .select('weight, reps, training_sessions!inner(user_id)')
          .eq('training_sessions.user_id', userId)
          .eq('completed', true)
          .not('weight', 'is', null)
          .not('reps', 'is', null);
      double total = 0;
      for (final row in res as List) {
        final w = (row['weight'] as num?)?.toDouble() ?? 0;
        final r = (row['reps'] as num?)?.toDouble() ?? 0;
        total += w * r;
      }
      return total;
    } catch (e) {
      debugPrint('[AnalyticsService] getTotalVolumeKg error: $e');
      return 0;
    }
  }

  /// Top [limit] exercises by total volume (weight × reps) in the last 30 days.
  /// Each entry: {name: String, total_volume: double}
  static Future<List<Map<String, dynamic>>> getTopExercisesByVolume(
      {int limit = 5}) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    final startStr = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String()
        .split('T')[0];

    final sessionsRes = await _client
        .from('training_sessions')
        .select('id')
        .eq('user_id', userId)
        .eq('completed', true)
        .gte('date', startStr);

    final sessionIds =
        (sessionsRes as List).map((e) => e['id'] as String).toList();
    if (sessionIds.isEmpty) return [];

    final setsRes = await _client
        .from('sets')
        .select('workout_exercise_id, weight, reps')
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .not('workout_exercise_id', 'is', null)
        .not('weight', 'is', null)
        .not('reps', 'is', null);

    // Aggregate volume per workout_exercise_id
    final volumePerWe = <String, double>{};
    for (final s in setsRes as List) {
      final weId = s['workout_exercise_id'] as String?;
      if (weId == null) continue;
      final w = (s['weight'] as num?)?.toDouble() ?? 0;
      final r = (s['reps'] as num?)?.toInt() ?? 0;
      volumePerWe[weId] = (volumePerWe[weId] ?? 0) + w * r;
    }
    if (volumePerWe.isEmpty) return [];

    // Fetch exercise names
    final weRes = await _client
        .from('workout_exercises')
        .select('id, exercises(id, name)')
        .inFilter('id', volumePerWe.keys.toList());

    // Deduplicate by exercise_id — sum volumes across different workout_exercise rows
    final volumePerExercise = <String, double>{};
    final namePerExercise = <String, String>{};
    for (final we in weRes as List) {
      final ex = we['exercises'] as Map<String, dynamic>?;
      if (ex == null) continue;
      final exId = ex['id'] as String;
      final weId = we['id'] as String;
      final vol = volumePerWe[weId] ?? 0;
      volumePerExercise[exId] = (volumePerExercise[exId] ?? 0) + vol;
      namePerExercise[exId] = ex['name'] as String;
    }

    final result = volumePerExercise.entries
        .map((e) => {'name': namePerExercise[e.key] ?? '', 'total_volume': e.value})
        .toList()
      ..sort((a, b) =>
          (b['total_volume'] as double).compareTo(a['total_volume'] as double));

    return result.take(limit).toList();
  }

  /// Wellness logs for the last [days] days, sorted ascending by date.
  /// Each entry: {date, sleep_hours, energy, stress, sleep_quality, soreness}
  static Future<List<Map<String, dynamic>>> getWellnessHistory(
      {int days = 30}) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    final startStr = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .split('T')[0];

    final res = await _client
        .from('wellness_logs')
        .select('date, sleep_hours, energy, stress, sleep_quality, soreness')
        .eq('user_id', userId)
        .gte('date', startStr)
        .order('date', ascending: true);

    return (res as List).cast<Map<String, dynamic>>();
  }

  /// Session duration history: last [limit] completed sessions with duration > 0.
  /// Returns [{date, duration_minutes}], sorted ascending by date.
  static Future<List<Map<String, dynamic>>> getSessionDurationHistory(
      {int limit = 60}) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];
    return AppCache.get<List<Map<String, dynamic>>>(
      key: 'session_durations:$userId:$limit',
      ttl: const Duration(minutes: 15),
      fetch: () async {
        final res = await _client
            .from('training_sessions')
            .select('date, duration_seconds')
            .eq('user_id', userId)
            .eq('completed', true)
            .not('duration_seconds', 'is', null)
            .gt('duration_seconds', 0)
            .order('date', ascending: false)
            .limit(limit);
        return (res as List)
            .cast<Map<String, dynamic>>()
            .reversed
            .map((s) => {
                  'date': s['date'] as String,
                  'duration_minutes':
                      ((s['duration_seconds'] as num) / 60).roundToDouble(),
                })
            .toList();
      },
      encode: (v) => jsonEncode(v),
      decode: (s) =>
          s == null ? [] : (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
    );
  }

  /// Session RPE history: last [limit] completed sessions with RPE logged.
  /// Returns [{date, rpe}], sorted ascending by date.
  static Future<List<Map<String, dynamic>>> getSessionRpeHistory(
      {int limit = 60}) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];
    return AppCache.get<List<Map<String, dynamic>>>(
      key: 'session_rpe:$userId:$limit',
      ttl: const Duration(minutes: 15),
      fetch: () async {
        final res = await _client
            .from('training_sessions')
            .select('date, session_rpe')
            .eq('user_id', userId)
            .eq('completed', true)
            .not('session_rpe', 'is', null)
            .order('date', ascending: false)
            .limit(limit);
        return (res as List)
            .cast<Map<String, dynamic>>()
            .reversed
            .map((s) => {
                  'date': s['date'] as String,
                  'rpe': (s['session_rpe'] as num).toInt(),
                })
            .toList();
      },
      encode: (v) => jsonEncode(v),
      decode: (s) =>
          s == null ? [] : (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
    );
  }

  /// Exercise breakdown per muscle group for the last 30 days.
  /// Returns { category: [{name, sets}] }, sorted by sets desc (top 5 per group).
  static Future<Map<String, List<Map<String, dynamic>>>> getMuscleGroupExerciseBreakdown() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};
    return AppCache.get<Map<String, List<Map<String, dynamic>>>>(
      key: 'muscle_breakdown:$userId',
      ttl: const Duration(minutes: 30),
      fetch: () async {
        final startStr = DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String()
            .split('T')[0];
        final sessRes = await _client
            .from('training_sessions')
            .select('id')
            .eq('user_id', userId)
            .eq('completed', true)
            .gte('date', startStr);
        final sessionIds =
            (sessRes as List).map((e) => e['id'] as String).toList();
        if (sessionIds.isEmpty) return {};

        final setsRes = await _client
            .from('sets')
            .select('workout_exercise_id')
            .inFilter('training_session_id', sessionIds)
            .eq('completed', true)
            .not('workout_exercise_id', 'is', null);

        final weCount = <String, int>{};
        for (final s in setsRes as List) {
          final id = s['workout_exercise_id'] as String;
          weCount[id] = (weCount[id] ?? 0) + 1;
        }
        if (weCount.isEmpty) return {};

        final weRes = await _client
            .from('workout_exercises')
            .select('id, exercises(name, name_ru, category)')
            .inFilter('id', weCount.keys.toList());

        final catExSets = <String, Map<String, int>>{};
        for (final we in weRes as List) {
          final ex = we['exercises'] as Map<String, dynamic>?;
          if (ex == null) continue;
          final cat = ex['category'] as String? ?? 'other';
          final name = ex['name_ru'] as String? ??
              ex['name'] as String? ?? '—';
          final count = weCount[we['id'] as String] ?? 0;
          catExSets.putIfAbsent(cat, () => {})[name] =
              (catExSets[cat]![name] ?? 0) + count;
        }

        return catExSets.map((cat, exMap) {
          final sorted = exMap.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          return MapEntry(
            cat,
            sorted
                .take(5)
                .map((e) => {'name': e.key, 'sets': e.value})
                .toList(),
          );
        });
      },
      encode: (v) => jsonEncode(v),
      decode: (s) {
        if (s == null) return {};
        final raw = jsonDecode(s) as Map<String, dynamic>;
        return raw.map((k, v) => MapEntry(
              k,
              (v as List).cast<Map<String, dynamic>>(),
            ));
      },
    );
  }

  /// Top exercises by weight progress over the last [weeks] weeks.
  /// Returns up to 5 entries [{name, start_weight, end_weight, pct_change}],
  /// sorted by pct_change descending (improvements only).
  static Future<List<Map<String, dynamic>>> getTopExercisesByProgress(
      {int weeks = 12}) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];
    return AppCache.get<List<Map<String, dynamic>>>(
      key: 'exercise_progress:$userId:$weeks',
      ttl: const Duration(minutes: 30),
      fetch: () async {
        final startStr = DateTime.now()
            .subtract(Duration(days: weeks * 7))
            .toIso8601String()
            .split('T')[0];
        final res = await _client
            .from('personal_records')
            .select('exercise_id, weight_kg, achieved_at, exercises(name, name_ru)')
            .eq('user_id', userId)
            .gte('achieved_at', startStr)
            .order('achieved_at', ascending: true);
        final byExercise = <String, List<double>>{};
        final names = <String, String>{};
        for (final r in res as List) {
          final exId = r['exercise_id'] as String;
          final weight = (r['weight_kg'] as num).toDouble();
          final ex = r['exercises'] as Map<String, dynamic>?;
          if (ex != null) {
            names[exId] = ex['name_ru'] as String? ??
                ex['name'] as String? ??
                exId;
          }
          byExercise.putIfAbsent(exId, () => []).add(weight);
        }
        final result = <Map<String, dynamic>>[];
        for (final entry in byExercise.entries) {
          if (entry.value.length < 2) continue;
          final start = entry.value.first;
          final end = entry.value.last;
          if (start <= 0 || end <= start) continue;
          result.add({
            'name': names[entry.key] ?? entry.key,
            'start_weight': start,
            'end_weight': end,
            'pct_change': (end - start) / start * 100,
          });
        }
        result.sort((a, b) =>
            (b['pct_change'] as double).compareTo(a['pct_change'] as double));
        return result.take(5).toList();
      },
      encode: (v) => jsonEncode(v),
      decode: (s) =>
          s == null ? [] : (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
    );
  }
}
