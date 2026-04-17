class SetRecord {
  final String id;
  final String trainingSessionId;
  final String workoutExerciseId;
  final int setNumber;
  final double? weight;
  final int? reps;
  final int? rpe;
  final bool completed;
  final bool isWarmup;
  final DateTime? performedAt;
  final int? repsTarget;
  /// Duration in seconds for cardio sets. Null for strength/bodyweight.
  final int? durationSeconds;
  /// Distance in meters for cardio sets. Null for strength/bodyweight.
  final double? distanceM;

  SetRecord({
    required this.id,
    required this.trainingSessionId,
    required this.workoutExerciseId,
    required this.setNumber,
    this.weight,
    this.reps,
    this.rpe,
    this.completed = false,
    this.isWarmup = false,
    this.performedAt,
    this.repsTarget,
    this.durationSeconds,
    this.distanceM,
  });

  factory SetRecord.fromJson(Map<String, dynamic> json) {
    return SetRecord(
      id: json['id'] as String,
      trainingSessionId: json['training_session_id'] as String,
      workoutExerciseId: json['workout_exercise_id'] as String,
      setNumber: json['set_number'] as int,
      weight: (json['weight'] as num?)?.toDouble(),
      reps: json['reps'] as int?,
      rpe: json['rpe'] as int?,
      completed: json['completed'] as bool? ?? false,
      isWarmup: json['is_warmup'] as bool? ?? false,
      performedAt: json['performed_at'] != null
          ? DateTime.tryParse(json['performed_at'] as String)
          : null,
      repsTarget: json['reps_target'] as int?,
      durationSeconds: json['duration_seconds'] as int?,
      distanceM: (json['distance_m'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'training_session_id': trainingSessionId,
        'workout_exercise_id': workoutExerciseId,
        'set_number': setNumber,
        'weight': weight,
        'reps': reps,
        'rpe': rpe,
        'completed': completed,
        'is_warmup': isWarmup,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (distanceM != null) 'distance_m': distanceM,
      };
}
