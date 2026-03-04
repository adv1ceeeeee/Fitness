import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/training_session.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/models/set_record.dart';
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
}
