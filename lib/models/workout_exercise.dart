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
  final Map<int, double> weeklyTargetWeights;
  final Map<int, double> dropSetWeeklyTargetWeights;
  final int? targetRpe;
  final int? durationMinutes;
  final int? supersetGroup;
  final bool isDropSet;
  final int? day; // which day of the week (0=Mon … 6=Sun), null = all days
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
    this.weeklyTargetWeights = const {},
    this.dropSetWeeklyTargetWeights = const {},
    this.targetRpe,
    this.durationMinutes,
    this.supersetGroup,
    this.isDropSet = false,
    this.day,
    this.exercise,
  });

  bool get isCardio => exercise?.category == 'cardio';

  double? weightForWeek(int week) {
    final direct = weeklyTargetWeights[week];
    if (direct != null) return direct;
    for (var previousWeek = week - 1; previousWeek >= 1; previousWeek--) {
      final previous = weeklyTargetWeights[previousWeek];
      if (previous != null) return previous;
    }
    return targetWeight;
  }

  bool hasWeightForWeek(int week) => weeklyTargetWeights.containsKey(week);

  double? dropSetWeightForWeek(int week) {
    final direct = dropSetWeeklyTargetWeights[week];
    if (direct != null) return direct;
    for (var previousWeek = week - 1; previousWeek >= 1; previousWeek--) {
      final previous = dropSetWeeklyTargetWeights[previousWeek];
      if (previous != null) return previous;
    }
    final mainWeight = weightForWeek(week);
    if (mainWeight == null) return null;
    return mainWeight * 0.6;
  }

  bool hasDropSetWeightForWeek(int week) =>
      dropSetWeeklyTargetWeights.containsKey(week);

  WorkoutExercise copyWithExercise(Exercise newExercise) => WorkoutExercise(
        id: id,
        workoutId: workoutId,
        exerciseId: newExercise.id,
        order: order,
        sets: sets,
        repsRange: repsRange,
        restSeconds: restSeconds,
        targetWeight: targetWeight,
        weeklyTargetWeights: weeklyTargetWeights,
        dropSetWeeklyTargetWeights: dropSetWeeklyTargetWeights,
        targetRpe: targetRpe,
        durationMinutes: durationMinutes,
        supersetGroup: supersetGroup,
        isDropSet: isDropSet,
        day: day,
        exercise: newExercise,
      );

  factory WorkoutExercise.fromJson(Map<String, dynamic> json) {
    Map<int, double> parseWeeklyWeights(Object? raw) {
      if (raw is! Map) return const {};
      final parsed = <int, double>{};
      for (final entry in raw.entries) {
        final week = int.tryParse('${entry.key}');
        final value = entry.value;
        if (week != null && value is num) {
          parsed[week] = value.toDouble();
        }
      }
      return parsed;
    }

    return WorkoutExercise(
      id: json['id'] as String,
      workoutId: json['workout_id'] as String,
      exerciseId: json['exercise_id'] as String,
      order: json['order'] as int,
      sets: json['sets'] as int,
      repsRange: json['reps_range'] as String? ?? '8-12',
      restSeconds: json['rest_seconds'] as int? ?? 90,
      targetWeight: (json['target_weight'] as num?)?.toDouble(),
      weeklyTargetWeights: parseWeeklyWeights(json['weekly_target_weights']),
      dropSetWeeklyTargetWeights:
          parseWeeklyWeights(json['drop_set_weekly_target_weights']),
      targetRpe: json['target_rpe'] as int?,
      durationMinutes: json['duration_minutes'] as int?,
      supersetGroup: json['superset_group'] as int?,
      isDropSet: json['is_drop_set'] as bool? ?? false,
      day: json['day'] as int?,
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
        'weekly_target_weights': weeklyTargetWeights
            .map((week, weight) => MapEntry('$week', weight)),
        'drop_set_weekly_target_weights': dropSetWeeklyTargetWeights
            .map((week, weight) => MapEntry('$week', weight)),
        'target_rpe': targetRpe,
        'duration_minutes': durationMinutes,
        'superset_group': supersetGroup,
        'is_drop_set': isDropSet,
        'day': day,
        // Nested exercise included for cache round-tripping. Supabase inserts
        // use manual maps, not toJson(), so this does not affect writes.
        if (exercise != null) 'exercises': exercise!.toJson(),
      };
}
