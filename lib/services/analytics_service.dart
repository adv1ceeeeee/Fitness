import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/auth_service.dart';

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

    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startStr = startOfWeek.toIso8601String().split('T')[0];

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
}
