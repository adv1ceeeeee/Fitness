class SetRecord {
  final String id;
  final String trainingSessionId;
  final String workoutExerciseId;
  final int setNumber;
  final double? weight;
  final int? reps;
  final bool completed;

  SetRecord({
    required this.id,
    required this.trainingSessionId,
    required this.workoutExerciseId,
    required this.setNumber,
    this.weight,
    this.reps,
    this.completed = false,
  });

  factory SetRecord.fromJson(Map<String, dynamic> json) {
    return SetRecord(
      id: json['id'] as String,
      trainingSessionId: json['training_session_id'] as String,
      workoutExerciseId: json['workout_exercise_id'] as String,
      setNumber: json['set_number'] as int,
      weight: (json['weight'] as num?)?.toDouble(),
      reps: json['reps'] as int?,
      completed: json['completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'training_session_id': trainingSessionId,
        'workout_exercise_id': workoutExerciseId,
        'set_number': setNumber,
        'weight': weight,
        'reps': reps,
        'completed': completed,
      };
}
