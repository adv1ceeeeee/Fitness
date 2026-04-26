import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/services/app_cache.dart';
import 'package:sportwai/services/auth_service.dart';

class WorkoutService {
  static SupabaseClient get _client => Supabase.instance.client;

  // ─── Cache helpers ───────────────────────────────────────────────────────
  static const _workoutsTtl = Duration(minutes: 5);
  static const _workoutTtl = Duration(minutes: 5);
  static const _exercisesTtl = Duration(minutes: 5);

  /// Invalidate all workout-related caches for the current user.
  /// Call after any mutation that affects the user's workout list.
  static Future<void> _invalidateWorkoutsList() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    await AppCache.invalidate('workouts:$userId');
  }

  static Future<void> _invalidateWorkout(String id) async {
    await AppCache.invalidate('workout:$id');
  }

  static Future<void> _invalidateWorkoutExercises(String workoutId) async {
    await AppCache.invalidate('workout_exercises:$workoutId');
  }

  static Future<void> _invalidateGroup(String? groupId) async {
    if (groupId == null) return;
    await AppCache.invalidate('workout_group:$groupId');
  }

  // ─── Reads ───────────────────────────────────────────────────────────────

  static Future<List<Workout>> getMyWorkouts() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    return AppCache.get<List<Workout>>(
      key: 'workouts:$userId',
      ttl: _workoutsTtl,
      fetch: () async {
        final res = await _client
            .from('workouts')
            .select()
            .eq('user_id', userId)
            .eq('is_standard', false)
            .isFilter('deleted_at', null)
            .order('updated_at', ascending: false);
        return (res as List)
            .map((e) => Workout.fromJson(e as Map<String, dynamic>))
            .toList();
      },
      encode: (list) => jsonEncode(list.map((w) => w.toJson()).toList()),
      decode: (cached) {
        if (cached == null) return <Workout>[];
        final list = jsonDecode(cached) as List;
        return list
            .map((e) => Workout.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  static Future<Workout> createWorkout(
    String name,
    List<int> days, {
    List<int> restDays = const [],
    int cycleWeeks = 8,
    String? groupId,
    Map<int, String>? dayTimes,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) throw StateError('createWorkout called while not authenticated');
    final res = await _client.from('workouts').insert({
      'user_id': userId,
      'name': name,
      'days': days,
      'rest_days': restDays,
      'is_standard': false,
      'cycle_weeks': cycleWeeks,
      if (groupId != null) 'group_id': groupId,
      if (dayTimes != null && dayTimes.isNotEmpty)
        'day_times': {for (final e in dayTimes.entries) '${e.key}': e.value},
    }).select().single();

    await _invalidateWorkoutsList();
    await _invalidateGroup(groupId);
    return Workout.fromJson(res);
  }

  /// Returns all sections that belong to the same multi-section program,
  /// ordered by the earliest day in each section.
  static Future<List<Workout>> getSectionsByGroupId(String groupId) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];
    return AppCache.get<List<Workout>>(
      key: 'workout_group:$groupId',
      ttl: _workoutsTtl,
      fetch: () async {
        final res = await _client
            .from('workouts')
            .select()
            .eq('user_id', userId)
            .eq('group_id', groupId)
            .isFilter('deleted_at', null);
        final list = (res as List)
            .map((e) => Workout.fromJson(e as Map<String, dynamic>))
            .toList();
        list.sort((a, b) {
          final da = a.days.isEmpty ? 99 : a.days.reduce((x, y) => x < y ? x : y);
          final db = b.days.isEmpty ? 99 : b.days.reduce((x, y) => x < y ? x : y);
          return da.compareTo(db);
        });
        return list;
      },
      encode: (list) => jsonEncode(list.map((w) => w.toJson()).toList()),
      decode: (cached) {
        if (cached == null) return <Workout>[];
        final list = jsonDecode(cached) as List;
        return list
            .map((e) => Workout.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  static Future<void> setGroupId(String workoutId, String groupId) async {
    await _client
        .from('workouts')
        .update({'group_id': groupId})
        .eq('id', workoutId);
    await _invalidateWorkoutsList();
    await _invalidateWorkout(workoutId);
    await _invalidateGroup(groupId);
  }

  /// Creates multiple workouts that form a multi-section program.
  /// All sections share the same group_id (= first workout's id).
  static Future<List<Workout>> createWorkoutGroup(
    List<({String name, List<int> days, List<int> restDays, int cycleWeeks, Map<int, String> dayTimes})> sections,
  ) async {
    if (sections.isEmpty || sections.length > 7) {
      throw ArgumentError('sections must have 1–7 entries, got ${sections.length}');
    }

    // Create first section to get the group ID
    final first = await createWorkout(
      sections.first.name,
      sections.first.days,
      restDays: sections.first.restDays,
      cycleWeeks: sections.first.cycleWeeks,
      dayTimes: sections.first.dayTimes,
    );

    if (sections.length == 1) return [first];

    // Use first workout's id as group_id for all sections
    final groupId = first.id;
    await _client
        .from('workouts')
        .update({'group_id': groupId})
        .eq('id', first.id);

    final rest = await Future.wait(
      sections.skip(1).map(
            (s) => createWorkout(
              s.name,
              s.days,
              restDays: s.restDays,
              cycleWeeks: s.cycleWeeks,
              groupId: groupId,
              dayTimes: s.dayTimes,
            ),
          ),
    );

    await _invalidateWorkoutsList();
    await _invalidateGroup(groupId);
    return [first, ...rest];
  }

  static Future<void> addExerciseToWorkout(
    String workoutId,
    String exerciseId, {
    int sets = 3,
    String repsRange = '8-12',
    int restSeconds = 90,
    double? targetWeight,
    int? targetRpe,
    int? durationMinutes,
    int? day,
  }) async {
    final maxOrder = await _client
        .from('workout_exercises')
        .select('order')
        .eq('workout_id', workoutId)
        .order('order', ascending: false)
        .limit(1)
        .maybeSingle();

    final nextOrder = (maxOrder?['order'] as int? ?? -1) + 1;

    await _client.from('workout_exercises').insert({
      'workout_id': workoutId,
      'exercise_id': exerciseId,
      'order': nextOrder,
      'sets': sets,
      'reps_range': repsRange,
      'rest_seconds': restSeconds,
      if (targetWeight != null) 'target_weight': targetWeight,
      if (targetRpe != null) 'target_rpe': targetRpe,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (day != null) 'day': day,
    });
    await _invalidateWorkoutExercises(workoutId);
  }

  static Future<List<WorkoutExercise>> getWorkoutExercises(
      String workoutId) async {
    return AppCache.get<List<WorkoutExercise>>(
      key: 'workout_exercises:$workoutId',
      ttl: _exercisesTtl,
      fetch: () async {
        final res = await _client
            .from('workout_exercises')
            .select('*, exercises(*)')
            .eq('workout_id', workoutId)
            .order('order');
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
  }

  static Future<Workout?> getWorkout(String id) async {
    return AppCache.get<Workout?>(
      key: 'workout:$id',
      ttl: _workoutTtl,
      fetch: () async {
        final res = await _client
            .from('workouts')
            .select()
            .eq('id', id)
            .maybeSingle();
        if (res == null) return null;
        return Workout.fromJson(res);
      },
      encode: (w) => w == null ? null : jsonEncode(w.toJson()),
      decode: (cached) {
        if (cached == null) return null;
        return Workout.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      },
    );
  }

  static Future<void> updateWorkout(
    String id, {
    String? name,
    List<int>? days,
    int? cycleWeeks,
    int? warmupMinutes,
    int? cooldownMinutes,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (days != null) updates['days'] = days;
    if (cycleWeeks != null) updates['cycle_weeks'] = cycleWeeks;
    if (warmupMinutes != null) updates['warmup_minutes'] = warmupMinutes;
    if (cooldownMinutes != null) updates['cooldown_minutes'] = cooldownMinutes;
    if (updates.isEmpty) return;
    await _client.from('workouts').update(updates).eq('id', id);
    await _invalidateWorkoutsList();
    await _invalidateWorkout(id);
  }

  static Future<void> reorderExercises(
      String workoutId, List<String> exerciseIds) async {
    // Write the new order to cache up-front so a re-entry to the screen
    // before the DB round-trips finish still sees the new order.
    final cached = await getWorkoutExercises(workoutId);
    final byId = {for (final e in cached) e.id: e};
    final reordered = <WorkoutExercise>[
      for (final id in exerciseIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (reordered.length == exerciseIds.length) {
      await AppCache.set<List<WorkoutExercise>>(
        key: 'workout_exercises:$workoutId',
        value: reordered,
        encode: (list) => jsonEncode(list.map((w) => w.toJson()).toList()),
      );
    }

    // Apply DB updates in parallel — N round-trips, but concurrent.
    await Future.wait([
      for (var i = 0; i < exerciseIds.length; i++)
        _client
            .from('workout_exercises')
            .update({'order': i})
            .eq('id', exerciseIds[i]),
    ]);
    await _invalidateWorkoutExercises(workoutId);
  }

  static Future<void> removeExerciseFromWorkout(
      String workoutExerciseId) async {
    // Fetch the workout_id first so we can invalidate the right cache.
    final row = await _client
        .from('workout_exercises')
        .select('workout_id')
        .eq('id', workoutExerciseId)
        .maybeSingle();
    await _client
        .from('workout_exercises')
        .delete()
        .eq('id', workoutExerciseId);
    final workoutId = row?['workout_id'] as String?;
    if (workoutId != null) await _invalidateWorkoutExercises(workoutId);
  }

  static Future<void> updateWorkoutExercise(
    String id, {
    int? sets,
    String? repsRange,
    int? restSeconds,
    double? targetWeight,
    int? targetRpe,
    int? durationMinutes,
    // Pass a boxed int? to explicitly set superset_group (null clears it).
    // Use [_Absent] sentinel to skip the field entirely.
    Object? supersetGroup = _absent,
    Object? isDropSet = _absent,
  }) async {
    final updates = <String, dynamic>{};
    if (sets != null) updates['sets'] = sets;
    if (repsRange != null) updates['reps_range'] = repsRange;
    if (restSeconds != null) updates['rest_seconds'] = restSeconds;
    updates['target_weight'] = targetWeight;
    updates['target_rpe'] = targetRpe;
    updates['duration_minutes'] = durationMinutes;
    if (supersetGroup != _absent) updates['superset_group'] = supersetGroup;
    if (isDropSet != _absent) updates['is_drop_set'] = isDropSet;
    final res = await _client
        .from('workout_exercises')
        .update(updates)
        .eq('id', id)
        .select('workout_id')
        .maybeSingle();
    final workoutId = res?['workout_id'] as String?;
    if (workoutId != null) await _invalidateWorkoutExercises(workoutId);
  }

  static const _absent = Object();

  /// Replaces the exercise_id of a workout_exercise row (used during session swap).
  static Future<void> updateExerciseInWorkout(
      String workoutExerciseId, String newExerciseId) async {
    final res = await _client
        .from('workout_exercises')
        .update({'exercise_id': newExerciseId})
        .eq('id', workoutExerciseId)
        .select('workout_id')
        .maybeSingle();
    final workoutId = res?['workout_id'] as String?;
    if (workoutId != null) await _invalidateWorkoutExercises(workoutId);
  }

  /// Soft-delete a workout (sets deleted_at, hidden from the app but recoverable).
  /// workout_exercises remain intact; historical sets are never touched.
  static Future<void> deleteWorkout(String id) async {
    await _client
        .from('workouts')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    await _invalidateWorkoutsList();
    await _invalidateWorkout(id);
    await _invalidateWorkoutExercises(id);
  }

  /// Creates a copy of a workout with all its exercises.
  /// The new workout gets name "Копия: <original>" and same days/settings.
  static Future<Workout> duplicateWorkout(String id) async {
    final original = await getWorkout(id);
    if (original == null) throw StateError('Workout $id not found');

    final copy = await createWorkout(
      'Копия: ${original.name}',
      original.days,
      cycleWeeks: original.cycleWeeks,
    );

    final exercises = await getWorkoutExercises(id);
    for (final we in exercises) {
      await addExerciseToWorkout(
        copy.id,
        we.exerciseId,
        sets: we.sets,
        repsRange: we.repsRange,
        restSeconds: we.restSeconds,
        targetWeight: we.targetWeight,
        durationMinutes: we.durationMinutes,
      );
    }
    return copy;
  }

  /// Clear all workout-related caches for the current user.
  /// Called on logout to prevent data leaking between accounts.
  static Future<void> clearAllCaches() async {
    await AppCache.invalidatePrefix('workouts:');
    await AppCache.invalidatePrefix('workout:');
    await AppCache.invalidatePrefix('workout_exercises:');
    await AppCache.invalidatePrefix('workout_group:');
  }
}
