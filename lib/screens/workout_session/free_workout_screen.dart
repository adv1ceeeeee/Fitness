import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/screens/exercises/create_exercise_screen.dart';
import 'package:sportwai/services/exercise_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/workout_service.dart';

const _categoryOrder = ['Грудь', 'Спина', 'Плечи', 'Руки', 'Ноги', 'Кардио'];

class FreeWorkoutScreen extends StatefulWidget {
  /// Called with (workoutId, sessionId, workoutName) when session is started.
  final void Function(String sessionId, String workoutId, String workoutName) onStart;

  const FreeWorkoutScreen({super.key, required this.onStart});

  @override
  State<FreeWorkoutScreen> createState() => _FreeWorkoutScreenState();
}

class _FreeWorkoutScreenState extends State<FreeWorkoutScreen> {
  List<Exercise> _allExercises = [];
  final List<Exercise> _selected = [];
  String _searchQuery = '';
  Timer? _debounce;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadExercises() async {
    final all = await ExerciseService.getExercises();
    if (mounted) setState(() => _allExercises = all);
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = v);
    });
  }

  void _toggle(Exercise ex) {
    setState(() {
      if (_selected.any((e) => e.id == ex.id)) {
        _selected.removeWhere((e) => e.id == ex.id);
      } else {
        _selected.add(ex);
      }
    });
  }

  List<Exercise> get _filtered {
    if (_searchQuery.isEmpty) return _allExercises;
    return _allExercises
        .where((e) => e.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  List<MapEntry<String, List<Exercise>>> get _grouped {
    final groups = <String, List<Exercise>>{};
    for (final ex in _allExercises) {
      final cat = Exercise.categoryDisplayName(ex.category);
      groups.putIfAbsent(cat, () => []).add(ex);
    }
    return groups.entries.toList()
      ..sort((a, b) {
        final ia = _categoryOrder.indexOf(a.key);
        final ib = _categoryOrder.indexOf(b.key);
        if (ia == -1 && ib == -1) return a.key.compareTo(b.key);
        if (ia == -1) return 1;
        if (ib == -1) return -1;
        return ia.compareTo(ib);
      });
  }

  Future<void> _start() async {
    if (_selected.isEmpty || _starting) return;
    setState(() => _starting = true);

    try {
      // Create a temporary workout with no scheduled days
      final dateTag =
          DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
      final workout = await WorkoutService.createWorkout(
        'Свободная тренировка $dateTag',
        [],
        cycleWeeks: 1,
      );

      // Add selected exercises in order
      for (final ex in _selected) {
        await WorkoutService.addExerciseToWorkout(
          workout.id,
          ex.id,
          sets: ex.category == 'cardio' ? 1 : 3,
          repsRange: '8-12',
          restSeconds: 90,
          durationMinutes: ex.category == 'cardio' ? 30 : null,
        );
      }

      // Create session
      final session = await TrainingService.createSession(workout.id);

      if (mounted) {
        widget.onStart(session.id, workout.id, workout.name);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось запустить тренировку')),
        );
      }
    }
  }

  Future<void> _openCreateExercise() async {
    final created = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const CreateExerciseScreen()),
    );
    if (created != null && mounted) {
      setState(() {
        _allExercises = [..._allExercises, created]
          ..sort((a, b) => a.name.compareTo(b.name));
        _selected.add(created);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchQuery.isNotEmpty;
    final catalogWidgets = <Widget>[];

    if (isSearching) {
      for (final ex in _filtered) {
        catalogWidgets.add(_ExerciseTile(
          exercise: ex,
          selected: _selected.any((e) => e.id == ex.id),
          onTap: () => _toggle(ex),
        ));
      }
    } else {
      final groups = _grouped;
      for (final group in groups) {
        catalogWidgets.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            group.key,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
              letterSpacing: 0.5,
            ),
          ),
        ));
        for (final ex in group.value) {
          catalogWidgets.add(_ExerciseTile(
            exercise: ex,
            selected: _selected.any((e) => e.id == ex.id),
            onTap: () => _toggle(ex),
          ));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Свободная тренировка'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Selected exercises chips
          if (_selected.isNotEmpty)
            Container(
              color: AppColors.card,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Выбрано: ${_selected.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _selected
                        .map(
                          (ex) => Chip(
                            label: Text(ex.name,
                                style: const TextStyle(fontSize: 12)),
                            backgroundColor:
                                AppColors.accent.withValues(alpha: 0.15),
                            labelStyle:
                                const TextStyle(color: AppColors.accent),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            deleteIconColor: AppColors.accent,
                            onDeleted: () => _toggle(ex),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            side: BorderSide.none,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),

          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Поиск упражнений',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Catalog
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 4, 16, MediaQuery.of(context).padding.bottom + 80),
              children: [
                ...catalogWidgets,
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _openCreateExercise,
                  icon: const Icon(Icons.add),
                  label: const Text('Создать своё упражнение'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton(
            onPressed: _selected.isEmpty || _starting ? null : _start,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _starting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    _selected.isEmpty
                        ? 'Выберите упражнения'
                        : 'Начать тренировку (${_selected.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  final Exercise exercise;
  final bool selected;
  final VoidCallback onTap;

  const _ExerciseTile({
    required this.exercise,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? AppColors.accent.withValues(alpha: 0.12)
            : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  exercise.category == 'cardio'
                      ? Icons.directions_run
                      : Icons.fitness_center,
                  size: 20,
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: TextStyle(
                          color: selected
                              ? AppColors.accent
                              : AppColors.textPrimary,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      Text(
                        '${Exercise.categoryDisplayName(exercise.category)}${exercise.isCustom ? '  •  Моё' : ''}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle : Icons.add_circle_outline,
                  color: selected
                      ? AppColors.accent
                      : AppColors.textSecondary.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
