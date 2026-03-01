class TrainingSession {
  final String id;
  final String userId;
  final String workoutId;
  final DateTime date;
  final bool completed;
  final String? notes;
  final DateTime? createdAt;

  TrainingSession({
    required this.id,
    required this.userId,
    required this.workoutId,
    required this.date,
    this.completed = false,
    this.notes,
    this.createdAt,
  });

  factory TrainingSession.fromJson(Map<String, dynamic> json) {
    return TrainingSession(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      workoutId: json['workout_id'] as String,
      date: DateTime.parse(json['date'] as String),
      completed: json['completed'] as bool? ?? false,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'workout_id': workoutId,
        'date': date.toIso8601String().split('T')[0],
        'completed': completed,
        'notes': notes,
      };
}
