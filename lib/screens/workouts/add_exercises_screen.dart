import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sportwai/services/image_cache_manager.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/screens/exercises/create_exercise_screen.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/data/standard_programs.dart';
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
  'Грудь', 'Спина', 'Плечи', 'Руки', 'Ноги', 'Кардио', 'Пресс',
];

// Category key → display name (in chip order)
const _categoryChips = [
  ('chest', 'Грудь'),
  ('back', 'Спина'),
  ('shoulders', 'Плечи'),
  ('arms', 'Руки'),
  ('legs', 'Ноги'),
  ('core', 'Пресс'),
  ('cardio', 'Кардио'),
];

enum ExerciseSortMode { alphabetical, difficulty, popularity, userResults }


class _AddExercisesScreenState extends State<AddExercisesScreen> {
  Workout? _workout;
  List<WorkoutExercise> _programExercises = [];
  List<Exercise> _allExercises = [];
  List<Workout> _groupSections = []; // all sections of a multi-section program
  String _searchQuery = '';
  bool _favoritesOnly = false;
  bool _loading = true;
  Timer? _searchDebounce;
  String? _openCategory; // currently pinned/open category (single-expand)
  int? _selectedDay; // currently active day context for adding exercises
  // ── Filter & sort ──
  String? _selectedCategoryKey; // 'chest', 'back', etc. (derived from _openCategory)
  String? _selectedMovementType; // 'press', 'row', etc.
  bool _showMovementFilter = false; // movement chips visible inside expanded category
  bool _showCategorySearch = false; // search field inside expanded category
  String _categorySearchQuery = ''; // search query inside expanded category
  final TextEditingController _categorySearchController = TextEditingController();
  ExerciseSortMode _sortMode = ExerciseSortMode.alphabetical;
  Map<String, double> _userBest1RMs = {};
  Map<String, int> _popularity = {};

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  /// Exercises filtered to the currently selected day.
  /// If no day is selected, shows all exercises (both day-assigned and unassigned).
  List<WorkoutExercise> get _visibleExercises {
    if (_selectedDay == null) return _programExercises;
    return _programExercises
        .where((e) => e.day == null || e.day == _selectedDay)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _categorySearchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _searchQuery = value);
      if (value.isNotEmpty) {
        final count = _allExercises
            .where((e) => e.name.toLowerCase().contains(value.toLowerCase()))
            .length;
        EventLogger.exerciseSearched(query: value, resultsCount: count);
      }
    });
  }

  List<Exercise> get _filteredFlat {
    var list = _favoritesOnly ? _allExercises.where((e) => e.isFavorite).toList() : _allExercises;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) =>
        e.name.toLowerCase().contains(q) ||
        (e.nameRu?.toLowerCase().contains(q) ?? false)
      ).toList();
    }
    if (_selectedCategoryKey != null) {
      list = list.where((e) => e.category == _selectedCategoryKey).toList();
    }
    if (_selectedMovementType != null) {
      list = list.where((e) => e.effectiveMovementType == _selectedMovementType).toList();
    }
    return _sorted(list);
  }

  List<Exercise> _sorted(List<Exercise> list) {
    final copy = List<Exercise>.from(list);
    switch (_sortMode) {
      case ExerciseSortMode.alphabetical:
        copy.sort((a, b) => a.displayName.compareTo(b.displayName));
      case ExerciseSortMode.difficulty:
        copy.sort((a, b) => a.difficultyOrder.compareTo(b.difficultyOrder));
      case ExerciseSortMode.popularity:
        copy.sort((a, b) =>
          (_popularity[b.id] ?? 0).compareTo(_popularity[a.id] ?? 0));
      case ExerciseSortMode.userResults:
        copy.sort((a, b) =>
          (_userBest1RMs[b.id] ?? 0).compareTo(_userBest1RMs[a.id] ?? 0));
    }
    return copy;
  }

  Future<void> _toggleFavorite(Exercise ex) async {
    final newVal = !ex.isFavorite;
    // Optimistic update
    setState(() {
      final idx = _allExercises.indexWhere((e) => e.id == ex.id);
      if (idx != -1) {
        _allExercises[idx] = _allExercises[idx].copyWith(isFavorite: newVal);
      }
    });
    await ExerciseService.toggleFavorite(ex.id, add: newVal);
  }

  /// Grouped by category when no search active.
  List<MapEntry<String, List<Exercise>>> get _groupedExercises {
    final source = _favoritesOnly ? _allExercises.where((e) => e.isFavorite).toList() : _allExercises;
    final groups = <String, List<Exercise>>{};
    for (final ex in source) {
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
    if (mounted) setState(() => _loading = true);
    final results = await Future.wait([
      WorkoutService.getWorkout(widget.workoutId),
      WorkoutService.getWorkoutExercises(widget.workoutId),
      ExerciseService.getExercises(),
    ]);
    final w = results[0] as Workout?;
    final ex = results[1] as List<WorkoutExercise>;
    final all = results[2] as List<Exercise>;
    // If this is a section of a multi-section program, load siblings too.
    final sections = (w?.groupId != null)
        ? await WorkoutService.getSectionsByGroupId(w!.groupId!)
        : <Workout>[];
    if (!mounted) return;
    setState(() {
      _workout = w;
      _programExercises = ex;
      _allExercises = all;
      _groupSections = sections;
      _loading = false;
      // Auto-select when only one day in this section
      if (w != null && w.days.length == 1) _selectedDay = w.days.first;
    });
    // Load sort data in background — only needed when user switches sort mode.
    ExerciseService.getBest1RMs().then((orms) {
      if (mounted) setState(() => _userBest1RMs = orms);
    }).catchError((_) {});
    ExerciseService.getPopularity().then((pop) {
      if (mounted) setState(() => _popularity = pop);
    }).catchError((_) {});
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


  Future<void> _toggleDropSet(int i) async {
    final we = _programExercises[i];
    await WorkoutService.updateWorkoutExercise(
      we.id,
      isDropSet: !we.isDropSet,
    );
    await _load();
  }

  void _showEditWorkoutDialog() {
    if (_workout == null) return;
    final nameCtrl = TextEditingController(text: _workout!.name);
    final Set<int> selectedDays = Set.from(_workout!.days);
    int cycleWeeks = _workout!.cycleWeeks == 0 ? 8 : _workout!.cycleWeeks;
    bool noCycle = _workout!.cycleWeeks == 0;
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
                Opacity(
                  opacity: noCycle ? 0.35 : 1.0,
                  child: IgnorePointer(
                    ignoring: noCycle,
                    child: SliderTheme(
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
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => setDialogState(() => noCycle = !noCycle),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: noCycle
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: noCycle
                            ? AppColors.accent
                            : AppColors.textSecondary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.all_inclusive, size: 16,
                            color: noCycle ? AppColors.accent : AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text('Без цикла',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: noCycle ? AppColors.accent : AppColors.textSecondary,
                            )),
                      ],
                    ),
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
                  cycleWeeks: noCycle ? 0 : cycleWeeks,
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
    String? gifUrl,
    String? description,
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
                  if (gifUrl != null || (description != null && description.isNotEmpty)) ...[
                    const SizedBox(height: 16),
                    if (gifUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          cacheManager: AppImageCacheManager.instance,
                          imageUrl: gifUrl,
                          width: double.infinity,
                          height: 260,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const SizedBox(height: 260),
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    if (description != null && description.isNotEmpty) ...[
                      if (gifUrl != null) const SizedBox(height: 12),
                      Text(
                        description,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
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
                    const SizedBox(height: 6),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app_outlined,
                              size: 13,
                              color: AppColors.textSecondary.withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Text(
                            'Дважды нажмите на слайдер для ввода вручную',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary.withValues(alpha: 0.5)),
                          ),
                        ],
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

  Future<void> _openCreateExercise() async {
    final created = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const CreateExerciseScreen()),
    );
    if (created != null && mounted) {
      setState(() => _allExercises = [..._allExercises, created]
        ..sort((a, b) => a.name.compareTo(b.name)));
    }
  }

  Future<void> _deleteCustomExercise(Exercise ex) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Удалить упражнение?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(ex.displayName,
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ExerciseService.deleteExercise(ex.id);
      if (mounted) setState(() => _allExercises.removeWhere((e) => e.id == ex.id));
    }
  }

  List<Exercise> _exercisesForCategory(String category) {
    var source = _favoritesOnly
        ? _allExercises.where((e) => e.isFavorite).toList()
        : List<Exercise>.from(_allExercises);
    source = source
        .where((e) => Exercise.categoryDisplayName(e.category) == category)
        .toList();
    if (_selectedMovementType != null) {
      source = source.where((e) => e.effectiveMovementType == _selectedMovementType).toList();
    }
    if (_categorySearchQuery.isNotEmpty) {
      final q = _categorySearchQuery.toLowerCase();
      source = source.where((e) =>
          e.displayName.toLowerCase().contains(q) ||
          e.name.toLowerCase().contains(q)).toList();
    }
    return _sorted(source);
  }

  void _showExerciseHistory(Exercise ex) {
    context.push('/exercise/${ex.id}/history', extra: ex);
  }

  /// Called when user taps an exercise card or the + button.
  /// If the program has multiple days and none is selected, asks the user
  /// to pick a day first, then opens the settings sheet.
  void _triggerAddExercise(Exercise ex) {
    final days = _workout?.days ?? [];
    if (days.length > 1 && _selectedDay == null) {
      // Ask which day
      showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.card,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 56),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('В какой день добавить?',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(ex.displayName,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: days.map((d) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _selectedDay = d);
                      _openAddSheet(ex);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        _dayLabels[d],
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    } else {
      _openAddSheet(ex);
    }
  }

  void _openAddSheet(Exercise ex) {
    _showExerciseSettingsSheet(
      title: ex.displayName,
      gifUrl: ex.gifUrl,
      description: ex.descriptionRu ?? ex.description,
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
        day: _selectedDay,
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
          onTap: () => _triggerAddExercise(ex),
          onLongPress: () => _showExerciseHistory(ex),
          leading: Icon(
            ex.category == 'cardio' ? Icons.directions_run : Icons.fitness_center,
            color: ex.isCustom ? AppColors.accent.withValues(alpha: 0.75) : AppColors.accent,
          ),
          title: Text(ex.displayName,
              style: const TextStyle(color: AppColors.textPrimary)),
          subtitle: Text(
            '${Exercise.categoryDisplayName(ex.category)}${ex.isCustom ? '  •  Моё' : ''}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  ex.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 20,
                  color: ex.isFavorite ? const Color(0xFFFFB800) : AppColors.textSecondary,
                ),
                onPressed: () => _toggleFavorite(ex),
              ),
              if (ex.isCustom)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: AppColors.textSecondary,
                  onPressed: () => _deleteCustomExercise(ex),
                ),
              IconButton(
                icon: const Icon(Icons.add, color: AppColors.accent),
                onPressed: () => _triggerAddExercise(ex),
              ),
            ],
          ),
        ),
      ),
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.background, elevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final workout = _workout;
    final days = workout?.days ?? [];

    // Catalog — collapsed list of category headers only (exercise list shown separately)
    final groups = _groupedExercises;
    final catalogWidgets = <Widget>[];
    bool weightedHeaderShown = false;
    bool cardioHeaderShown = false;
    for (final group in groups) {
      final isCardioGroup = group.value.any((e) => e.category == 'cardio');
      if (!isCardioGroup && !weightedHeaderShown) {
        catalogWidgets.add(const _GroupSeparator('Группы мышц'));
        weightedHeaderShown = true;
      }
      if (isCardioGroup && !cardioHeaderShown) {
        catalogWidgets.add(const _GroupSeparator('Кардио'));
        cardioHeaderShown = true;
      }
      catalogWidgets.add(_CategoryHeader(
        label: group.key,
        count: group.value.length,
        expanded: _openCategory == group.key,
        onToggle: () => setState(() {
          if (_openCategory == group.key) {
            _openCategory = null;
            _selectedCategoryKey = null;
            _selectedMovementType = null;
            _showMovementFilter = false;
            _showCategorySearch = false;
            _categorySearchQuery = '';
            _categorySearchController.clear();
          } else {
            _openCategory = group.key;
            _selectedCategoryKey = _keyForDisplayName(group.key);
            _selectedMovementType = null;
            _showMovementFilter = false;
            _showCategorySearch = false;
            _categorySearchQuery = '';
            _categorySearchController.clear();
          }
        }),
      ));
    }

    // Same color logic as program cards in workouts_screen
    const Color kPremiumColor = Color(0xFFFFB800);
    const Color kUserColor = Color(0xFFAB7FF8);
    final String wName = workout?.name ?? '';
    final Color workoutIconColor = premiumWorkoutNames.contains(wName)
        ? kPremiumColor
        : allStandardWorkoutNames.contains(wName)
            ? AppColors.accent
            : kUserColor;

    final isMultiSection = widget.totalSections > 1;
    final sectionTitle = isMultiSection
        ? '${widget.sectionIndex + 1}/${widget.totalSections}: ${workout?.name ?? ''}'
        : (workout?.name ?? 'Программа');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: 72,
        title: Row(
          children: [
            Hero(
              tag: 'workout-icon-${widget.workoutId}',
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: workoutIconColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.fitness_center_rounded,
                  color: workoutIconColor,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sectionTitle,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, height: 1.15),
                  ),
                  if (days.isNotEmpty)
                    Text(
                      days.map((d) => _dayLabels[d]).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                ],
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
                      workout.cycleWeeks == 0 ? '∞' : '${workout.cycleWeeks} нед.',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ]
                ],
              ),
            ),

          // ── Day/section tabs (multi-section programs) ─────────────────────
          if (_groupSections.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _groupSections.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final s = _groupSections[i];
                    final isActive = s.id == widget.workoutId;
                    final dayLabel = s.days
                        .map((d) => _dayLabels[d])
                        .join(', ');
                    return GestureDetector(
                      onTap: isActive
                          ? null
                          : () => context.go(
                                '/workouts/${s.id}/exercises',
                              ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.accent
                              : AppColors.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isActive
                                ? AppColors.accent
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          dayLabel.isEmpty ? s.name : dayLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // ── Day selector chips (when section has > 1 day) ──────────────────
          if ((days.length > 1))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  const Text('День: ',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  ...days.map((d) {
                    final isSelected = _selectedDay == d;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => setState(() =>
                            _selectedDay = isSelected ? null : d),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF3A3A3A)
                                : AppColors.card,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(color: const Color(0xFF6B6B6B))
                                : null,
                          ),
                          child: Text(
                            _dayLabels[d],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  if (_selectedDay != null)
                    GestureDetector(
                      onTap: () => setState(() => _selectedDay = null),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 2),
                        child: Icon(Icons.close,
                            size: 14, color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),

          // ── Поиск ───────────────────────────────────────────────────────────
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
          // ── Избранное + сортировка ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Избранное'),
                  avatar: Icon(
                    _favoritesOnly ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 16,
                    color: _favoritesOnly ? Colors.black : AppColors.textSecondary,
                  ),
                  selected: _favoritesOnly,
                  onSelected: (v) => setState(() => _favoritesOnly = v),
                  selectedColor: const Color(0xFFFFB800),
                  checkmarkColor: Colors.black,
                  labelStyle: TextStyle(
                    color: _favoritesOnly ? Colors.black : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  backgroundColor: AppColors.card,
                  showCheckmark: false,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _showSortSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _sortMode != ExerciseSortMode.alphabetical
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: _sortMode != ExerciseSortMode.alphabetical
                          ? Border.all(color: AppColors.accent, width: 1)
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sort_rounded,
                            size: 16,
                            color: _sortMode != ExerciseSortMode.alphabetical
                                ? AppColors.accent
                                : AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          _sortModeLabel(_sortMode),
                          style: TextStyle(
                            fontSize: 12,
                            color: _sortMode != ExerciseSortMode.alphabetical
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Открытая категория: прилипающий заголовок + фильтр + список ──────
          if (_openCategory != null && _searchQuery.isEmpty) ...[
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _CategoryHeader(
                label: _openCategory!,
                count: _exercisesForCategory(_openCategory!).length,
                totalCount: _totalForCategory(_openCategory!),
                expanded: true,
                filterVisible: _showMovementFilter,
                filterActive: _selectedMovementType != null,
                onToggle: () => setState(() {
                  _openCategory = null;
                  _selectedCategoryKey = null;
                  _selectedMovementType = null;
                  _showMovementFilter = false;
                  _showCategorySearch = false;
                  _categorySearchQuery = '';
                  _categorySearchController.clear();
                }),
                onFilterToggle: () => setState(
                    () => _showMovementFilter = !_showMovementFilter),
                onSearchToggle: () => setState(() {
                  _showCategorySearch = !_showCategorySearch;
                  if (!_showCategorySearch) {
                    _categorySearchQuery = '';
                    _categorySearchController.clear();
                  }
                }),
                searchVisible: _showCategorySearch,
              ),
            ),
            // ── Search field inside category ──────────────────────────────────
            if (_showCategorySearch)
              Container(
                color: AppColors.background,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _categorySearchController,
                  autofocus: true,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Поиск в категории...',
                    hintStyle: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.6),
                        fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 18, color: AppColors.textSecondary),
                    suffixIcon: _categorySearchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () => setState(() {
                              _categorySearchQuery = '';
                              _categorySearchController.clear();
                            }),
                            child: const Icon(Icons.close_rounded,
                                size: 16, color: AppColors.textSecondary),
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.card,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _categorySearchQuery = v),
                ),
              ),
            // ── Movement type chips (shown when ≡ is active) ──────────────────
            if (_showMovementFilter && _selectedCategoryKey != null)
              Container(
                color: AppColors.background,
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildChip(
                        label: 'Все',
                        selected: _selectedMovementType == null,
                        small: true,
                        onTap: () =>
                            setState(() => _selectedMovementType = null),
                      ),
                      ...Exercise.movementsForCategory(_selectedCategoryKey!)
                          .map((mt) => _buildChip(
                                label: Exercise.movementDisplayName(mt),
                                selected: _selectedMovementType == mt,
                                small: true,
                                onTap: () => setState(() {
                                  _selectedMovementType =
                                      _selectedMovementType == mt ? null : mt;
                                }),
                              )),
                    ],
                  ),
                ),
              ),
            const Divider(height: 1, color: Color(0xFF2A2A2A)),
            Expanded(
              child: ListView(
                key: ValueKey('$_openCategory/$_selectedMovementType/$_categorySearchQuery'),
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, MediaQuery.of(context).padding.bottom + 80),
                children: _buildExerciseTiles(
                    _exercisesForCategory(_openCategory!)),
              ),
            ),
          ] else
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 0, 16, MediaQuery.of(context).padding.bottom + 80),
              children: [
                // Упражнения в программе
                if (_visibleExercises.isNotEmpty) ...[
                  Text(
                    _selectedDay == null
                        ? 'В программе (${_programExercises.length})'
                        : 'В программе — ${_dayLabels[_selectedDay!]} (${_visibleExercises.length})',
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
                    onReorder: (oldIndex, newIndex) async {
                      // Indexes come from _visibleExercises; map them back to
                      // _programExercises so the day filter doesn't shift the
                      // wrong items around.
                      if (newIndex > oldIndex) newIndex--;
                      final movedItem = _visibleExercises[oldIndex];
                      final movedRealIdx =
                          _programExercises.indexOf(movedItem);
                      final WorkoutExercise? anchorItem =
                          newIndex < _visibleExercises.length
                              ? _visibleExercises[newIndex]
                              : null;
                      setState(() {
                        _programExercises.removeAt(movedRealIdx);
                        final insertIdx = anchorItem == null
                            ? _programExercises.length
                            : _programExercises.indexOf(anchorItem);
                        _programExercises.insert(
                            insertIdx < 0 ? _programExercises.length : insertIdx,
                            movedItem);
                      });
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await WorkoutService.reorderExercises(
                          widget.workoutId,
                          _programExercises.map((e) => e.id).toList(),
                        );
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                                content: Text('Не удалось сохранить порядок')),
                          );
                        }
                      }
                    },
                    children: _visibleExercises.asMap().entries.map((entry) {
                      final i = entry.key;
                      final we = entry.value;
                      final isLast = i == _visibleExercises.length - 1;
                      final nextWe = isLast ? null : _visibleExercises[i + 1];
                      final isLinkedWithNext = !isLast &&
                          we.supersetGroup != null &&
                          we.supersetGroup == nextWe?.supersetGroup;
                      final realIdx = _programExercises.indexOf(we);
                      return _ProgramExerciseCard(
                        key: ValueKey(we.id),
                        dragIndex: i,
                        workoutExercise: we,
                        supersetLabel: _supersetLabel(realIdx),
                        isLinkedWithNext: isLinkedWithNext,
                        canLink: !isLast,
                        isDropSet: we.isDropSet,
                        onToggleLink: () => _toggleSuperset(realIdx),
                        onToggleDropSet: () => _toggleDropSet(realIdx),
                        onEdit: () => _showExerciseSettingsSheet(
                          title: we.exercise?.displayName ?? '?',
                          gifUrl: we.exercise?.gifUrl,
                          description: we.exercise?.descriptionRu ?? we.exercise?.description,
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

                if (_searchQuery.isNotEmpty || _favoritesOnly) ...[
                  if (_filteredFlat.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              _favoritesOnly
                                  ? Icons.star_outline_rounded
                                  : Icons.search_off_rounded,
                              size: 40,
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _favoritesOnly
                                  ? 'Нет избранных упражнений.\nНажмите ⭐ на любом упражнении, чтобы добавить.'
                                  : 'Ничего не найдено',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._buildExerciseTiles(_filteredFlat),
                ] else
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
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter/sort helpers ──────────────────────────────────────────────────

  String? _keyForDisplayName(String displayName) {
    for (final (key, label) in _categoryChips) {
      if (label == displayName) return key;
    }
    return null;
  }

  /// Total exercises in category ignoring movement type filter.
  int _totalForCategory(String displayName) {
    final source = _favoritesOnly
        ? _allExercises.where((e) => e.isFavorite).toList()
        : _allExercises;
    return source
        .where((e) => Exercise.categoryDisplayName(e.category) == displayName)
        .length;
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool small = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(
            horizontal: small ? 10 : 14,
            vertical: small ? 4 : 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.15)
              : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: AppColors.accent, width: 1.2)
              : Border.all(color: Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: small ? 12 : 13,
            color: selected ? AppColors.accent : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  String _sortModeLabel(ExerciseSortMode mode) {
    switch (mode) {
      case ExerciseSortMode.alphabetical: return 'А–Я';
      case ExerciseSortMode.difficulty:   return 'Сложность';
      case ExerciseSortMode.popularity:   return 'Популярность';
      case ExerciseSortMode.userResults:  return 'Мой результат';
    }
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SortSheet(
        current: _sortMode,
        onSelect: (m) {
          setState(() => _sortMode = m);
          Navigator.pop(context);
        },
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
  final bool isDropSet;
  final VoidCallback onToggleLink;
  final VoidCallback onToggleDropSet;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProgramExerciseCard({
    super.key,
    required this.dragIndex,
    required this.workoutExercise,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleLink,
    required this.onToggleDropSet,
    this.supersetLabel,
    this.isLinkedWithNext = false,
    this.canLink = false,
    this.isDropSet = false,
  });

  @override
  Widget build(BuildContext context) {
    final we = workoutExercise;
    final isCardio = we.exercise?.category == 'cardio';
    final inSuperset = supersetLabel != null;

    // Murasaki (紫) — medium-dark Japanese purple
    const murasakiColor = Color(0xFF8B5EA8);

    // Build subtitle as InlineSpan list so weight can be colored separately
    final List<InlineSpan> subtitleSpans;
    const sep = TextSpan(
      text: '  •  ',
      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
    );
    if (isCardio) {
      subtitleSpans = [
        TextSpan(
          text: '${we.durationMinutes ?? 30} мин',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ];
    } else {
      subtitleSpans = [
        TextSpan(
          text: '${we.sets} подх. × ${we.repsRange} повт.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        sep,
        TextSpan(
          text: 'отдых ${we.restSeconds}с',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        if (we.targetWeight != null) ...[
          sep,
          TextSpan(
            text: '${we.targetWeight} кг',
            style: const TextStyle(
              color: murasakiColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (we.targetRpe != null) ...[
          sep,
          TextSpan(
            text: 'RPE ${we.targetRpe}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ];
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
                          we.exercise?.displayName ?? '?',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(children: subtitleSpans),
                        ),
                      ],
                    ),
                  ),
                  // Drop-set toggle
                  GestureDetector(
                    onTap: onToggleDropSet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: isDropSet
                            ? const Color(0xFFFF9500).withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDropSet
                              ? const Color(0xFFFF9500).withValues(alpha: 0.5)
                              : AppColors.textSecondary.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.trending_down_rounded,
                            size: 14,
                            color: isDropSet
                                ? const Color(0xFFFF9500)
                                : AppColors.textSecondary
                                    .withValues(alpha: 0.4),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Дроп',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDropSet
                                  ? const Color(0xFFFF9500)
                                  : AppColors.textSecondary
                                      .withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
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
                            isLinkedWithNext ? 'Суперсет' : 'Связать в супер-сет',
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
  final int count;
  final int totalCount; // unfiltered total (shown as "12/85" when filtered)
  final bool expanded;
  final bool filterVisible; // movement chips are shown
  final bool filterActive;  // a movement type is selected
  final bool searchVisible; // search field is shown
  final VoidCallback onToggle;
  final VoidCallback? onFilterToggle; // null = no filter button
  final VoidCallback? onSearchToggle; // null = no search button

  const _CategoryHeader({
    required this.label,
    required this.count,
    required this.expanded,
    required this.onToggle,
    this.totalCount = 0,
    this.filterVisible = false,
    this.filterActive = false,
    this.searchVisible = false,
    this.onFilterToggle,
    this.onSearchToggle,
  });

  @override
  Widget build(BuildContext context) {
    final showFiltered = filterActive && totalCount > 0 && count != totalCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Tap the label/count area to expand/collapse
          Expanded(
            child: GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    showFiltered ? '$count/$totalCount' : '$count',
                    style: TextStyle(
                      fontSize: 12,
                      color: filterActive
                          ? AppColors.accent.withValues(alpha: 0.7)
                          : AppColors.textSecondary.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Search toggle button
          if (onSearchToggle != null) ...[
            GestureDetector(
              onTap: onSearchToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: searchVisible
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
          // Filter toggle button (≡)
          if (onFilterToggle != null) ...[
            GestureDetector(
              onTap: onFilterToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: filterVisible || filterActive
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
          // Expand/collapse
          GestureDetector(
            onTap: onToggle,
            child: Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ],
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

// ─── История упражнения ──────────────────────────────────────────────────────

class _ExerciseHistorySheet extends StatefulWidget {
  final Exercise exercise;
  const _ExerciseHistorySheet({required this.exercise});

  @override
  State<_ExerciseHistorySheet> createState() => _ExerciseHistorySheetState();
}

class _ExerciseHistorySheetState extends State<_ExerciseHistorySheet> {
  Map<String, double>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await AnalyticsService.getExerciseMaxWeight(widget.exercise.id);
    if (mounted) setState(() => _data = d);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final sorted = data == null
        ? <MapEntry<String, double>>[]
        : (data.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));

    double? pb;
    String? pbDate;
    for (final e in sorted) {
      if (pb == null || e.value > pb) {
        pb = e.value;
        pbDate = e.key;
      }
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.exercise.displayName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Прогресс максимального веса',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            if (pb != null && pbDate != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.emoji_events_rounded,
                      color: Color(0xFFFFB800), size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Личный рекорд: ${pb % 1 == 0 ? pb.toInt() : pb.toStringAsFixed(1)} кг'
                    '  (${_fmtDate(pbDate)})',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: data == null
                  ? const Center(child: CircularProgressIndicator())
                  : sorted.isEmpty
                      ? const Center(
                          child: Text(
                            'Нет данных для отображения',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : LineChart(_buildChart(sorted)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _fmtDate(String iso) {
    final d = DateTime.parse(iso);
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  LineChartData _buildChart(List<MapEntry<String, double>> points) {
    final spots = points.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.value);
    }).toList();

    final maxY = points.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final minY = points.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    final pad = (maxY - minY) * 0.2;

    return LineChartData(
      minY: (minY - pad).clamp(0, double.infinity),
      maxY: maxY + pad,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (v, _) => Text(
              '${v.toInt()} кг',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: (points.length / 4).ceilToDouble().clamp(1, double.infinity),
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= points.length) return const SizedBox();
              final d = DateTime.parse(points[i].key);
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${d.day}.${d.month.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10),
                ),
              );
            },
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppColors.accent,
          barWidth: 2.5,
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: 4,
              color: AppColors.accent,
              strokeWidth: 0,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            color: AppColors.accent.withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }
}

// ─── Sort bottom sheet ────────────────────────────────────────────────────────

class _SortSheet extends StatelessWidget {
  final ExerciseSortMode current;
  final ValueChanged<ExerciseSortMode> onSelect;
  const _SortSheet({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const options = [
      (ExerciseSortMode.alphabetical,  Icons.sort_by_alpha_rounded,  'По алфавиту',      'А → Я'),
      (ExerciseSortMode.difficulty,    Icons.fitness_center_outlined, 'По сложности',     'начинающий → продвинутый'),
      (ExerciseSortMode.popularity,    Icons.trending_up_rounded,     'По популярности',  'чаще всего добавляемые'),
      (ExerciseSortMode.userResults,   Icons.emoji_events_outlined,   'По результату',    'лучший 1ПМ первым'),
    ];
    return SafeArea(
      top: false,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: AppColors.textSecondary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Сортировка',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        ...options.map((o) {
          final (mode, icon, title, sub) = o;
          final sel = current == mode;
          return ListTile(
            leading: Icon(icon,
                color: sel ? AppColors.accent : AppColors.textSecondary),
            title: Text(title,
                style: TextStyle(
                    color: sel ? AppColors.accent : AppColors.textPrimary,
                    fontWeight:
                        sel ? FontWeight.w600 : FontWeight.normal)),
            subtitle: Text(sub,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            trailing: sel
                ? const Icon(Icons.check_circle_rounded,
                    color: AppColors.accent, size: 20)
                : null,
            onTap: () => onSelect(mode),
          );
        }),
        const SizedBox(height: 16),
      ],
    ),
    );
  }
}
