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

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

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
        .where((e) => e.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  void _showEditWorkoutDialog() {
    if (_workout == null) return;
    final nameCtrl = TextEditingController(text: _workout!.name);
    final Set<int> selectedDays = Set.from(_workout!.days);
    int cycleWeeks = _workout!.cycleWeeks;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text(
            'Редактировать программу',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Название',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Дни тренировок',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(7, (i) {
                    final sel = selectedDays.contains(i);
                    return FilterChip(
                      label: Text(_dayLabels[i]),
                      selected: sel,
                      onSelected: (_) => setDialogState(() {
                        if (sel) {
                          selectedDays.remove(i);
                        } else {
                          selectedDays.add(i);
                        }
                      }),
                      selectedColor: AppColors.accent,
                      checkmarkColor: Colors.black,
                      labelStyle: TextStyle(
                        color: sel ? Colors.black : AppColors.textPrimary,
                        fontWeight:
                            sel ? FontWeight.w600 : FontWeight.w400,
                      ),
                      backgroundColor: AppColors.surface,
                    );
                  }),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Длительность цикла',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    if (cycleWeeks > 16)
                      Text('$cycleWeeks нед.',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onDoubleTap: () async {
                    final ctrl = TextEditingController(text: '$cycleWeeks');
                    final result = await showDialog<int>(
                      context: ctx,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Длительность цикла'),
                        content: TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          decoration: const InputDecoration(suffixText: 'нед.'),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Отмена')),
                          TextButton(
                            onPressed: () {
                              final v = int.tryParse(ctrl.text.trim());
                              if (v != null && v >= 1) Navigator.pop(dctx, v);
                            },
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                    ctrl.dispose();
                    if (result != null) setDialogState(() => cycleWeeks = result);
                  },
                  child: LayoutBuilder(
                    builder: (lctx, constraints) {
                      const min = 4.0;
                      const max = 16.0;
                      const pad = 24.0;
                      final sv = cycleWeeks.clamp(4, 16).toDouble();
                      final thumbX = pad + (sv - min) / (max - min) * (constraints.maxWidth - pad * 2);
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 28),
                            child: SliderTheme(
                              data: SliderTheme.of(lctx).copyWith(
                                activeTrackColor: AppColors.accent,
                                inactiveTrackColor: AppColors.surface,
                                thumbColor: AppColors.accent,
                                overlayColor: AppColors.accent.withValues(alpha: 0.12),
                              ),
                              child: Slider(
                                value: sv,
                                min: min,
                                max: max,
                                divisions: 12,
                                onChanged: (v) => setDialogState(() => cycleWeeks = v.round()),
                              ),
                            ),
                          ),
                          Positioned(
                            left: thumbX - 24,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$cycleWeeks нед.',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('4 нед.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      Text('16 нед.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                await WorkoutService.updateWorkout(
                  widget.workoutId,
                  name: name,
                  days: selectedDays.toList()..sort(),
                  cycleWeeks: cycleWeeks,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  void _showExerciseSettingsSheet({
    required String title,
    required int initialSets,
    required String initialRepsRange,
    required int initialRest,
    required double? initialTargetWeight,
    required Future<void> Function(int sets, String repsRange, int rest, double? tw) onSave,
    required String saveLabel,
  }) {
    int sets = initialSets;
    int restSeconds = initialRest;
    double? targetWeight = initialTargetWeight;
    final repsController = TextEditingController(text: initialRepsRange);
    final weightController = TextEditingController(
        text: targetWeight != null ? targetWeight.toString() : '');

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> editRestManually() async {
            final ctrl = TextEditingController(text: '$restSeconds');
            final result = await showDialog<int>(
              context: ctx,
              builder: (dctx) => AlertDialog(
                title: const Text('Отдых'),
                content: TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(suffixText: 'сек.', hintText: 'Например: 150'),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Отмена')),
                  TextButton(
                    onPressed: () {
                      final v = int.tryParse(ctrl.text.trim());
                      if (v != null && v >= 0) Navigator.pop(dctx, v);
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
            ctrl.dispose();
            if (result != null) setModalState(() => restSeconds = result);
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Подходы
                  const Text('Подходы',
                      style: TextStyle(color: AppColors.textSecondary)),
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
                        child: Text(
                          '$sets',
                          style: const TextStyle(
                              fontSize: 24, color: AppColors.textPrimary),
                        ),
                      ),
                      _NumberButton(
                        label: '+',
                        onTap: () => setModalState(() => sets++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Повторения
                  const Text('Повторения',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: repsController,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(hintText: '8-12 или 5'),
                  ),
                  const SizedBox(height: 20),

                  // Целевой вес
                  const Text('Целевой вес (кг)',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: weightController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      targetWeight = double.tryParse(v.replaceAll(',', '.'));
                    },
                    decoration: const InputDecoration(hintText: 'Не обязательно'),
                  ),
                  const SizedBox(height: 20),

                  // Отдых — слайдер
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Отдых',
                          style: TextStyle(color: AppColors.textSecondary)),
                      if (restSeconds > 120)
                        Text('$restSeconds сек.',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onDoubleTap: editRestManually,
                    child: LayoutBuilder(
                      builder: (lctx, constraints) {
                        const sliderPadding = 24.0;
                        const min = 0.0;
                        const max = 120.0;
                        final sliderVal = restSeconds.clamp(0, 120).toDouble();
                        final trackWidth = constraints.maxWidth - sliderPadding * 2;
                        final thumbX = sliderPadding + (sliderVal - min) / (max - min) * trackWidth;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 28),
                              child: SliderTheme(
                                data: SliderTheme.of(lctx).copyWith(
                                  activeTrackColor: AppColors.accent,
                                  inactiveTrackColor: AppColors.surface,
                                  thumbColor: AppColors.accent,
                                  overlayColor: AppColors.accent.withValues(alpha: 0.12),
                                ),
                                child: Slider(
                                  value: sliderVal,
                                  min: min,
                                  max: max,
                                  divisions: 24,
                                  onChanged: (v) => setModalState(() => restSeconds = v.round()),
                                ),
                              ),
                            ),
                            Positioned(
                              left: thumbX - 24,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${restSeconds}с',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('0с', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        Text('120с', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'Дважды нажмите для ручного ввода',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary.withValues(alpha: 0.6)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await onSave(
                          sets,
                          repsController.text.trim().isNotEmpty
                              ? repsController.text.trim()
                              : '8-12',
                          restSeconds,
                          targetWeight,
                        );
                        _load();
                      },
                      child: Text(saveLabel),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workout = _workout;
    final days = workout?.days ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(workout?.name ?? 'Программа'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/workouts'),
        ),
        actions: [
          if (workout != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Редактировать программу',
              onPressed: _showEditWorkoutDialog,
            ),
        ],
      ),
      body: Column(
        children: [
          // Дни и цикл
          if (days.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const Text(
                    'Дни: ',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                  ...days.map((d) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _dayLabels[d],
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )),
                  if (workout != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${workout.cycleWeeks} нед.',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ]
                ],
              ),
            ),

          // Поиск
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
          const SizedBox(height: 12),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // Упражнения в программе
                if (_programExercises.isNotEmpty) ...[
                  Text(
                    'В программе (${_programExercises.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _programExercises.removeAt(oldIndex);
                        _programExercises.insert(newIndex, item);
                      });
                      WorkoutService.reorderExercises(
                        widget.workoutId,
                        _programExercises.map((e) => e.id).toList(),
                      );
                    },
                    children: _programExercises.asMap().entries.map((entry) {
                      final i = entry.key;
                      final we = entry.value;
                      return _ProgramExerciseCard(
                        key: ValueKey(we.id),
                        dragIndex: i,
                        workoutExercise: we,
                        onEdit: () => _showExerciseSettingsSheet(
                          title: we.exercise?.name ?? '?',
                          initialSets: we.sets,
                          initialRepsRange: we.repsRange,
                          initialRest: we.restSeconds,
                          initialTargetWeight: we.targetWeight,
                          saveLabel: 'Сохранить',
                          onSave: (s, r, rest, tw) =>
                              WorkoutService.updateWorkoutExercise(
                            we.id,
                            sets: s,
                            repsRange: r,
                            restSeconds: rest,
                            targetWeight: tw,
                          ),
                        ),
                        onDelete: () async {
                          await WorkoutService.removeExerciseFromWorkout(we.id);
                          _load();
                        },
                      );
                    }).toList(),
                  ),
                  const Divider(height: 24),
                ],

                // Добавить упражнение
                Text(
                  _programExercises.isEmpty
                      ? 'Добавьте упражнения в программу'
                      : 'Добавить упражнение',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),

                ..._filteredExercises.map((ex) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          leading: const Icon(Icons.fitness_center,
                              color: AppColors.accent),
                          title: Text(ex.name,
                              style: const TextStyle(
                                  color: AppColors.textPrimary)),
                          subtitle: Text(
                            Exercise.categoryDisplayName(ex.category),
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.add,
                                color: AppColors.accent),
                            onPressed: () => _showExerciseSettingsSheet(
                              title: ex.name,
                              initialSets: 3,
                              initialRepsRange: '8-12',
                              initialRest: 90,
                              initialTargetWeight: null,
                              saveLabel: 'Добавить в программу',
                              onSave: (s, r, rest, tw) =>
                                  WorkoutService.addExerciseToWorkout(
                                widget.workoutId,
                                ex.id,
                                sets: s,
                                repsRange: r,
                                restSeconds: rest,
                                targetWeight: tw,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Карточка упражнения в программе ────────────────────────────────────────

class _ProgramExerciseCard extends StatelessWidget {
  final WorkoutExercise workoutExercise;
  final int dragIndex;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProgramExerciseCard({
    super.key,
    required this.dragIndex,
    required this.workoutExercise,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final we = workoutExercise;

    final parts = <String>[
      '${we.sets} подх. × ${we.repsRange} повт.',
      'отдых ${we.restSeconds}с',
    ];
    if (we.targetWeight != null) parts.add('${we.targetWeight} кг');
    if (we.targetRpe != null) parts.add('RPE ${we.targetRpe}');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: dragIndex,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.drag_handle,
                      color: AppColors.textSecondary, size: 22),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      we.exercise?.name ?? '?',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      parts.join('  •  '),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.tune,
                    color: AppColors.textSecondary, size: 20),
                tooltip: 'Изменить',
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    color: AppColors.error, size: 20),
                tooltip: 'Удалить',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Кнопка +/− ─────────────────────────────────────────────────────────────

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
