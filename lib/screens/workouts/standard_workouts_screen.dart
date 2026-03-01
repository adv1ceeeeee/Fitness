import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/data/standard_programs.dart';
import 'package:sportwai/services/exercise_service.dart';
import 'package:sportwai/services/workout_service.dart';
import 'package:sportwai/models/exercise.dart';

class StandardWorkoutsTab extends StatefulWidget {
  const StandardWorkoutsTab({super.key});

  @override
  State<StandardWorkoutsTab> createState() => _StandardWorkoutsTabState();
}

class _StandardWorkoutsTabState extends State<StandardWorkoutsTab> {
  List<Exercise> _exercises = [];

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    final list = await ExerciseService.getExercises();
    if (mounted) setState(() => _exercises = list);
  }

  Exercise? _findExercise(String name) {
    try {
      return _exercises.firstWhere(
        (e) => e.name.toLowerCase().contains(name.toLowerCase()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _useProgram(Map<String, dynamic> program) async {
    try {
      final workout = await WorkoutService.createWorkout(
        program['name'] as String,
        (program['days'] as List).cast<int>(),
      );

      final exercises = program['exercises'] as List;
      for (final ex in exercises) {
        final name = ex['name'] as String;
        final exercise = _findExercise(name);
        if (exercise != null) {
          await WorkoutService.addExerciseToWorkout(
            workout.id,
            exercise.id,
            sets: ex['sets'] as int? ?? 3,
            repsRange: ex['reps'] as String? ?? '8-12',
            restSeconds: ex['rest'] as int? ?? 90,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Программа "${program['name']}" добавлена в "Мои программы"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPreview(Map<String, dynamic> program) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final exercises = program['exercises'] as List;
        final daysCount = (program['days'] as List).length;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                program['name'] as String,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$daysCount раза в неделю',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Text(
                'Упражнения:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              ...exercises.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${e['name']} — ${e['sets']}x${e['reps']}',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _useProgram(program);
                  },
                  child: const Text('Использовать эту программу'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: standardPrograms.length,
      itemBuilder: (context, i) {
        final p = standardPrograms[i];
        final daysCount = (p['days'] as List).length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => _showPreview(p),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.list_alt_rounded,
                        color: AppColors.accent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['name'] as String,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$daysCount раза в неделю',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
