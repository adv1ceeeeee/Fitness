import 'package:flutter/material.dart';
import 'workout_exercise.dart';

class Workout {
  final String id;
  final String userId;
  final String name;
  final List<int> days;
  final List<int> restDays;
  final bool isStandard;
  final int cycleWeeks;
  final int warmupMinutes;
  final int cooldownMinutes;
  final String? groupId;

  /// Human-readable name of the parent multi-section program. Denormalised:
  /// all sections of the same group share the same value. NULL for single-
  /// section programs (display falls back to [name]).
  final String? groupName;
  final DateTime createdAt;
  final DateTime updatedAt;
  List<WorkoutExercise>? exercises;

  /// Per-day start time. Key = day index (0=Mon…6=Sun), value = TimeOfDay.
  final Map<int, TimeOfDay> dayTimes;

  Workout({
    required this.id,
    required this.userId,
    required this.name,
    required this.days,
    this.restDays = const [],
    this.isStandard = false,
    this.cycleWeeks = 8,
    this.warmupMinutes = 0,
    this.cooldownMinutes = 0,
    this.groupId,
    this.groupName,
    required this.createdAt,
    required this.updatedAt,
    this.exercises,
    this.dayTimes = const {},
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
      restDays: (json['rest_days'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      isStandard: json['is_standard'] as bool? ?? false,
      cycleWeeks: json['cycle_weeks'] as int? ?? 8,
      warmupMinutes: json['warmup_minutes'] as int? ?? 0,
      cooldownMinutes: json['cooldown_minutes'] as int? ?? 0,
      groupId: json['group_id'] as String?,
      groupName: json['group_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      dayTimes: _parseDayTimes(json['day_times']),
    );
  }

  static Map<int, TimeOfDay> _parseDayTimes(dynamic raw) {
    if (raw == null) return {};
    final map = raw as Map<String, dynamic>;
    final result = <int, TimeOfDay>{};
    for (final entry in map.entries) {
      final day = int.tryParse(entry.key);
      final timeStr = entry.value as String?;
      if (day != null && timeStr != null && timeStr.length >= 5) {
        final parts = timeStr.split(':');
        result[day] = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
    return result;
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
        if (groupId != null) 'group_id': groupId,
        if (groupName != null) 'group_name': groupName,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  int get daysPerWeek => days.length;

  int currentCycleWeek([DateTime? now]) {
    final totalWeeks = cycleWeeks <= 0 ? 1 : cycleWeeks;
    final current = now ?? DateTime.now();
    final startDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final currentDate = DateTime(current.year, current.month, current.day);
    final elapsedDays = currentDate.difference(startDate).inDays;
    final week = elapsedDays < 0 ? 1 : (elapsedDays ~/ 7) + 1;
    if (week < 1) return 1;
    if (week > totalWeeks) return totalWeeks;
    return week;
  }
}
