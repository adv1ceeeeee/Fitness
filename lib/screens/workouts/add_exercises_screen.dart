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
  'Грудь',
  'Спина',
  'Плечи',
  'Руки',
  'Ноги',
  'Кардио',
  'Пресс',
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
  bool _catalogLoading = false;
  // Guards _openWorkoutExerciseSettings against double-fire. The handler is
  // async (it may fetch the full exercise before opening the sheet), so a
  // quick second tap on the title / edit icon used to stack two identical
  // bottom sheets on top of each other.
  bool _openingExerciseSheet = false;
  String? _catalogLoadError;
  String? _loadError;
  Timer? _searchDebounce;
  String? _openCategory; // currently pinned/open category (single-expand)
  int? _selectedDay; // currently active day context for adding exercises
  // ── Filter & sort ──
  String?
      _selectedCategoryKey; // 'chest', 'back', etc. (derived from _openCategory)
  String? _selectedMovementType; // 'press', 'row', etc.
  bool _showMovementFilter =
      false; // movement chips visible inside expanded category
  bool _showCategorySearch = false; // search field inside expanded category
  String _categorySearchQuery = ''; // search query inside expanded category
  final TextEditingController _categorySearchController =
      TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  ExerciseSortMode _sortMode = ExerciseSortMode.alphabetical;
  Map<String, double> _userBest1RMs = {};
  Map<String, int> _popularity = {};
  List<WorkoutExercise> _copiedProgramExercises = [];
  WorkoutExercise? _copiedExercise;
  bool _pastingProgram = false;
  bool _pastingExercise = false;

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  /// Exercises filtered to the currently selected day.
  /// If no day is selected, shows all exercises (both day-assigned and unassigned).
  List<WorkoutExercise> get _visibleExercises {
    if (_selectedDay == null) return _programExercises;
    return _programExercises
        .where((e) => e.day == null || e.day == _selectedDay)
        .toList();
  }

  int get _currentCycleWeek => _workout?.currentCycleWeek() ?? 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AddExercisesScreen old) {
    super.didUpdateWidget(old);
    // GoRouter reuses this State when navigating between sections of the
    // same group (same route pattern, different :id param). We reset only
    // the UI-local state (search, open category) and trigger a background
    // reload — keeping `_workout`/`_programExercises` in place avoids a
    // full-screen loading spinner on every tab switch.
    if (old.workoutId != widget.workoutId) {
      _searchDebounce?.cancel();
      _searchController.clear();
      _categorySearchController.clear();
      setState(() {
        _searchQuery = '';
        _categorySearchQuery = '';
        _openCategory = null;
        _selectedCategoryKey = null;
        _selectedMovementType = null;
        _showMovementFilter = false;
        _showCategorySearch = false;
        _selectedDay = null;
      });
      _load();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _categorySearchController.dispose();
    _searchController.dispose();
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
    var list = _favoritesOnly
        ? _allExercises.where((e) => e.isFavorite).toList()
        : _allExercises;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              (e.nameRu?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    if (_selectedCategoryKey != null) {
      list = list.where((e) => e.category == _selectedCategoryKey).toList();
    }
    if (_selectedMovementType != null) {
      list = list
          .where((e) => e.effectiveMovementType == _selectedMovementType)
          .toList();
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
    final source = _favoritesOnly
        ? _allExercises.where((e) => e.isFavorite).toList()
        : _allExercises;
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
    // Show the loading skeleton only on initial load (no data yet).
    // For subsequent reloads (e.g. switching sections or post-add refresh)
    // keep showing the previous data so the screen does not blink.
    if (mounted && _workout == null) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final results = await Future.wait([
        WorkoutService.getWorkout(widget.workoutId),
        WorkoutService.getWorkoutExercises(widget.workoutId),
      ]).timeout(const Duration(seconds: 18));
      final w = results[0] as Workout?;
      final ex = results[1] as List<WorkoutExercise>;
      if (w == null) {
        throw StateError('Программа не найдена');
      }

      var sections = <Workout>[];
      if (w.groupId != null) {
        try {
          sections = await WorkoutService.getSectionsByGroupId(w.groupId!)
              .timeout(const Duration(seconds: 18));
        } catch (_) {
          sections = _groupSections;
        }
      }

      if (!mounted) return;
      setState(() {
        _workout = w;
        _programExercises = ex;
        _groupSections = sections.isNotEmpty ? sections : _groupSections;
        _loading = false;
        _loadError = null;
        // Auto-select when only one day in this section
        if (w.days.length == 1) _selectedDay = w.days.first;
      });

      _loadExerciseCatalog();
      _loadSortData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _loadExerciseCatalog() async {
    final cached = await ExerciseService.getCachedExercises();
    if (mounted && cached.isNotEmpty && _allExercises.isEmpty) {
      setState(() {
        _allExercises = cached;
        _catalogLoadError = null;
      });
      _loadFavoriteFlags();
    }

    if (mounted && _allExercises.isEmpty) {
      setState(() {
        _catalogLoading = true;
        _catalogLoadError = null;
      });
    }

    try {
      final all = await ExerciseService.getExercises()
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _allExercises = all;
        _catalogLoading = false;
        _catalogLoadError = null;
      });
      _loadFavoriteFlags();
    } catch (e) {
      if (mounted) {
        final fallback = ExerciseService.getLocalFallbackExercises();
        setState(() {
          if (_allExercises.isEmpty) {
            _allExercises = fallback;
            _catalogLoadError = null;
          } else {
            _catalogLoadError = e.toString();
          }
          _catalogLoading = false;
        });
      }
    }
  }

  Future<void> _loadFavoriteFlags() async {
    try {
      final favoriteIds = await ExerciseService.getFavoriteExerciseIds()
          .timeout(const Duration(seconds: 8));
      if (!mounted || favoriteIds.isEmpty) return;
      setState(() {
        _allExercises = [
          for (final exercise in _allExercises)
            exercise.copyWith(isFavorite: favoriteIds.contains(exercise.id)),
        ];
      });
    } catch (_) {}
  }

  void _loadSortData() {
    // Load sort data in background — only needed when user switches sort mode.
    ExerciseService.getBest1RMs()
        .timeout(const Duration(seconds: 12))
        .then((orms) {
      if (mounted) setState(() => _userBest1RMs = orms);
    }).catchError((_) {});
    ExerciseService.getPopularity()
        .timeout(const Duration(seconds: 12))
        .then((pop) {
      if (mounted) setState(() => _popularity = pop);
    }).catchError((_) {});
  }

  /// Returns label like "A1", "A2", "B1"... for exercises in a superset, or null.
  String? _supersetLabel(int index) {
    final g = _programExercises[index].supersetGroup;
    if (g == null) return null;
    if (_programExercises.where((e) => e.supersetGroup == g).length < 2) {
      return null;
    }
    // Collect unique groups in order of first appearance
    final seenGroups = <int>[];
    for (final we in _programExercises) {
      if (we.supersetGroup != null && !seenGroups.contains(we.supersetGroup)) {
        seenGroups.add(we.supersetGroup!);
      }
    }
    final groupLetter =
        String.fromCharCode('A'.codeUnitAt(0) + seenGroups.indexOf(g));
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
    final linked =
        a.supersetGroup != null && a.supersetGroup == b.supersetGroup;

    if (linked) {
      final group = a.supersetGroup;
      final remaining = _programExercises
          .where(
              (e) => e.supersetGroup == group && e.id != a.id && e.id != b.id)
          .toList();
      await Future.wait([
        WorkoutService.updateWorkoutExercise(a.id, supersetGroup: null),
        WorkoutService.updateWorkoutExercise(b.id, supersetGroup: null),
        if (remaining.length == 1)
          WorkoutService.updateWorkoutExercise(
            remaining.first.id,
            supersetGroup: null,
          ),
      ]);
      if (remaining.length == 1) {
        _showMessage('Суперсет развязан');
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  int? _targetDayForPaste() {
    if (_selectedDay != null) return _selectedDay;
    final days = _workout?.days ?? [];
    if (days.length == 1) return days.first;
    if (days.isEmpty) return null;
    return null;
  }

  void _copySelectedDayProgram() {
    final day = _selectedDay;
    if (day == null) {
      _showMessage('Выберите день, который нужно скопировать');
      return;
    }
    final source = _programExercises.where((e) => e.day == day).toList();
    if (source.isEmpty) {
      _showMessage('В этом дне пока нет упражнений');
      return;
    }
    setState(() {
      _copiedProgramExercises = List<WorkoutExercise>.from(source);
    });
    _showMessage('Программа на ${_dayLabels[day]} скопирована');
  }

  Future<void> _pasteCopiedDayProgram() async {
    if (_copiedProgramExercises.isEmpty) {
      _showMessage('Сначала скопируйте программу дня');
      return;
    }
    final targetDay = _targetDayForPaste();
    if ((_workout?.days.length ?? 0) > 1 && targetDay == null) {
      _showMessage('Выберите день, куда вставить программу');
      return;
    }

    final existingExerciseIds = _programExercises
        .where((e) => e.day == targetDay || e.day == null)
        .map((e) => e.exerciseId)
        .toSet();
    final sourceExercises = _copiedProgramExercises
        .where((e) => existingExerciseIds.add(e.exerciseId))
        .toList();
    if (sourceExercises.isEmpty) {
      _showMessage('Все упражнения уже есть в выбранном дне');
      return;
    }

    setState(() => _pastingProgram = true);
    final groupMap = <int, int>{};
    var nextGroup = _programExercises
            .map((e) => e.supersetGroup ?? 0)
            .fold<int>(0, (a, b) => a > b ? a : b) +
        1;

    try {
      for (final we in sourceExercises) {
        final sourceGroup = we.supersetGroup;
        int? pastedGroup;
        if (sourceGroup != null) {
          pastedGroup = groupMap.putIfAbsent(sourceGroup, () => nextGroup++);
        }
        await WorkoutService.addExerciseToWorkout(
          widget.workoutId,
          we.exerciseId,
          sets: we.sets,
          repsRange: we.repsRange,
          restSeconds: we.restSeconds,
          targetWeight: we.targetWeight,
          weeklyTargetWeights: we.weeklyTargetWeights,
          dropSetWeeklyTargetWeights: we.dropSetWeeklyTargetWeights,
          targetRpe: we.targetRpe,
          durationMinutes: we.durationMinutes,
          supersetGroup: pastedGroup,
          isDropSet: we.isDropSet,
          day: targetDay,
        );
      }
      await _load();
      if (mounted && targetDay != null) {
        final skipped = _copiedProgramExercises.length - sourceExercises.length;
        _showMessage(skipped > 0
            ? 'Вставлено: ${sourceExercises.length}, уже были: $skipped'
            : 'Вставлено в ${_dayLabels[targetDay]}');
      }
    } catch (_) {
      _showMessage('Не удалось вставить программу');
    } finally {
      if (mounted) setState(() => _pastingProgram = false);
    }
  }

  void _copyWorkoutExercise(WorkoutExercise we) {
    setState(() => _copiedExercise = we);
    _showMessage('Упражнение скопировано');
  }

  Future<void> _pasteCopiedExercise() async {
    final source = _copiedExercise;
    if (source == null) {
      _showMessage('Сначала скопируйте упражнение');
      return;
    }
    final targetDay = _targetDayForPaste();
    if ((_workout?.days.length ?? 0) > 1 && targetDay == null) {
      _showMessage('Выберите день, куда вставить упражнение');
      return;
    }
    final alreadyExists = _programExercises.any(
      (e) =>
          e.exerciseId == source.exerciseId &&
          (e.day == targetDay || e.day == null),
    );
    if (alreadyExists) {
      _showMessage('Это упражнение уже есть в выбранном дне');
      return;
    }

    setState(() => _pastingExercise = true);
    try {
      await WorkoutService.addExerciseToWorkout(
        widget.workoutId,
        source.exerciseId,
        sets: source.sets,
        repsRange: source.repsRange,
        restSeconds: source.restSeconds,
        targetWeight: source.targetWeight,
        weeklyTargetWeights: source.weeklyTargetWeights,
        dropSetWeeklyTargetWeights: source.dropSetWeeklyTargetWeights,
        targetRpe: source.targetRpe,
        durationMinutes: source.durationMinutes,
        isDropSet: source.isDropSet,
        day: targetDay,
      );
      await _load();
      _showMessage('Упражнение вставлено');
    } catch (_) {
      _showMessage('Не удалось вставить упражнение');
    } finally {
      if (mounted) setState(() => _pastingExercise = false);
    }
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
                      checkmarkColor: AppColors.textOnAccent,
                      labelStyle: TextStyle(
                        color: sel
                            ? AppColors.textOnAccent
                            : AppColors.textPrimary,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
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
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
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
                              style:
                                  const TextStyle(color: AppColors.textPrimary),
                              decoration:
                                  const InputDecoration(suffixText: 'нед.'),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(dctx),
                                  child: const Text('Отмена')),
                              TextButton(
                                onPressed: () {
                                  final v = int.tryParse(ctrl.text.trim());
                                  if (v != null && v >= 1) {
                                    Navigator.pop(dctx, v);
                                  }
                                },
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                        ctrl.dispose();
                        if (result != null) {
                          setDialogState(() => cycleWeeks = result);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
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
                        onChanged: (v) =>
                            setDialogState(() => cycleWeeks = v.round()),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('4 нед.',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                      Text('16 нед.',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
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
                        Icon(Icons.all_inclusive,
                            size: 16,
                            color: noCycle
                                ? AppColors.accent
                                : AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text('Без цикла',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: noCycle
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
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
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
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
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    _MinuteStepper(
                      value: cooldownMinutes,
                      onChanged: (v) =>
                          setDialogState(() => cooldownMinutes = v),
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
    Map<int, double> initialWeeklyTargetWeights = const {},
    Map<int, double> initialDropSetWeeklyTargetWeights = const {},
    required int initialDurationMinutes,
    required Future<void> Function(
            int sets,
            String repsRange,
            int rest,
            double? tw,
            int? durationMinutes,
            Map<int, double> weeklyTargetWeights,
            Map<int, double> dropSetWeeklyTargetWeights)
        onSave,
    required String saveLabel,
    String? gifUrl,
    String? description,
    bool showInfoTabs = false,
    int cycleWeeks = 0,
    int currentWeek = 1,
    bool isDropSet = false,
  }) {
    int sets = initialSets;
    int restSeconds = initialRest;
    double? targetWeight = initialTargetWeight;
    int durationMinutes = initialDurationMinutes;
    int activeTab = showInfoTabs ? 0 : 1;
    final totalWeeks = cycleWeeks <= 0 ? 1 : cycleWeeks;
    final safeCurrentWeek = currentWeek.clamp(1, totalWeeks).toInt();
    int selectedWeek = safeCurrentWeek;
    final weeklyTargetWeights =
        Map<int, double>.from(initialWeeklyTargetWeights);
    final dropSetWeeklyTargetWeights =
        Map<int, double>.from(initialDropSetWeeklyTargetWeights);
    final repsController = TextEditingController(text: initialRepsRange);
    final weightController = TextEditingController(
        text: targetWeight != null ? targetWeight.toString() : '');
    final weekWeightController = TextEditingController(
      text: weeklyTargetWeights[selectedWeek]?.toString() ?? '',
    );
    final dropSetWeekWeightController = TextEditingController(
      text: dropSetWeeklyTargetWeights[selectedWeek]?.toString() ?? '',
    );

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
                  decoration: const InputDecoration(
                      suffixText: 'сек.', hintText: 'Например: 150'),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dctx),
                      child: const Text('Отмена')),
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

          double? effectiveWeekWeight(int week) {
            final direct = weeklyTargetWeights[week];
            if (direct != null) return direct;
            for (var previousWeek = week - 1;
                previousWeek >= 1;
                previousWeek--) {
              final previous = weeklyTargetWeights[previousWeek];
              if (previous != null) return previous;
            }
            return targetWeight;
          }

          double? effectiveDropSetWeekWeight(int week) {
            final direct = dropSetWeeklyTargetWeights[week];
            if (direct != null) return direct;
            for (var previousWeek = week - 1;
                previousWeek >= 1;
                previousWeek--) {
              final previous = dropSetWeeklyTargetWeights[previousWeek];
              if (previous != null) return previous;
            }
            final mainWeight = effectiveWeekWeight(week);
            if (mainWeight == null) return null;
            return mainWeight * 0.6;
          }

          void commitSelectedWeekWeight() {
            final raw = weekWeightController.text.trim();
            if (raw.isEmpty) {
              weeklyTargetWeights.remove(selectedWeek);
              return;
            }
            final parsed = double.tryParse(raw.replaceAll(',', '.'));
            if (parsed == null) return;
            weeklyTargetWeights[selectedWeek] = parsed;

            if (isDropSet) {
              final dropRaw = dropSetWeekWeightController.text.trim();
              if (dropRaw.isEmpty) {
                dropSetWeeklyTargetWeights.remove(selectedWeek);
                return;
              }
              final dropParsed = double.tryParse(dropRaw.replaceAll(',', '.'));
              if (dropParsed != null) {
                dropSetWeeklyTargetWeights[selectedWeek] = dropParsed;
              }
            }
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
                  // Title row with a dedicated close button — without it the
                  // sheet has no obvious way to dismiss on desktop where
                  // swipe-down isn't a thing.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: AppColors.textSecondary),
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  if (showInfoTabs) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _SheetTabButton(
                            label: 'Описание',
                            selected: activeTab == 0,
                            onTap: () => setModalState(() => activeTab = 0),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SheetTabButton(
                            label: 'Прогресс',
                            selected: activeTab == 1,
                            onTap: () => setModalState(() => activeTab = 1),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (!showInfoTabs || activeTab == 0) ...[
                    if (gifUrl != null ||
                        (description != null && description.isNotEmpty)) ...[
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
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
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
                    ] else ...[
                      const SizedBox(height: 24),
                      const Center(
                        child: Text(
                          'Описание пока не добавлено',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (!showInfoTabs || activeTab == 1) ...[
                    const SizedBox(height: 20),
                    if (showInfoTabs && !isCardio) ...[
                      const Text(
                        'Прогресс за цикл программы',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Сейчас идет неделя $safeCurrentWeek из $totalWeeks',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(totalWeeks, (i) {
                            final week = i + 1;
                            final selected = selectedWeek == week;
                            final current = safeCurrentWeek == week;
                            final hasWeight =
                                weeklyTargetWeights.containsKey(week);
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    selectedWeek = week;
                                    weekWeightController.text =
                                        weeklyTargetWeights[week]?.toString() ??
                                            '';
                                    dropSetWeekWeightController.text =
                                        dropSetWeeklyTargetWeights[week]
                                                ?.toString() ??
                                            '';
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 11, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.accent
                                            .withValues(alpha: 0.18)
                                        : current
                                            ? AppColors.metric
                                                .withValues(alpha: 0.14)
                                            : AppColors.surface,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.accent
                                          : current
                                              ? AppColors.metric
                                              : hasWeight
                                                  ? AppColors.metric
                                                      .withValues(alpha: 0.55)
                                                  : Colors.transparent,
                                    ),
                                  ),
                                  child: Text(
                                    '$week',
                                    style: TextStyle(
                                      color: selected
                                          ? AppColors.accent
                                          : current
                                              ? AppColors.metric
                                              : AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: weekWeightController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: isDropSet
                              ? 'Основной вес на неделю $selectedWeek'
                              : 'Вес на неделю $selectedWeek',
                          suffixText: 'кг',
                          hintText: effectiveWeekWeight(selectedWeek) != null
                              ? effectiveWeekWeight(selectedWeek).toString()
                              : 'Например: 50',
                        ),
                        onChanged: (v) {
                          final parsed =
                              double.tryParse(v.replaceAll(',', '.'));
                          if (parsed == null) {
                            weeklyTargetWeights.remove(selectedWeek);
                          } else {
                            weeklyTargetWeights[selectedWeek] = parsed;
                          }
                        },
                      ),
                      if (isDropSet) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: dropSetWeekWeightController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Вес дроп-сета на неделю $selectedWeek',
                            suffixText: 'кг',
                            hintText:
                                effectiveDropSetWeekWeight(selectedWeek) != null
                                    ? effectiveDropSetWeekWeight(selectedWeek)
                                        .toString()
                                    : 'Например: 30',
                          ),
                          onChanged: (v) {
                            final parsed =
                                double.tryParse(v.replaceAll(',', '.'));
                            if (parsed == null) {
                              dropSetWeeklyTargetWeights.remove(selectedWeek);
                            } else {
                              dropSetWeeklyTargetWeights[selectedWeek] = parsed;
                            }
                          },
                        ),
                      ],
                      if (!weeklyTargetWeights.containsKey(selectedWeek) &&
                          effectiveWeekWeight(selectedWeek) != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          isDropSet
                              ? 'Показываются предыдущие веса: ${effectiveWeekWeight(selectedWeek)} кг / ${effectiveDropSetWeekWeight(selectedWeek)} кг'
                              : 'Показывается предыдущий вес: ${effectiveWeekWeight(selectedWeek)} кг',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
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
                          overlayColor:
                              AppColors.accent.withValues(alpha: 0.12),
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
                        decoration:
                            const InputDecoration(hintText: '8-12 или 5'),
                      ),
                      const SizedBox(height: 20),

                      // Целевой вес
                      const Text('Целевой вес (кг)',
                          style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: weightController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (v) {
                          targetWeight =
                              double.tryParse(v.replaceAll(',', '.'));
                        },
                        decoration:
                            const InputDecoration(hintText: 'Не обязательно'),
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
                                    fontSize: 13,
                                    color: AppColors.textSecondary)),
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
                            final sliderVal =
                                restSeconds.clamp(0, 120).toDouble();
                            final trackWidth =
                                constraints.maxWidth - sliderPadding * 2;
                            final thumbX = sliderPadding +
                                (sliderVal - min) / (max - min) * trackWidth;
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
                                      overlayColor: AppColors.accent
                                          .withValues(alpha: 0.12),
                                    ),
                                    child: Slider(
                                      value: sliderVal,
                                      min: min,
                                      max: max,
                                      divisions: 24,
                                      onChanged: (v) => setModalState(
                                          () => restSeconds = v.round()),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: thumbX - 24,
                                  top: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$restSeconds с',
                                      style: const TextStyle(
                                        color: AppColors.textOnAccent,
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
                            Text('0с',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                            Text('120с',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
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
                                color: AppColors.textSecondary
                                    .withValues(alpha: 0.5)),
                            const SizedBox(width: 4),
                            Text(
                              'Дважды нажмите на слайдер для ввода вручную',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary
                                      .withValues(alpha: 0.5)),
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
                            await onSave(
                              1,
                              '1',
                              0,
                              null,
                              durationMinutes,
                              const {},
                              const {},
                            );
                          } else {
                            if (showInfoTabs && !isCardio) {
                              commitSelectedWeekWeight();
                            }
                            await onSave(
                              sets,
                              repsController.text.trim().isNotEmpty
                                  ? repsController.text.trim()
                                  : '8-12',
                              restSeconds,
                              targetWeight,
                              null,
                              weeklyTargetWeights,
                              isDropSet ? dropSetWeeklyTargetWeights : const {},
                            );
                          }
                          _load();
                        },
                        child: Text(saveLabel),
                      ),
                    ),
                  ],
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
            child:
                const Text('Удалить', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ExerciseService.deleteExercise(ex.id);
      if (mounted) {
        setState(() => _allExercises.removeWhere((e) => e.id == ex.id));
      }
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
      source = source
          .where((e) => e.effectiveMovementType == _selectedMovementType)
          .toList();
    }
    if (_categorySearchQuery.isNotEmpty) {
      final q = _categorySearchQuery.toLowerCase();
      source = source
          .where((e) =>
              e.displayName.toLowerCase().contains(q) ||
              e.name.toLowerCase().contains(q))
          .toList();
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
      gifUrl: ex.primaryMediaUrl,
      description: ex.descriptionRu ?? ex.description,
      isCardio: ex.category == 'cardio',
      initialSets: 3,
      initialRepsRange: '8-12',
      initialRest: 90,
      initialTargetWeight: null,
      initialDurationMinutes: 30,
      saveLabel: 'Добавить в программу',
      onSave: (s, r, rest, tw, dur, weeklyWeights, dropSetWeeklyWeights) async {
        // ── Optimistic local insert ───────────────────────────────────────
        // Append to the bottom of the program list immediately so the user
        // sees the exercise without waiting for the DB round-trip. We give
        // it a temporary id (`tmp_…`) so the row is identifiable; the next
        // _load() will replace it with the canonical server row.
        final resolvedExercise = await ExerciseService.resolveExercise(ex)
            .timeout(const Duration(seconds: 8));
        if (resolvedExercise == null) {
          if (mounted) {
            _showMessage('Не удалось найти упражнение в каталоге');
          }
          return;
        }

        final tmpId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
        final maxExistingOrder = _programExercises
            .map((e) => e.order)
            .fold<int>(-1, (acc, o) => o > acc ? o : acc);
        final optimistic = WorkoutExercise(
          id: tmpId,
          workoutId: widget.workoutId,
          exerciseId: resolvedExercise.id,
          order: maxExistingOrder + 1,
          sets: s,
          repsRange: r,
          restSeconds: rest,
          targetWeight: tw,
          weeklyTargetWeights: weeklyWeights,
          dropSetWeeklyTargetWeights: dropSetWeeklyWeights,
          durationMinutes: dur,
          day: _selectedDay,
          exercise: resolvedExercise,
        );
        if (mounted) {
          _searchDebounce?.cancel();
          _searchController.clear();
          _categorySearchController.clear();
          setState(() {
            _programExercises = [..._programExercises, optimistic];
            _searchQuery = '';
            _categorySearchQuery = '';
            _openCategory = null;
            _selectedCategoryKey = null;
            _selectedMovementType = null;
            _showMovementFilter = false;
            _showCategorySearch = false;
          });
        }
        // ── Background DB write ───────────────────────────────────────────
        try {
          await WorkoutService.addExerciseToWorkout(
            widget.workoutId,
            resolvedExercise.id,
            sets: s,
            repsRange: r,
            restSeconds: rest,
            targetWeight: tw,
            weeklyTargetWeights: weeklyWeights,
            dropSetWeeklyTargetWeights: dropSetWeeklyWeights,
            durationMinutes: dur,
            day: _selectedDay,
          );
        } catch (_) {
          // Roll back the optimistic row if the DB write fails so the user
          // does not see an exercise that does not actually exist server-side.
          if (mounted) {
            setState(() {
              _programExercises =
                  _programExercises.where((e) => e.id != tmpId).toList();
            });
          }
        }
      },
    );
  }

  Future<void> _openWorkoutExerciseSettings(WorkoutExercise we) async {
    if (_openingExerciseSheet) return;
    _openingExerciseSheet = true;
    try {
      var exercise = we.exercise;
      if (exercise != null &&
          ((exercise.descriptionRu == null ||
                  exercise.descriptionRu!.isEmpty) &&
              (exercise.description == null ||
                  exercise.description!.isEmpty))) {
        try {
          final detailed = await ExerciseService.getExercise(
            exercise.id,
            includeDetails: true,
          ).timeout(const Duration(seconds: 8));
          if (detailed != null) exercise = detailed;
        } catch (_) {}
      }

      if (!mounted) return;
      await _showSettingsAndAwaitClose(exercise, we);
    } finally {
      _openingExerciseSheet = false;
    }
  }

  Future<void> _showSettingsAndAwaitClose(
      Exercise? exercise, WorkoutExercise we) async {
    _showExerciseSettingsSheet(
      title: exercise?.displayName ?? '?',
      gifUrl: exercise?.primaryMediaUrl,
      description: exercise?.descriptionRu ?? exercise?.description,
      isCardio: exercise?.category == 'cardio',
      initialSets: we.sets,
      initialRepsRange: we.repsRange,
      initialRest: we.restSeconds,
      initialTargetWeight: we.targetWeight,
      initialWeeklyTargetWeights: we.weeklyTargetWeights,
      initialDropSetWeeklyTargetWeights: we.dropSetWeeklyTargetWeights,
      initialDurationMinutes: we.durationMinutes ?? 30,
      saveLabel: 'Сохранить',
      showInfoTabs: true,
      cycleWeeks: _workout?.cycleWeeks ?? 0,
      currentWeek: _currentCycleWeek,
      isDropSet: we.isDropSet,
      onSave: (s, r, rest, tw, dur, weeklyWeights, dropSetWeeklyWeights) =>
          WorkoutService.updateWorkoutExercise(
        we.id,
        sets: s,
        repsRange: r,
        restSeconds: rest,
        targetWeight: tw,
        durationMinutes: dur,
        weeklyTargetWeights: weeklyWeights,
        dropSetWeeklyTargetWeights: dropSetWeeklyWeights,
      ),
    );
  }

  List<Widget> _buildExerciseTiles(List<Exercise> exercises) {
    return exercises
        .map((ex) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  onTap: () => _triggerAddExercise(ex),
                  onLongPress: () => _showExerciseHistory(ex),
                  leading: Icon(
                    ex.category == 'cardio'
                        ? Icons.directions_run
                        : Icons.fitness_center,
                    color: ex.isCustom
                        ? AppColors.accent.withValues(alpha: 0.75)
                        : AppColors.accent,
                  ),
                  title: Text(ex.displayName,
                      style: const TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text(
                    '${Exercise.categoryDisplayName(ex.category)}${ex.isCustom ? '  •  Моё' : ''}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          ex.isFavorite
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 20,
                          color: ex.isFavorite
                              ? AppColors.favorite
                              : AppColors.textSecondary,
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
            ))
        .toList();
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

    if (_loadError != null && _workout == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.background, elevation: 0),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    color: AppColors.error,
                    size: 42,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Не удалось открыть программу',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        ),
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
    if (catalogWidgets.isEmpty) {
      catalogWidgets.add(_CatalogStateCard(
        loading: _catalogLoading,
        error: _catalogLoadError,
        onRetry: _loadExerciseCatalog,
      ));
    }

    // Same color logic as program cards in workouts_screen
    const Color kPremiumColor = AppColors.favorite;
    const Color kUserColor = AppColors.metric;
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
        centerTitle: true,
        titleSpacing: 0,
        toolbarHeight: 72,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sectionTitle,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.15),
                  ),
                  if (days.isNotEmpty)
                    Text(
                      days.map((d) => _dayLabels[d]).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
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
      body: Builder(builder: (context) {
        // Rest-only section: skip the entire search/catalog UI — there's
        // nothing to add to a rest day. Show a centred breathing icon instead.
        final isRestOnlySection = workout != null &&
            workout.days.isEmpty &&
            (workout.restDays.isNotEmpty || workout.groupId != null);
        return Column(
        children: [
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
                    final dayLabel =
                        s.days.map((d) => _dayLabels[d]).join(', ');
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
                          color: isActive ? AppColors.accent : AppColors.card,
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
                                ? AppColors.textOnAccent
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // ── Day selector chips ────────────────────────────────────────────
          if (days.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('День: ',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                        ...days.map((d) {
                          final isSelected = _selectedDay == d;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () => setState(
                                  () => _selectedDay = isSelected ? null : d),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.surfacePressed
                                      : AppColors.card,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isSelected
                                      ? Border.all(color: AppColors.cardBorder)
                                      : null,
                                ),
                                child: Text(
                                  _dayLabels[d],
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? AppColors.textPrimary
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
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CopyPasteChip(
                        icon: Icons.content_copy_rounded,
                        label: 'Копировать',
                        onTap: _pastingProgram ? null : _copySelectedDayProgram,
                      ),
                      const SizedBox(width: 8),
                      _CopyPasteChip(
                        icon: Icons.content_paste_rounded,
                        label: 'Вставить',
                        onTap: _pastingProgram ? null : _pasteCopiedDayProgram,
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // ── Rest-day branch — replaces the whole catalog ────────────────────
          if (isRestOnlySection) ...[
            const Expanded(child: _RestDayPlaceholder()),
          ] else ...[
          // ── Поиск ───────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
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
                  labelPadding: const EdgeInsets.only(left: 2, right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  visualDensity:
                      const VisualDensity(horizontal: -4, vertical: -3),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: Icon(
                    _favoritesOnly
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 16,
                    color: _favoritesOnly
                        ? AppColors.textOnWarmAccent
                        : AppColors.textSecondary,
                  ),
                  selected: _favoritesOnly,
                  onSelected: (v) => setState(() => _favoritesOnly = v),
                  selectedColor: AppColors.favorite,
                  checkmarkColor: AppColors.textOnWarmAccent,
                  labelStyle: TextStyle(
                    color: _favoritesOnly
                        ? AppColors.textOnWarmAccent
                        : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  backgroundColor: AppColors.card,
                  showCheckmark: false,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _showSortSheet,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                onFilterToggle: () =>
                    setState(() => _showMovementFilter = !_showMovementFilter),
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
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            const Divider(height: 1, color: AppColors.separator),
            Expanded(
              child: ListView(
                key: ValueKey(
                    '$_openCategory/$_selectedMovementType/$_categorySearchQuery'),
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, MediaQuery.of(context).padding.bottom + 80),
                children:
                    _buildExerciseTiles(_exercisesForCategory(_openCategory!)),
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
                    SizedBox(
                      width: double.infinity,
                      child: _CopyPasteChip(
                        icon: Icons.content_paste_rounded,
                        label: 'Вставить скопированное упражнение',
                        fullWidth: true,
                        onTap: _pastingExercise || _copiedExercise == null
                            ? null
                            : _pasteCopiedExercise,
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
                              insertIdx < 0
                                  ? _programExercises.length
                                  : insertIdx,
                              movedItem);
                          _programExercises = [
                            for (var i = 0; i < _programExercises.length; i++)
                              _programExercises[i].copyWith(order: i),
                          ];
                        });
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await WorkoutService.reorderWorkoutExercises(
                            widget.workoutId,
                            _programExercises,
                          );
                        } catch (e) {
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Не удалось сохранить порядок')),
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
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(we.id),
                          index: i,
                          child: _ProgramExerciseCard(
                            dragIndex: i,
                            workoutExercise: we,
                            supersetLabel: _supersetLabel(realIdx),
                            isLinkedWithNext: isLinkedWithNext,
                            canLink: !isLast,
                            isDropSet: we.isDropSet,
                            onToggleLink: () => _toggleSuperset(realIdx),
                            onToggleDropSet: () => _toggleDropSet(realIdx),
                            onCopy: () => _copyWorkoutExercise(we),
                            currentWeek: _currentCycleWeek,
                            onEdit: () => _openWorkoutExerciseSettings(we),
                            onDelete: () async {
                              await WorkoutService.removeExerciseFromWorkout(
                                  we.id);
                              _load();
                            },
                          ),
                        );
                      }).toList(),
                    ),
                    const Divider(height: 24),
                  ],

                  if (_visibleExercises.isEmpty && _copiedExercise != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: _CopyPasteChip(
                        icon: Icons.content_paste_rounded,
                        label: 'Вставить скопированное упражнение',
                        fullWidth: true,
                        onTap: _pastingExercise ? null : _pasteCopiedExercise,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Добавить упражнение
                  Center(
                    child: Text(
                      _programExercises.isEmpty
                          ? 'Добавьте упражнения в программу'
                          : 'Добавить упражнение',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
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
                                    color: AppColors.textSecondary,
                                    fontSize: 13),
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
          ], // end of isRestOnlySection ? ... : <full catalog>
        ],
      );
      }),
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
            horizontal: small ? 10 : 14, vertical: small ? 4 : 6),
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
      case ExerciseSortMode.alphabetical:
        return 'А–Я';
      case ExerciseSortMode.difficulty:
        return 'Сложность';
      case ExerciseSortMode.popularity:
        return 'Популярность';
      case ExerciseSortMode.userResults:
        return 'Мой результат';
    }
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      useRootNavigator: true,
      isScrollControlled: true,
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
  final String? supersetLabel; // e.g. "A1", "A2"
  final bool isLinkedWithNext;
  final bool canLink;
  final bool isDropSet;
  final int currentWeek;
  final VoidCallback onToggleLink;
  final VoidCallback onToggleDropSet;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProgramExerciseCard({
    required this.dragIndex,
    required this.workoutExercise,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleLink,
    required this.onToggleDropSet,
    required this.onCopy,
    this.currentWeek = 1,
    this.supersetLabel,
    this.isLinkedWithNext = false,
    this.canLink = false,
    this.isDropSet = false,
  });

  String _compactTitle(String title) {
    final trimmed = title.trim();
    final paren = trimmed.indexOf(' (');
    if (trimmed.length > 22 && paren > 0) {
      return trimmed.substring(0, paren);
    }
    return trimmed;
  }

  String _formatWeight(double? weight, {bool drop = false}) {
    if (weight == null) return '';
    final value = drop ? weight * 0.6 : weight;
    if (value % 1 == 0) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }

  String _dropReps(String repsRange) {
    final values = RegExp(r'\d+')
        .allMatches(repsRange)
        .map((m) => int.tryParse(m.group(0)!))
        .whereType<int>()
        .toList();
    final top = values.isEmpty
        ? 12
        : values.reduce((a, b) => a > b ? a : b).clamp(12, 99);
    return '$top';
  }

  String _metricLine(WorkoutExercise we, {bool drop = false}) {
    if (we.exercise?.category == 'cardio') {
      return '${we.durationMinutes ?? 30} мин';
    }
    final reps = drop ? _dropReps(we.repsRange) : we.repsRange;
    final weight = _formatWeight(
      drop
          ? we.dropSetWeightForWeek(currentWeek)
          : we.weightForWeek(currentWeek),
    );
    // Old format "3X8-16X10" was ambiguous — the dash in the rep range
    // collided visually with the X separator. New format:
    //   "3 × 8-16 · 10 кг"   when weight is set
    //   "3 × 8-16"           bodyweight / no target weight
    final base = '${we.sets} × $reps';
    return weight.isEmpty ? base : '$base · $weight кг';
  }

  @override
  Widget build(BuildContext context) {
    final we = workoutExercise;
    final isCardio = we.exercise?.category == 'cardio';
    final inSuperset = supersetLabel != null;
    final title = _compactTitle(we.exercise?.displayName ?? '?');
    final mainLine = _metricLine(we);
    final dropLine = _metricLine(we, drop: true);

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
            height: isDropSet && !isCardio ? 148 : 124,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: inSuperset
                  ? Border(
                      left: BorderSide(color: supersetColor, width: 3),
                    )
                  : null,
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 12,
                  top: 12,
                  child: Container(
                    width: supersetLabel == null ? 26 : 32,
                    height: 26,
                    decoration: BoxDecoration(
                      color: supersetLabel == null
                          ? AppColors.surface
                          : supersetColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      supersetLabel ?? '${dragIndex + 1}',
                      style: TextStyle(
                        color: supersetLabel == null
                            ? AppColors.textSecondary
                            : supersetColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 52,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.tune,
                          color: AppColors.textSecondary, size: 22),
                      tooltip: 'Изменить',
                      onPressed: onEdit,
                    ),
                  ),
                ),
                Positioned(
                  left: 62,
                  right: 82,
                  top: 20,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onEdit,
                    child: Column(
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            height: 1.18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          mainLine,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.metric,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (isDropSet && !isCardio) ...[
                          const SizedBox(height: 3),
                          Text(
                            dropLine,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.metric,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.error, size: 24),
                    tooltip: 'Удалить',
                    onPressed: onDelete,
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 50,
                  child: GestureDetector(
                    onTap: onToggleDropSet,
                    child: Container(
                      width: 58,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isDropSet
                            ? const Color(0xFFFF9500).withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDropSet
                              ? const Color(0xFFFF9500).withValues(alpha: 0.55)
                              : AppColors.textSecondary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Icon(
                        Icons.trending_down_rounded,
                        size: 17,
                        color: isDropSet
                            ? const Color(0xFFFF9500)
                            : AppColors.textSecondary.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: IconButton(
                    icon: const Icon(Icons.content_copy_rounded,
                        color: AppColors.textSecondary, size: 21),
                    tooltip: 'Копировать упражнение',
                    onPressed: onCopy,
                  ),
                ),
              ],
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
                            isLinkedWithNext ? Icons.link : Icons.link_off,
                            size: 13,
                            color: isLinkedWithNext
                                ? supersetColor
                                : AppColors.textSecondary
                                    .withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isLinkedWithNext
                                ? 'Суперсет'
                                : 'Связать в супер-сет',
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

/// Placeholder shown in place of the exercises catalog when the user opens a
/// rest-only section ("Отдых"). Looped, low-key pulse so the screen reads as
/// "nothing to do here — recover".
class _RestDayPlaceholder extends StatefulWidget {
  const _RestDayPlaceholder();

  @override
  State<_RestDayPlaceholder> createState() => _RestDayPlaceholderState();
}

class _RestDayPlaceholderState extends State<_RestDayPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final scale = 0.92 + 0.16 * _ctrl.value;
                final glow = 0.10 + 0.10 * _ctrl.value;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(alpha: glow),
                    ),
                    child: Center(
                      child: Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent.withValues(alpha: 0.18),
                        ),
                        child: const Icon(
                          Icons.nightlight_round,
                          size: 40,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'День отдыха',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Восстанавливайся — сегодня без тренировки.\nСон, питание и лёгкая активность сделают своё.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary.withValues(alpha: 0.85),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyPasteChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool fullWidth;

  const _CopyPasteChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final content = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment:
          fullWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 15,
          color: enabled
              ? AppColors.textSecondary
              : AppColors.textSecondary.withValues(alpha: 0.35),
        ),
        const SizedBox(width: 5),
        if (fullWidth)
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: enabled
                    ? AppColors.textSecondary
                    : AppColors.textSecondary.withValues(alpha: 0.35),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: enabled
                  ? AppColors.textSecondary
                  : AppColors.textSecondary.withValues(alpha: 0.35),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled ? 1 : 0.65,
        child: Container(
          height: fullWidth ? 38 : 28,
          padding: EdgeInsets.symmetric(horizontal: fullWidth ? 12 : 9),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(fullWidth ? 10 : 8),
            border: Border.all(
              color: AppColors.textSecondary.withValues(alpha: 0.22),
            ),
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}

class _SheetTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SheetTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.16)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accent : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
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

// ─── Заголовок категории упражнений ──────────────────────────────────────────

class _CategoryHeader extends StatelessWidget {
  final String label;
  final int count;
  final int totalCount; // unfiltered total (shown as "12/85" when filtered)
  final bool expanded;
  final bool filterVisible; // movement chips are shown
  final bool filterActive; // a movement type is selected
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

class _CatalogStateCard extends StatelessWidget {
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  const _CatalogStateCard({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2D2D2D)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            Icon(
              hasError ? Icons.wifi_off_rounded : Icons.fitness_center_rounded,
              color: hasError ? AppColors.error : AppColors.textSecondary,
              size: 28,
            ),
          const SizedBox(height: 10),
          Text(
            loading
                ? 'Загружаю каталог упражнений'
                : hasError
                    ? 'Каталог не загрузился'
                    : 'Каталог упражнений пуст',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasError) ...[
            const SizedBox(height: 6),
            Text(
              error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ],
      ),
    );
  }
}

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
                      color: AppColors.favorite, size: 16),
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
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval:
                (points.length / 4).ceilToDouble().clamp(1, double.infinity),
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
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
      (
        ExerciseSortMode.alphabetical,
        Icons.sort_by_alpha_rounded,
        'По алфавиту',
        'А → Я'
      ),
      (
        ExerciseSortMode.difficulty,
        Icons.fitness_center_outlined,
        'По сложности',
        'начинающий → продвинутый'
      ),
      (
        ExerciseSortMode.popularity,
        Icons.trending_up_rounded,
        'По популярности',
        'чаще всего добавляемые'
      ),
      (
        ExerciseSortMode.userResults,
        Icons.emoji_events_outlined,
        'По результату',
        'лучший 1ПМ первым'
      ),
    ];
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
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
                  dense: true,
                  visualDensity:
                      const VisualDensity(horizontal: -2, vertical: -2),
                  minLeadingWidth: 28,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                  leading: Icon(icon,
                      color: sel ? AppColors.accent : AppColors.textSecondary),
                  title: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: sel ? AppColors.accent : AppColors.textPrimary,
                          fontWeight:
                              sel ? FontWeight.w600 : FontWeight.normal)),
                  subtitle: Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  trailing: sel
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppColors.accent, size: 20)
                      : null,
                  onTap: () => onSelect(mode),
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
