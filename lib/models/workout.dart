import 'workout_exercise.dart';

class Workout {
  final String id;
  final String userId;
  final String name;
  final List<int> days;
  final bool isStandard;
  final int cycleWeeks;
  final int warmupMinutes;
  final int cooldownMinutes;
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
    this.warmupMinutes = 0,
    this.cooldownMinutes = 0,
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
      warmupMinutes: json['warmup_minutes'] as int? ?? 0,
      cooldownMinutes: json['cooldown_minutes'] as int? ?? 0,
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
        'warmup_minutes': warmupMinutes,
        'cooldown_minutes': cooldownMinutes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  int get daysPerWeek => days.length;
}
