import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/data/standard_programs.dart';
import 'package:sportwai/services/event_logger.dart';
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

  /// Creates a single workout and adds its exercises.
  Future<void> _createSection(
    String name,
    List<int> days,
    List exercises, {
    String? groupId,
  }) async {
    final workout = await WorkoutService.createWorkout(name, days, groupId: groupId);
    for (final ex in exercises) {
      final exercise = _findExercise(ex['name'] as String);
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
    return;
  }

  Future<void> _useProgram(Map<String, dynamic> program) async {
    try {
      final sections = program['sections'] as List?;

      if (sections != null && sections.isNotEmpty) {
        // Multi-section program: create first workout, then rest share same groupId.
        final firstSection = sections.first as Map<String, dynamic>;
        final firstWorkout = await WorkoutService.createWorkout(
          firstSection['name'] as String,
          (firstSection['days'] as List).cast<int>(),
        );
        final groupId = firstWorkout.id;

        // Update first workout to point to its own id as group_id
        if (sections.length > 1) {
          await WorkoutService.setGroupId(firstWorkout.id, groupId);
        }

        // Add exercises to the first section
        for (final ex in (firstSection['exercises'] as List)) {
          final exercise = _findExercise(ex['name'] as String);
          if (exercise != null) {
            await WorkoutService.addExerciseToWorkout(
              firstWorkout.id,
              exercise.id,
              sets: ex['sets'] as int? ?? 3,
              repsRange: ex['reps'] as String? ?? '8-12',
              restSeconds: ex['rest'] as int? ?? 90,
            );
          }
        }

        // Create remaining sections
        for (final s in sections.skip(1)) {
          final sec = s as Map<String, dynamic>;
          await _createSection(
            sec['name'] as String,
            (sec['days'] as List).cast<int>(),
            sec['exercises'] as List,
            groupId: groupId,
          );
        }
      } else {
        // Single workout program
        await _createSection(
          program['name'] as String,
          (program['days'] as List).cast<int>(),
          program['exercises'] as List,
        );
      }

      if (mounted) {
        EventLogger.standardProgramUsed(programName: program['name'] as String);
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

  int _totalDays(Map<String, dynamic> program) {
    final sections = program['sections'] as List?;
    if (sections != null) {
      return sections.fold<int>(0, (sum, s) => sum + ((s as Map)['days'] as List).length);
    }
    return (program['days'] as List).length;
  }

  void _showPreview(Map<String, dynamic> program) {
    final sections = program['sections'] as List?;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  program['name'] as String,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_totalDays(program)} дней в неделю',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    children: [
                      if (sections != null) ...[
                        for (final s in sections) ...[
                          const SizedBox(height: 8),
                          Text(
                            (s as Map)['name'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...(s['exercises'] as List).map((e) => Padding(
                                padding: const EdgeInsets.only(bottom: 3, left: 8),
                                child: Text(
                                  '• ${e['name']} — ${e['sets']}×${e['reps']}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary, fontSize: 13),
                                ),
                              )),
                        ],
                      ] else ...[
                        const Text(
                          'Упражнения:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...(program['exercises'] as List).map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• ${e['name']} — ${e['sets']}×${e['reps']}',
                                style: const TextStyle(color: AppColors.textSecondary),
                              ),
                            )),
                      ],
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
                      SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgramCard(Map<String, dynamic> p) {
    final daysCount = _totalDays(p);
    final isMulti = p['sections'] != null;
    final isPremium = p['premium'] == true;
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
                    color: isPremium
                        ? const Color(0xFFFFB800).withValues(alpha: 0.15)
                        : AppColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.list_alt_rounded,
                    color: isPremium ? const Color(0xFFFFB800) : AppColors.accent,
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
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '$daysCount раза в неделю',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (isMulti) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${(p['sections'] as List).length} дня',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (isPremium)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFB800)),
                        SizedBox(width: 3),
                        Text(
                          'Pro',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFFB800),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final basic = standardPrograms.where((p) => p['premium'] != true).toList();
    final premium = standardPrograms.where((p) => p['premium'] == true).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).padding.bottom + 100),
      children: [
        // ── Стандартные программы ─────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Стандартные программы',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        for (final p in basic) _buildProgramCard(p),

        // ── Продвинутые программы ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Row(
            children: [
              const Text(
                'Продвинутые программы',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFB800)),
                    SizedBox(width: 3),
                    Text(
                      'Pro',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFFB800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final p in premium) _buildProgramCard(p),
      ],
    );
  }
}
