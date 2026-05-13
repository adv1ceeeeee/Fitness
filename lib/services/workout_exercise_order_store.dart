import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/models/workout_exercise.dart';

class WorkoutExerciseOrderStore {
  WorkoutExerciseOrderStore._();

  static const _keyPrefix = 'workout_exercise_order_v1:';

  static String _key(String workoutId) => '$_keyPrefix$workoutId';

  static Future<void> save(
    String workoutId,
    List<WorkoutExercise> exercises,
  ) async {
    final ids = [
      for (final exercise in exercises)
        if (!exercise.id.startsWith('tmp_')) exercise.id,
    ];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(workoutId), ids);
  }

  static Future<List<WorkoutExercise>> apply(
    String workoutId,
    List<WorkoutExercise> exercises,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.getStringList(_key(workoutId));
    if (savedIds == null || savedIds.isEmpty || exercises.length < 2) {
      return _normalizeOrder(exercises);
    }

    final byId = {for (final exercise in exercises) exercise.id: exercise};
    final ordered = <WorkoutExercise>[];
    for (final id in savedIds) {
      final exercise = byId.remove(id);
      if (exercise != null) ordered.add(exercise);
    }

    final rest = byId.values.toList()
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        return a.id.compareTo(b.id);
      });

    return _normalizeOrder([...ordered, ...rest]);
  }

  static List<WorkoutExercise> _normalizeOrder(
      List<WorkoutExercise> exercises) {
    return [
      for (var i = 0; i < exercises.length; i++)
        exercises[i].copyWith(order: i),
    ];
  }
}
