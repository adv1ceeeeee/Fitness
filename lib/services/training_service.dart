import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/training_session.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/app_cache.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/offline_queue_service.dart';
import 'package:sportwai/services/workout_exercise_order_store.dart';
import 'package:sportwai/utils/retry.dart';

class TrainingService {
  static SupabaseClient get _client => Supabase.instance.client;

  // ─── Cache helpers ──────────────────────────────────────────────────────
  // Short TTLs: session data changes more often than workouts.
  static const _shortTtl = Duration(minutes: 2);
  static const _mediumTtl = Duration(minutes: 5);
  static const _networkTimeout = Duration(seconds: 10);
  static const _workoutExerciseSelect = '''
*, exercises(id,name,name_ru,category,image_url,is_standard,user_id,gif_url)
''';
  static const _workoutExerciseCachePrefix = 'workout_exercises_v2';
  static final Map<String, Future<List<WorkoutExercise>>>
      _workoutExercisesInFlight = {};

  static String _workoutExerciseCacheKey(String workoutId, {int? dayIndex}) =>
      dayIndex == null
          ? '$_workoutExerciseCachePrefix:$workoutId'
          : '$_workoutExerciseCachePrefix:$workoutId:day:$dayIndex';

  static int _appDayIndex(DateTime date) => date.weekday - 1;

