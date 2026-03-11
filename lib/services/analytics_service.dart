import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/auth_service.dart';

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

    final res = await _client
        .from('training_sessions')
        .select()
        .eq('user_id', userId)
        .eq('completed', true);

    return (res as List).length;
  }

  static Future<int> getBestStreak() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;

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

  static Future<int> getWorkoutsThisWeek() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;

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
        .not('weight', 'is', null);

    final weIds = (setsRes as List)
        .map((e) => e['workout_exercise_id'] as String)
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
        .eq('completed', true);

    final sets = (allSets as List).cast<Map<String, dynamic>>();
    if (sets.isEmpty) return null;

    // Exercise names for the workout_exercise IDs in these sets
    final weIds =
        sets.map((s) => s['workout_exercise_id'] as String).toSet().toList();

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
      final weId = s['workout_exercise_id'] as String;
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

    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startStr = startOfWeek.toIso8601String().split('T')[0];

    final sessionsRes = await _client
        .from('training_sessions')
        .select('id')
        .eq('user_id', userId)
        .gte('date', startStr);

    final sessionIds = (sessionsRes as List).map((e) => e['id'] as String).toList();
    if (sessionIds.isEmpty) return 0;

    final setsRes = await _client
        .from('sets')
        .select('weight, reps')
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true);

    double volume = 0;
    for (final s in setsRes as List) {
      final w = (s['weight'] as num?)?.toDouble() ?? 0;
      final r = (s['reps'] as int?) ?? 0;
      volume += w * r;
    }
    return volume;
  }

  /// Returns the all-time personal best (max weight) per exercise.
  /// Result: list of {exerciseName, exerciseId, weightKg, date}.
  static Future<List<Map<String, dynamic>>> getPersonalRecords() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

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
        .not('weight', 'is', null);

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
      final weId = set['workout_exercise_id'] as String;
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
}
