import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/models/exercise.dart';
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

  static Future<Workout> createWorkout(String name, List<int> days) async {
    final userId = AuthService.currentUser!.id;
    final res = await _client.from('workouts').insert({
      'user_id': userId,
      'name': name,
      'days': days,
      'is_standard': false,
    }).select().single();

    return Workout.fromJson(res as Map<String, dynamic>);
  }

  static Future<void> addExerciseToWorkout(
    String workoutId,
    String exerciseId, {
    int sets = 3,
    String repsRange = '8-12',
    int restSeconds = 90,
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
    return Workout.fromJson(res as Map<String, dynamic>);
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

  static Future<void> removeExerciseFromWorkout(String workoutExerciseId) async {
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
  }) async {
    final updates = <String, dynamic>{};
    if (sets != null) updates['sets'] = sets;
    if (repsRange != null) updates['reps_range'] = repsRange;
    if (restSeconds != null) updates['rest_seconds'] = restSeconds;
    if (updates.isEmpty) return;
    await _client.from('workout_exercises').update(updates).eq('id', id);
  }
}