  /// Invalidate every cache entry related to training sessions for a user.
  /// Called after any session mutation (create, complete, skip, delete).
  static Future<void> _invalidateSessionCaches() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    await Future.wait([
      AppCache.invalidate('today_workout:$userId'),
      AppCache.invalidate('next_scheduled:$userId'),
      AppCache.invalidate('days_since_last:$userId'),
      AppCache.invalidate('open_session:$userId'),
      AppCache.invalidatePrefix('sessions_range:$userId'),
      AppCache.invalidatePrefix('last_session_info:$userId'),
      AppCache.invalidatePrefix('upcoming_sessions:$userId'),
    ]);
  }

  /// Clear all training-related caches (used on logout).
  static Future<void> clearAllCaches() async {
    await Future.wait([
      AppCache.invalidatePrefix('today_workout:'),
      AppCache.invalidatePrefix('next_scheduled:'),
      AppCache.invalidatePrefix('days_since_last:'),
      AppCache.invalidatePrefix('open_session:'),
      AppCache.invalidatePrefix('sessions_range:'),
      AppCache.invalidatePrefix('last_session_info:'),
      AppCache.invalidatePrefix('upcoming_sessions:'),
    ]);
  }

  /// Получить тренировку на сегодня для пользователя
  static Future<Workout?> getTodayWorkout() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    return AppCache.get<Workout?>(
      key: 'today_workout:$userId',
      ttl: _shortTtl,
      fetch: () async {
        final weekday = DateTime.now().weekday;
        final dayIndex = weekday - 1; // 0=Mon…6=Sun

        final res = await _client
            .from('workouts')
            .select()
            .eq('user_id', userId)
            .eq('is_standard', false)
            // Without this filter, soft-deleted workouts keep showing up as
            // "сегодня" on Home (deleteWorkout just stamps deleted_at, the
            // row stays in the table).
            .isFilter('deleted_at', null)
            .timeout(_networkTimeout);

        for (final row in res as List) {
          final days = row['days'] as List<dynamic>?;
          if (days != null && days.any((d) => (d as num).toInt() == dayIndex)) {
            return Workout.fromJson(row as Map<String, dynamic>);
          }
        }
        return null;
      },
      encode: (w) => w == null ? null : jsonEncode(w.toJson()),
      decode: (cached) {
        if (cached == null) return null;
        return Workout.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      },
    );
  }

  static Future<List<WorkoutExercise>> getWorkoutExercisesForToday(
    String workoutId, {
    DateTime? date,
  }) async {
    final dayIndex = _appDayIndex(date ?? DateTime.now());
    final inFlightKey = '$workoutId:$dayIndex';
    final inFlight = _workoutExercisesInFlight[inFlightKey];
    if (inFlight != null) return inFlight;

    final future = _fetchWorkoutExercisesForDay(workoutId, dayIndex);
    _workoutExercisesInFlight[inFlightKey] = future;
    future.whenComplete(() => _workoutExercisesInFlight.remove(inFlightKey));
    return future;
  }

  static Future<List<WorkoutExercise>> _fetchWorkoutExercisesForDay(
    String workoutId,
    int dayIndex,
  ) async {
    final exercises = await AppCache.get<List<WorkoutExercise>>(
      key: _workoutExerciseCacheKey(workoutId, dayIndex: dayIndex),
      ttl: _mediumTtl,
      fetch: () async {
        final res = await _client
            .from('workout_exercises')
            .select(_workoutExerciseSelect)
            .eq('workout_id', workoutId)
            .or('day.is.null,day.eq.$dayIndex')
            .order('order')
            .order('created_at')
            .timeout(_networkTimeout);
        return (res as List)
            .map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>))
            .toList();
      },
      encode: (list) => jsonEncode(list.map((w) => w.toJson()).toList()),
      decode: (cached) {
        if (cached == null) return <WorkoutExercise>[];
        final list = jsonDecode(cached) as List;
        return list
            .map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
    return WorkoutExerciseOrderStore.apply(workoutId, exercises);
  }

  /// Создать сессию тренировки
  static Future<TrainingSession> createSession(String workoutId) async {
    final userId = AuthService.currentUser!.id;
    final today = DateTime.now().toIso8601String().split('T')[0];

    int? streakAtStart;
    try {
      streakAtStart = await AnalyticsService.getCurrentStreak()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}

    final res = await _client
        .from('training_sessions')
        .insert({
          'user_id': userId,
          'workout_id': workoutId,
          'date': today,
          'completed': false,
          if (streakAtStart != null) 'streak_at_start': streakAtStart,
        })
        .select()
        .single()
        .timeout(_networkTimeout);

    await _invalidateSessionCaches();
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
          .maybeSingle()
          .timeout(_networkTimeout);

      if (res == null) {
        return await createSession(workoutId);
      }
      return TrainingSession.fromJson(res);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TrainingService.getOrCreateTodaySession] error: $e');
      }
      return null;
    }
  }

  /// Completes a session and persists kcal_total + volume_kg in one transaction.
  /// Uses fn_complete_session RPC — replaces the old completeSession +
  /// saveSessionKcal + saveSessionVolume three-call pattern.
  static Future<void> completeSession(
    String sessionId, {
    int? durationSeconds,
    String? notes,
    int? sessionRpe,
  }) async {
    final params = {
      'p_session_id': sessionId,
      if (durationSeconds != null && durationSeconds >= 0)
        'p_duration_seconds': durationSeconds,
      'p_notes': notes != null && notes.length > 1000
          ? notes.substring(0, 1000)
          : notes,
      if (sessionRpe != null) 'p_session_rpe': sessionRpe.clamp(1, 10),
    };

    try {
      await _client
          .rpc('fn_complete_session', params: params)
          .timeout(_networkTimeout);
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[TrainingService.completeSession] RPC timeout, using fallback: $e');
      }
      await _completeSessionFallback(
        sessionId,
        durationSeconds: durationSeconds,
        notes: notes,
        sessionRpe: sessionRpe,
      );
    }
    await _invalidateSessionCaches();
  }

  static Future<void> _completeSessionFallback(
    String sessionId, {
    int? durationSeconds,
    String? notes,
    int? sessionRpe,
  }) async {
    double volumeKg = 0;
    double kcalTotal = 0;
    try {
      final rows = await _client
          .from('sets')
          .select('weight, reps, kcal_estimated, is_warmup')
          .eq('training_session_id', sessionId)
          .eq('completed', true)
          .timeout(_networkTimeout);

      for (final row in rows as List) {
        final map = row as Map<String, dynamic>;
        kcalTotal += (map['kcal_estimated'] as num?)?.toDouble() ?? 0;
        final isWarmup = map['is_warmup'] as bool? ?? false;
        if (!isWarmup) {
          final weight = (map['weight'] as num?)?.toDouble() ?? 0;
          final reps = (map['reps'] as num?)?.toInt() ?? 0;
          volumeKg += weight * reps;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[TrainingService._completeSessionFallback] totals error: $e');
      }
    }

    final update = <String, dynamic>{
      'completed': true,
      if (durationSeconds != null && durationSeconds >= 0)
        'duration_seconds': durationSeconds,
      'notes': notes != null && notes.length > 1000
          ? notes.substring(0, 1000)
          : notes,
      if (sessionRpe != null) 'session_rpe': sessionRpe.clamp(1, 10),
      if (kcalTotal > 0)
        'kcal_total': double.parse(kcalTotal.toStringAsFixed(1)),
      if (volumeKg > 0) 'volume_kg': double.parse(volumeKg.toStringAsFixed(2)),
    };

    await _client
        .from('training_sessions')
        .update(update)
        .eq('id', sessionId)
        .timeout(_networkTimeout);
  }

  /// Mark a planned session as skipped with a reason.
  /// Sets notes to 'skipped:<reason>' and keeps completed=false.
  static Future<void> skipSession(String sessionId, String reason) async {
    await _client.from('training_sessions').update({
      'notes': 'skipped:$reason',
    }).eq('id', sessionId);
    await _invalidateSessionCaches();
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

    return AppCache.get<List<TrainingSession>>(
      key: 'sessions_range:$userId:$fromStr:$toStr',
      ttl: _shortTtl,
      fetch: () async {
        final res = await _client
            .from('training_sessions')
            .select(
                'id, user_id, workout_id, date, completed, notes, planned_time')
            .eq('user_id', userId)
            .gte('date', fromStr)
            .lte('date', toStr)
            .order('date');
        return (res as List)
            .map((e) => TrainingSession.fromJson(e as Map<String, dynamic>))
            .toList();
      },
      encode: (list) => jsonEncode(list.map((s) => s.toJson()).toList()),
      decode: (cached) {
        if (cached == null) return <TrainingSession>[];
        final list = jsonDecode(cached) as List;
        return list
            .map((e) => TrainingSession.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  static Future<bool> saveSet(
    String sessionId,
    String workoutExerciseId,
    int setNumber, {
    double? weight,
    int? reps,
    int? repsTarget,
    int? rpe,
    int? restSeconds,
    double? kcalEstimated,
    bool isWarmup = false,
    DateTime? startedAt,
    int? durationSeconds,
    double? distanceM,
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
            'performed_at': DateTime.now().toUtc().toIso8601String(),
            if (startedAt != null) 'started_at': startedAt.toIso8601String(),
            if (repsTarget != null) 'reps_target': repsTarget,
            if (restSeconds != null) 'rest_seconds': restSeconds,
            if (kcalEstimated != null) 'kcal_estimated': kcalEstimated,
            if (durationSeconds != null) 'duration_seconds': durationSeconds,
            if (distanceM != null) 'distance_m': distanceM,
          }).timeout(_networkTimeout));
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[TrainingService.saveSet] error: $e — queuing for offline retry');
      }
      await OfflineQueueService.enqueue(
        sessionId: sessionId,
        workoutExerciseId: workoutExerciseId,
        setNumber: setNumber,
        weight: weight,
        reps: reps,
        rpe: rpe,
        restSeconds: restSeconds,
        startedAt: startedAt,
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
          .eq('completed', true)
          .timeout(_networkTimeout);

      double total = 0;
      for (final r in rows as List) {
        final k = r['kcal_estimated'];
        if (k != null) total += (k as num).toDouble();
      }
      if (total <= 0) return;

      await _client
          .from('training_sessions')
          .update({'kcal_total': double.parse(total.toStringAsFixed(1))}).eq(
              'id', sessionId);
    } catch (e) {
      if (kDebugMode) debugPrint('[TrainingService.saveSessionKcal] error: $e');
    }
  }

  /// Returns all sets for a session joined with exercise name and order.
  static Future<List<Map<String, dynamic>>> getSessionSets(
      String sessionId) async {
    final res = await _client
        .from('sets')
        .select(
            '*, workout_exercises(order, reps_range, sets, exercises(name, name_ru, category))')
        .eq('training_session_id', sessionId)
        .order('set_number')
        .timeout(_networkTimeout);
    return (res as List).cast<Map<String, dynamic>>();
  }

  /// Update individual fields of a recorded set.
  static Future<void> updateSet(
    String setId, {
    double? weight,
    int? reps,
    int? rpe,
    bool? isWarmup,
    double? kcalEstimated,
  }) async {
    await _client
        .from('sets')
        .update({
          'weight': weight,
          'reps': reps,
          'rpe': rpe,
          if (isWarmup != null) 'is_warmup': isWarmup,
          if (kcalEstimated != null) 'kcal_estimated': kcalEstimated,
        })
        .eq('id', setId)
        .timeout(_networkTimeout);
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
          .update({'volume_kg': double.parse(total.toStringAsFixed(2))}).eq(
              'id', sessionId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TrainingService.saveSessionVolume] error: $e');
      }
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
          await _client.from('training_sessions').update(
              {'planned_time': ptStr}).eq('id', existing['id'] as String);
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
        .order('created_at', ascending: true)
        .timeout(_networkTimeout);

    return (res as List).cast<Map<String, dynamic>>();
  }

  /// Find the most recent incomplete session started within the last 24 hours.
  /// Returns null if none found. Used for session recovery on app restart.
  /// Cached briefly so the lookup on each app resume is near-instant.
  static Future<Map<String, dynamic>?> getOpenSession() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    return AppCache.get<Map<String, dynamic>?>(
      key: 'open_session:$userId',
      ttl: _shortTtl,
      fetch: () async {
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
            .maybeSingle()
            .timeout(_networkTimeout);
      },
      encode: (v) => v == null ? null : jsonEncode(v),
      decode: (cached) {
        if (cached == null) return null;
        return (jsonDecode(cached) as Map).cast<String, dynamic>();
      },
    );
  }

  /// Delete a session and all its sets atomically via fn_delete_session RPC.
  static Future<void> deleteSession(String sessionId) async {
    await _client.rpc('fn_delete_session', params: {'p_session_id': sessionId});
    await _invalidateSessionCaches();
  }

  /// Returns the personal best weight (kg) for an exercise.
  /// Reads from personal_records (populated by Postgres trigger on sets INSERT).
  static Future<double?> getPersonalBest(String exerciseId) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    final res = await _client
        .from('personal_records')
        .select('weight_kg')
        .eq('user_id', userId)
        .eq('exercise_id', exerciseId)
        .order('weight_kg', ascending: false)
        .limit(1)
        .maybeSingle();

    return (res?['weight_kg'] as num?)?.toDouble();
  }

  /// Returns the best recorded working weight per exercise in one request.
  static Future<Map<String, double>> getPersonalBestsForExercises(
      List<String> exerciseIds) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null || exerciseIds.isEmpty) return {};
    final sortedIds = [...exerciseIds]..sort();

    return AppCache.get<Map<String, double>>(
      key: 'personal_bests:$userId:${sortedIds.join(',')}',
      ttl: const Duration(minutes: 10),
      fetch: () async {
        final res = await _client
            .from('personal_records')
            .select('exercise_id, weight_kg')
            .eq('user_id', userId)
            .inFilter('exercise_id', exerciseIds)
            .timeout(_networkTimeout);
        final result = <String, double>{};
        for (final row in res as List) {
          final map = row as Map<String, dynamic>;
          final exerciseId = map['exercise_id'] as String?;
          final weight = (map['weight_kg'] as num?)?.toDouble();
          if (exerciseId == null || weight == null) continue;
          if (!result.containsKey(exerciseId) || weight > result[exerciseId]!) {
            result[exerciseId] = weight;
          }
        }
        return result;
      },
      encode: (value) => jsonEncode(value),
      decode: (cached) {
        if (cached == null) return <String, double>{};
        return (jsonDecode(cached) as Map<String, dynamic>).map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
        );
      },
    );
  }

  /// Returns the most recent completed session info per workout_id.
  /// Result: { workoutId → { 'date': String, 'duration_seconds': int? } }
  static Future<Map<String, Map<String, dynamic>>>
      getLastSessionInfoForWorkouts(List<String> workoutIds) async {
    if (workoutIds.isEmpty) return {};
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};

    final sortedIds = [...workoutIds]..sort();
    final keyIds = sortedIds.join(',');

    return AppCache.get<Map<String, Map<String, dynamic>>>(
      key: 'last_session_info:$userId:$keyIds',
      ttl: _mediumTtl,
      fetch: () async {
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
      },
      encode: (m) => jsonEncode(m),
      decode: (cached) {
        if (cached == null) return {};
        final raw = jsonDecode(cached) as Map;
        return raw.map((k, v) =>
            MapEntry(k as String, (v as Map).cast<String, dynamic>()));
      },
    );
  }

  /// Returns the next scheduled workout within 7 days (by workout.days weekday list).
  static Future<Workout?> getNextScheduledWorkout() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;
    return AppCache.get<Workout?>(
      key: 'next_scheduled:$userId',
      ttl: _shortTtl,
      fetch: () async {
        try {
          final rows = await _client
              .from('workouts')
              .select('id, name, days, cycle_weeks, is_standard')
              .eq('user_id', userId)
              .isFilter('deleted_at', null)
              .not('days', 'eq', '{}');
          final workouts = (rows as List)
              .map((r) => Workout.fromJson(r as Map<String, dynamic>))
              .where((w) => w.days.isNotEmpty)
              .toList();
          if (workouts.isEmpty) return null;
          final today = DateTime.now().weekday - 1;
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
      },
      encode: (w) => w == null ? null : jsonEncode(w.toJson()),
      decode: (cached) {
        if (cached == null) return null;
        return Workout.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      },
    );
  }

  /// Returns days since the last completed workout (0 = trained today, -1 = never).
  static Future<int> getDaysSinceLastWorkout() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return -1;
    return AppCache.get<int>(
      key: 'days_since_last:$userId',
      ttl: _shortTtl,
      fetch: () async {
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
      },
      encode: (v) => v.toString(),
      decode: (cached) => int.tryParse(cached ?? '') ?? -1,
    );
  }

  /// Returns the nearest upcoming (future, incomplete, non-skipped) session per workout.
  /// Result: { workoutId → { 'date': String 'yyyy-MM-dd', 'session_id': String } }
  static Future<Map<String, Map<String, dynamic>>>
      getUpcomingSessionsForWorkouts(List<String> workoutIds) async {
    if (workoutIds.isEmpty) return {};
    final userId = AuthService.currentUser?.id;
    if (userId == null) return {};

    final sortedIds = [...workoutIds]..sort();
    final keyIds = sortedIds.join(',');

    return AppCache.get<Map<String, Map<String, dynamic>>>(
      key: 'upcoming_sessions:$userId:$keyIds',
      ttl: _shortTtl,
      fetch: () async {
        final today = DateTime.now().toIso8601String().split('T')[0];
        try {
          final rows = await _client
              .from('training_sessions')
              .select('id, workout_id, date, notes')
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
              result[wid] = {
                'date': row['date'] as String,
                'session_id': row['id'] as String,
              };
            }
          }
          return result;
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                '[TrainingService.getUpcomingSessionsForWorkouts] error: $e');
          }
          return {};
        }
      },
      encode: (m) => jsonEncode(m),
      decode: (cached) {
        if (cached == null) return {};
        final raw = jsonDecode(cached) as Map;
        return raw.map((k, v) =>
            MapEntry(k as String, (v as Map).cast<String, dynamic>()));
      },
    );
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
        .select(
            'id, workout_id, date, duration_seconds, notes, kcal_total, volume_kg, workouts(name)')
        .eq('user_id', userId)
        .eq('completed', true)
        .order('date', ascending: false)
        .range(offset, offset + limit - 1);

    return (res as List).cast<Map<String, dynamic>>();
  }

  /// Returns the planned_time of today's uncompleted session, if any.
  /// Returns null when no session is scheduled or planned_time is not set.
  static Future<DateTime?> getTodayPlannedTime() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    try {
      final res = await Supabase.instance.client
          .from('training_sessions')
          .select('planned_time')
          .eq('user_id', userId)
          .eq('date', todayStr)
          .eq('completed', false)
          .not('planned_time', 'is', null)
          .limit(1)
          .maybeSingle();
      if (res == null) return null;
      final ptStr = res['planned_time'] as String?;
      if (ptStr == null) return null;
      // planned_time is stored as HH:MM — combine with today's date
      final parts = ptStr.split(':');
      if (parts.length < 2) return null;
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  /// Returns per-weekday training history for a workout program.
  ///
  /// Result map keys:
  ///   'totalSessions' → int
  ///   'firstDate'     → String? ('yyyy-MM-dd')
  ///   'byDay'         → Map<int, Map> where key is 0-based weekday (0=Mon…6=Sun)
  ///                     each value: {date, rpe, durationSeconds, exercises:[{name,setCount,maxWeight,lastReps}]}
  static Future<Map<String, dynamic>> getWorkoutDayHistory(
      String workoutId) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) {
      return {'totalSessions': 0, 'firstDate': null, 'byDay': <int, Map>{}};
    }

    // 1. Last 60 sessions for total count + first date + per-day grouping
    final sessRes = await _client
        .from('training_sessions')
        .select('id, date, session_rpe, duration_seconds')
        .eq('workout_id', workoutId)
        .eq('user_id', userId)
        .eq('completed', true)
        .order('date', ascending: false)
        .limit(60);

    final sessions = (sessRes as List).cast<Map<String, dynamic>>();
    if (sessions.isEmpty) {
      return {'totalSessions': 0, 'firstDate': null, 'byDay': <int, Map>{}};
    }

    final totalSessions = sessions.length;
    final firstDate = sessions.last['date'] as String?;

    // 2. Keep most recent session per weekday (0=Mon…6=Sun)
    final byDay = <int, Map<String, dynamic>>{};
    for (final s in sessions) {
      final dateStr = s['date'] as String?;
      if (dateStr == null) continue;
      final weekday = DateTime.parse(dateStr).weekday - 1; // 0=Mon…6=Sun
      if (!byDay.containsKey(weekday)) {
        byDay[weekday] = {
          'id': s['id'] as String,
          'date': dateStr,
          'rpe': s['session_rpe'] as int?,
          'durationSeconds': s['duration_seconds'] as int?,
          'exercises': <Map<String, dynamic>>[],
        };
      }
    }

    // 3. Fetch working sets for the selected sessions
    final sessionIds = byDay.values.map((d) => d['id'] as String).toList();
    final setsRes = await _client
        .from('sets')
        .select(
            'training_session_id, workout_exercise_id, weight, reps, set_number')
        .inFilter('training_session_id', sessionIds)
        .eq('completed', true)
        .eq('is_warmup', false)
        .not('reps', 'is', null)
        .not('workout_exercise_id', 'is', null)
        .order('set_number');

    // 4. Resolve workout_exercise_id → exercise display name
    final weIds = (setsRes as List)
        .map((s) => s['workout_exercise_id'] as String)
        .toSet()
        .toList();

    final weNames = <String, String>{};
    if (weIds.isNotEmpty) {
      final weRes = await _client
          .from('workout_exercises')
          .select('id, exercises(name, name_ru)')
          .inFilter('id', weIds);
      for (final row in weRes as List) {
        final ex = row['exercises'] as Map<String, dynamic>?;
        if (ex == null) continue;
        final nameRu = ex['name_ru'] as String?;
        final name = ex['name'] as String? ?? '';
        weNames[row['id'] as String] =
            (nameRu != null && nameRu.isNotEmpty) ? nameRu : name;
      }
    }

    // 5. Aggregate sets per session: {weId → {name, setCount, maxWeight, lastReps}}
    //    Preserve exercise order (by min set_number encountered first).
    final setsBySess = <String, Map<String, Map<String, dynamic>>>{};
    for (final s in setsRes as List) {
      final sessId = s['training_session_id'] as String;
      final weId = s['workout_exercise_id'] as String;
      setsBySess.putIfAbsent(sessId, () => {});
      setsBySess[sessId]!.putIfAbsent(
          weId,
          () => {
                'name': weNames[weId] ?? weId,
                'setCount': 0,
                'maxWeight': 0.0,
                'lastReps': 0,
              });
      final agg = setsBySess[sessId]![weId]!;
      agg['setCount'] = (agg['setCount'] as int) + 1;
      final w = (s['weight'] as num?)?.toDouble() ?? 0.0;
      if (w > (agg['maxWeight'] as double)) {
        agg['maxWeight'] = w;
        agg['lastReps'] = (s['reps'] as num?)?.toInt() ?? 0;
      }
    }

    for (final entry in byDay.entries) {
      final sessId = entry.value['id'] as String;
      entry.value['exercises'] =
          setsBySess[sessId]?.values.toList() ?? <Map<String, dynamic>>[];
    }

    return {
      'totalSessions': totalSessions,
      'firstDate': firstDate,
      'byDay': byDay
    };
  }
}
