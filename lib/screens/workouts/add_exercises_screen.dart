import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/services/exercise_service.dart';
import 'package:sportwai/services/workout_service.dart';

class AddExercisesScreen extends StatefulWidget {
  final String workoutId;

  const AddExercisesScreen({super.key, required this.workoutId});

  @override
  State<AddExercisesScreen> createState() => _AddExercisesScreenState();
}

class _AddExercisesScreenState extends State<AddExercisesScreen> {
  Workout? _workout;
  List<WorkoutExercise> _programExercises = [];
  List<Exercise> _allExercises = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await WorkoutService.getWorkout(widget.workoutId);
    final ex = await WorkoutService.getWorkoutExercises(widget.workoutId);
    final all = await ExerciseService.getExercises();
    if (mounted) {
      setState(() {
        _workout = w;
        _programExercises = ex;
        _allExercises = all;
      });
    }
  }

  List<Exercise> get _filteredExercises {
    if (_searchQuery.isEmpty) return _allExercises;
    return _allExercises
        .where((e) =>
            e.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  void _showAddDialog(Exercise exercise) {
    int sets = 3;
    String repsRange = '8-12';
    int restSeconds = 90;
    final repsController = TextEditingController(text: repsRange);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Подходы', style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _NumberButton(
                        label: '-',
                        onTap: () {
                          if (sets > 1) setModalState(() => sets--);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text('$sets', style: const TextStyle(fontSize: 24)),
                      ),
                      _NumberButton(
                        label: '+',
                        onTap: () => setModalState(() => sets++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Повторения', style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: repsController,
                    onChanged: (v) => repsRange = v,
                    decoration: const InputDecoration(
                      hintText: '8-12 или 5',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Отдых (сек)', style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [60, 90, 120].map((sec) {
                      final sel = restSeconds == sec;
                      return ChoiceChip(
                        label: Text('$sec'),
                        selected: sel,
                        onSelected: (_) => setModalState(() => restSeconds = sec),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await WorkoutService.addExerciseToWorkout(
                          widget.workoutId,
                          exercise.id,
                          sets: sets,
                          repsRange: repsController.text.trim().isNotEmpty
                              ? repsController.text.trim()
                              : '8-12',
                          restSeconds: restSeconds,
                        );
                        _load();
                      },
                      child: const Text('Добавить в программу'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_workout?.name ?? 'Упражнения'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
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
          if (_programExercises.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Text(
                    'В программе (${_programExercises.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _programExercises.length,
                itemBuilder: (context, i) {
                  final we = _programExercises[i];
                  final ex = we.exercise;
                  return Container(
                    key: ValueKey(we.id),
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    child: Card(
                      color: AppColors.card,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              ex?.name ?? '?',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Spacer(),
                            Text(
                              '${we.sets}x${we.repsRange}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _filteredExercises.length,
              itemBuilder: (context, i) {
                final ex = _filteredExercises[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: Icon(
                        Icons.fitness_center,
                        color: AppColors.accent,
                      ),
                      title: Text(
                        ex.name,
                        style: TextStyle(color: AppColors.textPrimary),
                      ),
                      subtitle: Text(
                        Exercise.categoryDisplayName(ex.category),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => _showAddDialog(ex),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _NumberButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Text(label, style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }
}
