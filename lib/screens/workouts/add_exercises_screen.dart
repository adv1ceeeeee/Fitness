import 'dart:async';
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
  /// IDs of sections that come after this one (empty = single-section program).
  final List<String> pendingSectionIds;
  /// 0-based index of the current section (for display).
  final int sectionIndex;
  /// Total number of sections in the program.
  final int totalSections;

  const AddExercisesScreen({
    super.key,
    required this.workoutId,
    this.pendingSectionIds = const [],
    this.sectionIndex = 0,
    this.totalSections = 1,
  });

  @override
  State<AddExercisesScreen> createState() => _AddExercisesScreenState();
}

// Desired category display order
const _categoryOrder = [
  'Грудь', 'Спина', 'Плечи', 'Руки', 'Ноги', 'Кардио',
];


class _AddExercisesScreenState extends State<AddExercisesScreen> {
  Workout? _workout;
  List<WorkoutExercise> _programExercises = [];
  List<Exercise> _allExercises = [];
  String _searchQuery = '';
  Timer? _searchDebounce;

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  List<Exercise> get _filteredFlat {
    if (_searchQuery.isEmpty) return _allExercises;
    return _allExercises
        .where((e) => e.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  /// Grouped by category when no search active.
  List<MapEntry<String, List<Exercise>>> get _groupedExercises {
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

  /// Returns label like "A1", "A2", "B1"... for exercises in a superset, or null.
  String? _supersetLabel(int index) {
    final g = _programExercises[index].supersetGroup;
    if (g == null) return null;
    // Collect unique groups in order of first appearance
    final seenGroups = <int>[];
    for (final we in _programExercises) {
      if (we.supersetGroup != null && !seenGroups.contains(we.supersetGroup)) {
        seenGroups.add(we.supersetGroup!);
      }
    }
    final groupLetter = String.fromCharCode(
        'A'.codeUnitAt(0) + seenGroups.indexOf(g));
    // Count position within the group up to this index
    int pos = 0;
    for (int i = 0; i <= index; i++) {
      if (_programExercises[i].supersetGroup == g) pos++;
    }
    return '$groupLetter$pos';
  }

  /// Toggle superset link between exercise[i] and exercise[i+1].
  Future<void> _toggleSuperset(int i) async {
    final a = _programExercises[i];
    final b = _programExercises[i + 1];
    final linked = a.supersetGroup != null && a.supersetGroup == b.supersetGroup;

    if (linked) {
      // Unlink: find next available group for b if more than 2 in group
      final groupMembers = _programExercises
          .where((e) => e.supersetGroup == a.supersetGroup)
          .toList();
      if (groupMembers.length == 2) {
        // Just remove group entirely for both
        await Future.wait([
          WorkoutService.updateWorkoutExercise(a.id, supersetGroup: null),
          WorkoutService.updateWorkoutExercise(b.id, supersetGroup: null),
        ]);
      } else {
        // Remove only b from the group
        await WorkoutService.updateWorkoutExercise(b.id, supersetGroup: null);
      }
    } else {
      // Link: both get the same group ID.
      // Use a's existing group if it has one, otherwise b's, otherwise new ID.
      int newGroup;
      if (a.supersetGroup != null) {
        newGroup = a.supersetGroup!;
      } else if (b.supersetGroup != null) {
        newGroup = b.supersetGroup!;
      } else {
        // New group ID = max existing + 1
        final maxGroup = _programExercises
            .map((e) => e.supersetGroup ?? 0)
            .reduce((a, b) => a > b ? a : b);
        newGroup = maxGroup + 1;
      }
      await Future.wait([
        WorkoutService.updateWorkoutExercise(a.id, supersetGroup: newGroup),
        WorkoutService.updateWorkoutExercise(b.id, supersetGroup: newGroup),
      ]);
    }
    await _load();
  }


  void _showEditWorkoutDialog() {
    if (_workout == null) return;
    final nameCtrl = TextEditingController(text: _workout!.name);
    final Set<int> selectedDays = Set.from(_workout!.days);
    int cycleWeeks = _workout!.cycleWeeks;
    int warmupMinutes = _workout!.warmupMinutes;
    int cooldownMinutes = _workout!.cooldownMinutes;

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
                    GestureDetector(
                      onTap: () async {
                        final ctrl = TextEditingController(text: '$cycleWeeks');
                        final result = await showDialog<int>(
                          context: ctx,
                          builder: (dctx) => AlertDialog(
                            backgroundColor: AppColors.card,
                            title: const Text('Длительность цикла',
                                style: TextStyle(color: AppColors.textPrimary)),
                            content: TextField(
                              controller: ctrl,
                              keyboardType: TextInputType.number,
                              autofocus: true,
                              style: const TextStyle(color: AppColors.textPrimary),
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$cycleWeeks нед.',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(ctx).copyWith(
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: AppColors.surface,
                    thumbColor: AppColors.accent,
                    overlayColor: AppColors.accent.withValues(alpha: 0.12),
                  ),
                  child: Slider(
                    value: cycleWeeks.clamp(4, 16).toDouble(),
                    min: 4,
                    max: 16,
                    divisions: 12,
                    label: '$cycleWeeks нед.',
                    onChanged: (v) => setDialogState(() => cycleWeeks = v.round()),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('4 нед.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      Text('16 нед.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Разминка
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Разминка',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    _MinuteStepper(
                      value: warmupMinutes,
                      onChanged: (v) => setDialogState(() => warmupMinutes = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Заминка
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Заминка',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    _MinuteStepper(
                      value: cooldownMinutes,
                      onChanged: (v) => setDialogState(() => cooldownMinutes = v),
                    ),
                  ],
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
                  warmupMinutes: warmupMinutes,
                  cooldownMinutes: cooldownMinutes,
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

  /// Shows the exercise params bottom sheet.
  /// [isCardio] — if true, shows only a duration slider (minutes).
  /// [onSave] receives (sets, repsRange, restSeconds, targetWeight, durationMinutes).
  void _showExerciseSettingsSheet({
    required String title,
    required bool isCardio,
    required int initialSets,
    required String initialRepsRange,
    required int initialRest,
    required double? initialTargetWeight,
    required int initialDurationMinutes,
    required Future<void> Function(
            int sets, String repsRange, int rest, double? tw, int? durationMinutes)
        onSave,
    required String saveLabel,
  }) {
    int sets = initialSets;
    int restSeconds = initialRest;
    double? targetWeight = initialTargetWeight;
    int durationMinutes = initialDurationMinutes;
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

                  if (isCardio) ...[
                    // ─── Кардио: только длительность ─────────────────────
                    const Text('Длительность',
                        style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        '$durationMinutes мин',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(ctx).copyWith(
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: AppColors.surface,
                        thumbColor: AppColors.accent,
                        overlayColor: AppColors.accent.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        value: durationMinutes.clamp(5, 120).toDouble(),
                        min: 5,
                        max: 120,
                        divisions: 23,
                        label: '$durationMinutes мин',
                        onChanged: (v) => setModalState(
                            () => durationMinutes = (v / 5).round() * 5),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('5 мин',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                          Text('120 мин',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ] else ...[
                    // ─── С отягощением: подходы/повторения/вес/отдых ─────

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
                                    '$restSeconds с',
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
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
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
                  ],
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (isCardio) {
                          await onSave(1, '1', 0, null, durationMinutes);
                        } else {
                          await onSave(
                            sets,
                            repsController.text.trim().isNotEmpty
                                ? repsController.text.trim()
                                : '8-12',
                            restSeconds,
                            targetWeight,
                            null,
                          );
                        }
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

  List<Widget> _buildExerciseTiles(List<Exercise> exercises) {
    return exercises.map((ex) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: Icon(
            ex.category == 'cardio' ? Icons.directions_run : Icons.fitness_center,
            color: AppColors.accent,
          ),
          title: Text(ex.name,
              style: const TextStyle(color: AppColors.textPrimary)),
          subtitle: Text(
            Exercise.categoryDisplayName(ex.category),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add, color: AppColors.accent),
            onPressed: () => _showExerciseSettingsSheet(
              title: ex.name,
              isCardio: ex.category == 'cardio',
              initialSets: 3,
              initialRepsRange: '8-12',
              initialRest: 90,
              initialTargetWeight: null,
              initialDurationMinutes: 30,
              saveLabel: 'Добавить в программу',
              onSave: (s, r, rest, tw, dur) => WorkoutService.addExerciseToWorkout(
                widget.workoutId,
                ex.id,
                sets: s,
                repsRange: r,
                restSeconds: rest,
                targetWeight: tw,
                durationMinutes: dur,
              ),
            ),
          ),
        ),
      ),
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    final workout = _workout;
    final days = workout?.days ?? [];

    // Build catalog with group separators
    final groups = _groupedExercises;
    final catalogWidgets = <Widget>[];
    bool weightedHeaderShown = false;
    bool cardioHeaderShown = false;
    for (final group in groups) {
      final isCardioGroup = group.value.any((e) => e.category == 'cardio');
      if (!isCardioGroup && !weightedHeaderShown) {
        catalogWidgets.add(const _GroupSeparator('С отягощением'));
        weightedHeaderShown = true;
      }
      if (isCardioGroup && !cardioHeaderShown) {
        catalogWidgets.add(const _GroupSeparator('Без отягощения'));
        cardioHeaderShown = true;
      }
      catalogWidgets.add(_CategoryHeader(label: group.key));
      catalogWidgets.addAll(_buildExerciseTiles(group.value));
    }

    final isMultiSection = widget.totalSections > 1;
    final sectionTitle = isMultiSection
        ? '${widget.sectionIndex + 1}/${widget.totalSections}: ${workout?.name ?? ''}'
        : (workout?.name ?? 'Программа');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(sectionTitle),
            if (days.isNotEmpty)
              Text(
                days.map((d) => _dayLabels[d]).join(' · '),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
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
          if (widget.pendingSectionIds.isNotEmpty)
            TextButton(
              onPressed: () => context.pushReplacement(
                '/workouts/${widget.pendingSectionIds.first}/exercises',
                extra: {
                  'pendingIds': widget.pendingSectionIds.skip(1).toList(),
                  'sectionIndex': widget.sectionIndex + 1,
                  'totalSections': widget.totalSections,
                },
              ),
              child: const Text(
                'Далее →',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
          const SizedBox(height: 12),

          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 0, 16, MediaQuery.of(context).padding.bottom + 80),
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
                      final isLast = i == _programExercises.length - 1;
                      final nextWe = isLast ? null : _programExercises[i + 1];
                      final isLinkedWithNext = !isLast &&
                          we.supersetGroup != null &&
                          we.supersetGroup == nextWe?.supersetGroup;
                      return _ProgramExerciseCard(
                        key: ValueKey(we.id),
                        dragIndex: i,
                        workoutExercise: we,
                        supersetLabel: _supersetLabel(i),
                        isLinkedWithNext: isLinkedWithNext,
                        canLink: !isLast,
                        onToggleLink: () => _toggleSuperset(i),
                        onEdit: () => _showExerciseSettingsSheet(
                          title: we.exercise?.name ?? '?',
                          isCardio: we.exercise?.category == 'cardio',
                          initialSets: we.sets,
                          initialRepsRange: we.repsRange,
                          initialRest: we.restSeconds,
                          initialTargetWeight: we.targetWeight,
                          initialDurationMinutes: we.durationMinutes ?? 30,
                          saveLabel: 'Сохранить',
                          onSave: (s, r, rest, tw, dur) =>
                              WorkoutService.updateWorkoutExercise(
                            we.id,
                            sets: s,
                            repsRange: r,
                            restSeconds: rest,
                            targetWeight: tw,
                            durationMinutes: dur,
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

                if (_searchQuery.isNotEmpty)
                  ..._buildExerciseTiles(_filteredFlat)
                else
                  ...catalogWidgets,

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
  final String? supersetLabel;   // e.g. "A1", "A2"
  final bool isLinkedWithNext;
  final bool canLink;
  final VoidCallback onToggleLink;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProgramExerciseCard({
    super.key,
    required this.dragIndex,
    required this.workoutExercise,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleLink,
    this.supersetLabel,
    this.isLinkedWithNext = false,
    this.canLink = false,
  });

  @override
  Widget build(BuildContext context) {
    final we = workoutExercise;
    final isCardio = we.exercise?.category == 'cardio';
    final inSuperset = supersetLabel != null;

    final String subtitle;
    if (isCardio) {
      subtitle = '${we.durationMinutes ?? 30} мин';
    } else {
      final parts = <String>[
        '${we.sets} подх. × ${we.repsRange} повт.',
        'отдых ${we.restSeconds}с',
      ];
      if (we.targetWeight != null) parts.add('${we.targetWeight} кг');
      if (we.targetRpe != null) parts.add('RPE ${we.targetRpe}');
      subtitle = parts.join('  •  ');
    }

    // Accent colour for this superset group (cycle through palette)
    const supersetColors = [
      Color(0xFF30D158), // green – group A
      Color(0xFFFF9F0A), // orange – group B
      Color(0xFFFF453A), // red – group C
      Color(0xFFBF5AF2), // purple – group D
    ];
    final groupIndex = supersetLabel != null
        ? (supersetLabel!.codeUnitAt(0) - 'A'.codeUnitAt(0)) %
            supersetColors.length
        : 0;
    final supersetColor = supersetColors[groupIndex];

    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Column(
        children: [
          // ── Exercise card ────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: inSuperset
                  ? Border(
                      left: BorderSide(color: supersetColor, width: 3),
                    )
                  : null,
            ),
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
                  // Order number badge
                  if (supersetLabel == null)
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${dragIndex + 1}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  // Superset badge
                  if (supersetLabel != null) ...[
                    Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: supersetColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        supersetLabel!,
                        style: TextStyle(
                          color: supersetColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
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
                          subtitle,
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

          // ── Superset link button ─────────────────────────────────────
          if (canLink)
            GestureDetector(
              onTap: onToggleLink,
              child: Container(
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        color: isLinkedWithNext
                            ? supersetColor.withValues(alpha: 0.5)
                            : AppColors.surface,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isLinkedWithNext
                            ? supersetColor.withValues(alpha: 0.15)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLinkedWithNext
                                ? Icons.link
                                : Icons.link_off,
                            size: 13,
                            color: isLinkedWithNext
                                ? supersetColor
                                : AppColors.textSecondary
                                    .withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isLinkedWithNext ? 'Суперсет' : 'Связать',
                            style: TextStyle(
                              fontSize: 11,
                              color: isLinkedWithNext
                                  ? supersetColor
                                  : AppColors.textSecondary
                                      .withValues(alpha: 0.5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: isLinkedWithNext
                            ? supersetColor.withValues(alpha: 0.5)
                            : AppColors.surface,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
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

// ─── Заголовок категории упражнений ──────────────────────────────────────────

class _CategoryHeader extends StatelessWidget {
  final String label;

  const _CategoryHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Степпер минут (0–30, шаг 5) ─────────────────────────────────────────────

class _MinuteStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _MinuteStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: value >= 5 ? () => onChanged(value - 5) : null,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.remove,
                size: 16,
                color: value >= 5
                    ? AppColors.textPrimary
                    : AppColors.textSecondary.withValues(alpha: 0.3)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            value == 0 ? 'Выкл' : '$value мин',
            style: TextStyle(
              fontSize: 13,
              color: value > 0 ? AppColors.accent : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        GestureDetector(
          onTap: value < 30 ? () => onChanged(value + 5) : null,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.add,
                size: 16,
                color: value < 30
                    ? AppColors.textPrimary
                    : AppColors.textSecondary.withValues(alpha: 0.3)),
          ),
        ),
      ],
    );
  }
}

// ─── Разделитель групп упражнений ────────────────────────────────────────────

class _GroupSeparator extends StatelessWidget {
  final String label;

  const _GroupSeparator(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
