import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/services/training_service.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Workout? _workout;
  List<WorkoutExercise> _exercises = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final workout = await TrainingService.getTodayWorkout();
    if (workout != null) {
      final ex =
          await TrainingService.getWorkoutExercisesForToday(workout.id);
      if (mounted) {
        setState(() {
          _workout = workout;
          _exercises = ex;
          _loading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _workout = null;
          _exercises = [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _startWorkout() async {
    if (_workout == null) return;
    final session =
        await TrainingService.getOrCreateTodaySession(_workout!.id);
    if (session != null && mounted) {
      context.push('/session/${session.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Тренировка на сегодня'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _workout == null
              ? _NoWorkoutToday()
              : _WorkoutContent(
                  workout: _workout!,
                  exercises: _exercises,
                  onStart: _startWorkout,
                ),
    );
  }
}

class _NoWorkoutToday extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fitness_center_rounded,
              size: 80,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Сегодня нет запланированной тренировки',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Создайте программу и выберите дни тренировок',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => context.go('/workouts'),
              child: Text(
                'Перейти к программам',
                style: TextStyle(color: AppColors.accent, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutContent extends StatelessWidget {
  final Workout workout;
  final List<WorkoutExercise> exercises;
  final VoidCallback onStart;

  const _WorkoutContent({
    required this.workout,
    required this.exercises,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.fitness_center_rounded,
                        size: 40,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        workout.name,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Упражнения (${exercises.length})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ...exercises.asMap().entries.map((e) {
                  final i = e.key + 1;
                  final we = e.value;
                  final ex = we.exercise;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$i',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ex?.name ?? '?',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '${we.sets} x ${we.repsRange}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onStart,
              child: const Text('Начать тренировку'),
            ),
          ),
        ),
      ],
    );
  }
}
