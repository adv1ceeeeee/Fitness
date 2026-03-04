import 'workout_exercise.dart';

class Workout {
  final String id;
  final String userId;
  final String name;
  final List<int> days;
  final bool isStandard;
  final int cycleWeeks;
  final DateTime createdAt;
  final DateTime updatedAt;
  List<WorkoutExercise>? exercises;

  Workout({
    required this.id,
    required this.userId,
    required this.name,
    required this.days,
    this.isStandard = false,
    this.cycleWeeks = 8,
    required this.createdAt,
    required this.updatedAt,
    this.exercises,
  });

  factory Workout.fromJson(Map<String, dynamic> json) {
    return Workout(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      days: (json['days'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      isStandard: json['is_standard'] as bool? ?? false,
      cycleWeeks: json['cycle_weeks'] as int? ?? 8,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'days': days,
        'is_standard': isStandard,
        'cycle_weeks': cycleWeeks,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  int get daysPerWeek => days.length;
}
