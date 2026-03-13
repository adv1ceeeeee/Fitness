import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/services/auth_service.dart';

class WorkoutService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<Workout>> getMyWorkouts() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    final res = await _client
        .from('workouts')
        .select()
        .eq('user_id', userId)
        .eq('is_standard', false)
        .order('updated_at', ascending: false);

    return (res as List)
        .map((e) => Workout.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Workout> createWorkout(
    String name,
    List<int> days, {
    int cycleWeeks = 8,
    String? groupId,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) throw StateError('createWorkout called while not authenticated');
    final res = await _client.from('workouts').insert({
      'user_id': userId,
      'name': name,
      'days': days,
      'is_standard': false,
      'cycle_weeks': cycleWeeks,
      if (groupId != null) 'group_id': groupId,
    }).select().single();

    return Workout.fromJson(res);
  }

  static Future<void> setGroupId(String workoutId, String groupId) async {
    await _client
        .from('workouts')
        .update({'group_id': groupId})
        .eq('id', workoutId);
  }

  /// Creates multiple workouts that form a multi-section program.
  /// All sections share the same group_id (= first workout's id).
  static Future<List<Workout>> createWorkoutGroup(
    List<({String name, List<int> days, int cycleWeeks})> sections,
  ) async {
    if (sections.isEmpty || sections.length > 7) {
      throw ArgumentError('sections must have 1–7 entries, got ${sections.length}');
    }

    // Create first section to get the group ID
    final first = await createWorkout(
      sections.first.name,
      sections.first.days,
      cycleWeeks: sections.first.cycleWeeks,
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
              cycleWeeks: s.cycleWeeks,
              groupId: groupId,
            ),
          ),
    );

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
    });
  }

  static Future<List<WorkoutExercise>> getWorkoutExercises(
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

  static Future<Workout?> getWorkout(String id) async {
    final res =
        await _client.from('workouts').select().eq('id', id).maybeSingle();
    if (res == null) return null;
    return Workout.fromJson(res);
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
  }

  static Future<void> reorderExercises(
      String workoutId, List<String> exerciseIds) async {
    for (var i = 0; i < exerciseIds.length; i++) {
      await _client
          .from('workout_exercises')
          .update({'order': i})
          .eq('id', exerciseIds[i]);
    }
  }

  static Future<void> removeExerciseFromWorkout(
      String workoutExerciseId) async {
    await _client
        .from('workout_exercises')
        .delete()
        .eq('id', workoutExerciseId);
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
    await _client.from('workout_exercises').update(updates).eq('id', id);
  }

  static const _absent = Object();

  /// Replaces the exercise_id of a workout_exercise row (used during session swap).
  static Future<void> updateExerciseInWorkout(
      String workoutExerciseId, String newExerciseId) async {
    await _client
        .from('workout_exercises')
        .update({'exercise_id': newExerciseId})
        .eq('id', workoutExerciseId);
  }

  /// Delete a workout and all its exercises.
  static Future<void> deleteWorkout(String id) async {
    await _client.from('workout_exercises').delete().eq('workout_id', id);
    await _client.from('workouts').delete().eq('id', id);
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
}
