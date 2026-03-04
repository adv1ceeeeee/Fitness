import 'exercise.dart';

class WorkoutExercise {
  final String id;
  final String workoutId;
  final String exerciseId;
  final int order;
  final int sets;
  final String repsRange;
  final int restSeconds;
  final double? targetWeight;
  final int? targetRpe;
  Exercise? exercise;

  WorkoutExercise({
    required this.id,
    required this.workoutId,
    required this.exerciseId,
    required this.order,
    required this.sets,
    required this.repsRange,
    required this.restSeconds,
    this.targetWeight,
    this.targetRpe,
    this.exercise,
  });

  factory WorkoutExercise.fromJson(Map<String, dynamic> json) {
    return WorkoutExercise(
      id: json['id'] as String,
      workoutId: json['workout_id'] as String,
      exerciseId: json['exercise_id'] as String,
      order: json['order'] as int,
      sets: json['sets'] as int,
      repsRange: json['reps_range'] as String? ?? '8-12',
      restSeconds: json['rest_seconds'] as int? ?? 90,
      targetWeight: (json['target_weight'] as num?)?.toDouble(),
      targetRpe: json['target_rpe'] as int?,
      exercise: json['exercises'] != null
          ? Exercise.fromJson(json['exercises'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'workout_id': workoutId,
        'exercise_id': exerciseId,
        'order': order,
        'sets': sets,
        'reps_range': repsRange,
        'rest_seconds': restSeconds,
        'target_weight': targetWeight,
        'target_rpe': targetRpe,
      };
}
