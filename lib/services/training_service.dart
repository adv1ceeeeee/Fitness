import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/training_session.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/services/auth_service.dart';

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

    final today = DateTime.now().toIso8601String().split('T')[0];

    var res = await _client
        .from('training_sessions')
        .select()
        .eq('user_id', userId)
        .eq('workout_id', workoutId)
        .eq('date', today)
        .maybeSingle();

    if (res == null) {
      final session = await createSession(workoutId);
      return session;
    }

    return TrainingSession.fromJson(res);
  }

  static Future<void> completeSession(String sessionId) async {
    await _client
        .from('training_sessions')
        .update({'completed': true})
        .eq('id', sessionId);
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
        .select('id, workout_id, date, completed')
        .eq('user_id', userId)
        .gte('date', fromStr)
        .lte('date', toStr)
        .order('date');

    return (res as List)
        .map((e) => TrainingSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveSet(
    String sessionId,
    String workoutExerciseId,
    int setNumber, {
    double? weight,
    int? reps,
    int? rpe,
  }) async {
    await _client.from('sets').insert({
      'training_session_id': sessionId,
      'workout_exercise_id': workoutExerciseId,
      'set_number': setNumber,
      'weight': weight,
      'reps': reps,
      'rpe': rpe,
      'completed': true,
    });
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
  }) async {
    await _client.from('sets').update({
      'weight': weight,
      'reps': reps,
      'rpe': rpe,
    }).eq('id', setId);
  }

  /// Find the first incomplete (not completed) session for today.
  /// Returns null if none found. Used for session recovery on app restart.
  static Future<Map<String, dynamic>?> getOpenSession() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    final today = DateTime.now().toIso8601String().split('T')[0];

    return await _client
        .from('training_sessions')
        .select('id, workout_id, created_at, workouts(name)')
        .eq('user_id', userId)
        .eq('date', today)
        .eq('completed', false)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
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
}
