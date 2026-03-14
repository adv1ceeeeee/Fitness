import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/training_session.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/offline_queue_service.dart';
import 'package:sportwai/utils/retry.dart';

class TrainingService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Получить тренировку на сегодня для пользователя
  static Future<Workout?> getTodayWorkout() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    final weekday = DateTime.now().weekday;
    // Dart: 1=Mon, 7=Sun. Our days: 0=Mon, 6=Sun
    final dayIndex = weekday - 1;

    final res = await _client
        .from('workouts')
        .select()
        .eq('user_id', userId)
        .eq('is_standard', false);

    final list = res as List;
    for (final row in list) {
      final days = row['days'] as List<dynamic>?;
      if (days != null &&
          days.any((d) => (d as num).toInt() == dayIndex)) {
        return Workout.fromJson(row as Map<String, dynamic>);
      }
    }
    return null;
  }

  static Future<List<WorkoutExercise>> getWorkoutExercisesForToday(
      String workoutId) async {
    final res = await _client
        .from('workout_exercises')
        .select('*, exercises(*)')
        .eq('workout_id', workoutId)
        .order('order');

    return (res as List)
        .map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Создать сессию тренировки
  static Future<TrainingSession> createSession(String workoutId) async {
    final userId = AuthService.currentUser!.id;
    final today = DateTime.now().toIso8601String().split('T')[0];

    final res = await _client.from('training_sessions').insert({
      'user_id': userId,
      'workout_id': workoutId,
      'date': today,
      'completed': false,
    }).select().single();

    return TrainingSession.fromJson(res);
  }

  /// Получить или создать сессию на сегодня
  static Future<TrainingSession?> getOrCreateTodaySession(
      String workoutId) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      final res = await _client
          .from('training_sessions')
          .select()
          .eq('user_id', userId)
          .eq('workout_id', workoutId)
          .eq('date', today)
          .maybeSingle();

      if (res == null) {
        return await createSession(workoutId);
      }
      return TrainingSession.fromJson(res);
    } catch (e) {
      debugPrint('[TrainingService.getOrCreateTodaySession] error: $e');
      return null;
    }
  }

  static Future<void> completeSession(
    String sessionId, {
    int? durationSeconds,
    String? notes,
  }) async {
    await _client.from('training_sessions').update({
      'completed': true,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      'notes': notes,
    }).eq('id', sessionId);
  }

  /// Mark a planned session as skipped with a reason.
  /// Sets notes to 'skipped:<reason>' and keeps completed=false.
  static Future<void> skipSession(String sessionId, String reason) async {
    await _client.from('training_sessions').update({
      'notes': 'skipped:$reason',
    }).eq('id', sessionId);
  }

  /// Получить все сессии пользователя в диапазоне дат
  static Future<List<TrainingSession>> getSessionsByDateRange(
    DateTime from,
    DateTime to,
  ) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    final fromStr = from.toIso8601String().split('T')[0];
    final toStr = to.toIso8601String().split('T')[0];

    final res = await _client
        .from('training_sessions')
        .select('id, user_id, workout_id, date, completed, notes, planned_time')
        .eq('user_id', userId)
        .gte('date', fromStr)
        .lte('date', toStr)
        .order('date');

    return (res as List)
        .map((e) => TrainingSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<bool> saveSet(
    String sessionId,
    String workoutExerciseId,
    int setNumber, {
    double? weight,
    int? reps,
    int? rpe,
    int? restSeconds,
    double? kcalEstimated,
    bool isWarmup = false,
  }) async {
    try {
      await retryWithBackoff(() => _client.from('sets').insert({
            'training_session_id': sessionId,
            'workout_exercise_id': workoutExerciseId,
            'set_number': setNumber,
            'weight': weight,
            'reps': reps,
            'rpe': rpe,
            'completed': true,
            'is_warmup': isWarmup,
            if (restSeconds != null) 'rest_seconds': restSeconds,
            if (kcalEstimated != null) 'kcal_estimated': kcalEstimated,
          }));
      return true;
    } catch (e) {
      debugPrint('[TrainingService.saveSet] error: $e — queuing for offline retry');
      await OfflineQueueService.enqueue(
        sessionId: sessionId,
        workoutExerciseId: workoutExerciseId,
        setNumber: setNumber,
        weight: weight,
        reps: reps,
        rpe: rpe,
        restSeconds: restSeconds,
      );
      return false;
    }
  }

  /// Sum kcal_estimated from all sets of a session and persist it.
  /// Call after completeSession to store the aggregated total.
  static Future<void> saveSessionKcal(String sessionId) async {
    try {
      final rows = await _client
          .from('sets')
          .select('kcal_estimated')
          .eq('training_session_id', sessionId)
          .eq('completed', true);

      double total = 0;
      for (final r in rows as List) {
        final k = r['kcal_estimated'];
        if (k != null) total += (k as num).toDouble();
      }
      if (total <= 0) return;

      await _client
          .from('training_sessions')
          .update({'kcal_total': double.parse(total.toStringAsFixed(1))})
          .eq('id', sessionId);
    } catch (e) {
      debugPrint('[TrainingService.saveSessionKcal] error: $e');
    }
  }

  /// Returns all sets for a session joined with exercise name and order.
  static Future<List<Map<String, dynamic>>> getSessionSets(
      String sessionId) async {
    final res = await _client
        .from('sets')
        .select('*, workout_exercises(order, reps_range, sets, exercises(name))')
        .eq('training_session_id', sessionId)
        .order('set_number');
    return (res as List).cast<Map<String, dynamic>>();
  }

  /// Update individual fields of a recorded set.
  static Future<void> updateSet(
    String setId, {
    double? weight,
    int? reps,
    int? rpe,
    bool? isWarmup,
  }) async {
    await _client.from('sets').update({
      'weight': weight,
      'reps': reps,
      'rpe': rpe,
      if (isWarmup != null) 'is_warmup': isWarmup,
    }).eq('id', setId);
  }

  /// Sum volume (weight × reps) for all non-warmup completed sets and persist it.
  static Future<void> saveSessionVolume(String sessionId) async {
    try {
      final rows = await _client
          .from('sets')
          .select('weight, reps')
          .eq('training_session_id', sessionId)
          .eq('completed', true)
          .eq('is_warmup', false);

      double total = 0;
      for (final r in rows as List) {
        final w = (r['weight'] as num?)?.toDouble() ?? 0;
        final rep = (r['reps'] as num?)?.toInt() ?? 0;
        total += w * rep;
      }
      if (total <= 0) return;

      await _client
          .from('training_sessions')
          .update({'volume_kg': double.parse(total.toStringAsFixed(2))})
          .eq('id', sessionId);
    } catch (e) {
      debugPrint('[TrainingService.saveSessionVolume] error: $e');
    }
  }

  /// Schedule (or return existing) a session for a specific date.
  /// If [plannedTime] is given, it is stored as HH:MM in the DB and used
  /// to fire a one-time local notification at that moment.
  static Future<TrainingSession> scheduleSession(
      String workoutId, DateTime date,
      {TimeOfDay? plannedTime}) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final dateStr = date.toIso8601String().split('T')[0];

    // Use select() without explicit column list so it works even if
    // planned_time column (migration 030) hasn't been applied yet.
    final existing = await _client
        .from('training_sessions')
        .select()
        .eq('user_id', userId)
        .eq('workout_id', workoutId)
        .eq('date', dateStr)
        .maybeSingle();

    final ptStr = plannedTime != null
        ? '${plannedTime.hour.toString().padLeft(2, '0')}:${plannedTime.minute.toString().padLeft(2, '0')}'
        : null;

    if (existing != null) {
      if (ptStr != null) {
        try {
          await _client
              .from('training_sessions')
              .update({'planned_time': ptStr})
              .eq('id', existing['id'] as String);
        } catch (_) {} // Column may not exist yet
      }
      return TrainingSession.fromJson(
          {...existing, if (ptStr != null) 'planned_time': ptStr});
    }

    final insertData = <String, dynamic>{
      'user_id': userId,
      'workout_id': workoutId,
      'date': dateStr,
      'completed': false,
      if (ptStr != null) 'planned_time': ptStr,
    };

    Map<String, dynamic> res;
    try {
      res = await _client
          .from('training_sessions')
          .insert(insertData)
          .select()
          .single();
    } catch (_) {
      // If planned_time column doesn't exist, retry without it
      if (ptStr != null) {
        insertData.remove('planned_time');
        res = await _client
            .from('training_sessions')
            .insert(insertData)
            .select()
            .single();
      } else {
        rethrow;
      }
    }

    return TrainingSession.fromJson(res);
  }

  /// Returns all incomplete sessions for today joined with workout name.
  static Future<List<Map<String, dynamic>>> getTodayIncompleteSessions() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    final today = DateTime.now().toIso8601String().split('T')[0];

    final res = await _client
        .from('training_sessions')
        .select('id, workout_id, created_at, workouts(name)')
        .eq('user_id', userId)
        .eq('date', today)
        .eq('completed', false)
        .order('created_at', ascending: true);

    return (res as List).cast<Map<String, dynamic>>();
  }

  /// Find the most recent incomplete session started within the last 24 hours.
  /// Returns null if none found. Used for session recovery on app restart.
  static Future<Map<String, dynamic>?> getOpenSession() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .toIso8601String();

    return await _client
        .from('training_sessions')
        .select('id, workout_id, created_at, workouts(name)')
        .eq('user_id', userId)
        .eq('completed', false)
        .gte('created_at', cutoff)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  /// Delete a session and all its sets.
  static Future<void> deleteSession(String sessionId) async {
    await _client.from('sets').delete().eq('training_session_id', sessionId);
    await _client.from('training_sessions').delete().eq('id', sessionId);
  }

  /// Returns the personal best weight (kg) ever logged for a given exercise,
  /// or null if the exercise has never been tracked with weight.
  static Future<double?> getPersonalBest(String exerciseId) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    // Find all workout_exercise IDs for this exercise
    final weRes = await _client
        .from('workout_exercises')
        .select('id')
        .eq('exercise_id', exerciseId);

    final weIds =
        (weRes as List).map((e) => e['id'] as String).toList();
    if (weIds.isEmpty) return null;

    // Find user's session IDs
    final sessRes = await _client
        .from('training_sessions')
        .select('id')
        .eq('user_id', userId);

    final sessIds =
        (sessRes as List).map((e) => e['id'] as String).toList();
    if (sessIds.isEmpty) return null;

    // Get max weight across all sets
    final setsRes = await _client
        .from('sets')
        .select('weight')
        .inFilter('workout_exercise_id', weIds)
        .inFilter('training_session_id', sessIds)
        .eq('completed', true)
        .not('weight', 'is', null)
        .order('weight', ascending: false)
        .limit(1)
        .maybeSingle();

    if (setsRes == null) return null;
    return (setsRes['weight'] as num?)?.toDouble();
  }

  /// Returns the most recent completed session info per workout_id.
  /// Result: { workoutId → { 'date': String, 'duration_seconds': int? } }
  static Future<Map<String, Map<String, dynamic>>> getLastSessionInfoForWorkouts(
      List<String> workoutIds) async {
    if (workoutIds.isEmpty) return {};
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};

    final rows = await _client
        .from('training_sessions')
        .select('workout_id, date, duration_seconds')
        .eq('user_id', userId)
        .eq('completed', true)
        .inFilter('workout_id', workoutIds)
        .order('date', ascending: false);

    final result = <String, Map<String, dynamic>>{};
    for (final row in rows as List) {
      final wid = row['workout_id'] as String;
      if (!result.containsKey(wid)) {
        result[wid] = {
          'date': row['date'] as String?,
          'duration_seconds': row['duration_seconds'] as int?,
        };
      }
    }
    return result;
  }

  /// Returns the next scheduled workout within 7 days (by workout.days weekday list).
  static Future<Workout?> getNextScheduledWorkout() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;
    try {
      final rows = await _client
          .from('workouts')
          .select('id, name, days, cycle_weeks, is_standard')
          .eq('user_id', userId)
          .not('days', 'eq', '{}');
      final workouts = (rows as List)
          .map((r) => Workout.fromJson(r as Map<String, dynamic>))
          .where((w) => w.days.isNotEmpty)
          .toList();
      if (workouts.isEmpty) return null;
      // Find the soonest upcoming workout day (1-7 days ahead)
      final today = DateTime.now().weekday - 1; // 0=Mon…6=Sun
      for (int offset = 1; offset <= 7; offset++) {
        final targetDay = (today + offset) % 7;
        for (final w in workouts) {
          if (w.days.contains(targetDay)) return w;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns days since the last completed workout (0 = trained today, -1 = never).
  static Future<int> getDaysSinceLastWorkout() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return -1;
    try {
      final rows = await _client
          .from('training_sessions')
          .select('date')
          .eq('user_id', userId)
          .eq('completed', true)
          .order('date', ascending: false)
          .limit(1);
      if ((rows as List).isEmpty) return -1;
      final lastDate = DateTime.parse(rows[0]['date'] as String);
      return DateTime.now().difference(lastDate).inDays;
    } catch (_) {
      return -1;
    }
  }

  /// Returns the nearest upcoming (future, incomplete, non-skipped) session per workout.
  /// Result: { workoutId → { 'date': String 'yyyy-MM-dd' } }
  static Future<Map<String, Map<String, dynamic>>> getUpcomingSessionsForWorkouts(
      List<String> workoutIds) async {
    if (workoutIds.isEmpty) return {};
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};
    final today = DateTime.now().toIso8601String().split('T')[0];
    try {
      final rows = await _client
          .from('training_sessions')
          .select('workout_id, date, notes')
          .eq('user_id', userId)
          .eq('completed', false)
          .inFilter('workout_id', workoutIds)
          .gte('date', today)
          .order('date', ascending: true);

      final result = <String, Map<String, dynamic>>{};
      for (final row in rows as List) {
        final notes = row['notes'] as String?;
        if (notes?.startsWith('skipped:') == true) continue;
        final wid = row['workout_id'] as String;
        if (!result.containsKey(wid)) {
          result[wid] = {'date': row['date'] as String};
        }
      }
      return result;
    } catch (e) {
      debugPrint('[TrainingService.getUpcomingSessionsForWorkouts] error: $e');
      return {};
    }
  }

  /// All completed sessions, newest first, with workout name and duration.
  /// Pass [offset] for pagination (page size = [limit]).
  static Future<List<Map<String, dynamic>>> getCompletedSessions({
    int limit = 20,
    int offset = 0,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    final res = await _client
        .from('training_sessions')
        .select('id, workout_id, date, duration_seconds, notes, kcal_total, volume_kg, workouts(name)')
        .eq('user_id', userId)
        .eq('completed', true)
        .order('date', ascending: false)
        .range(offset, offset + limit - 1);

    return (res as List).cast<Map<String, dynamic>>();
  }
}
