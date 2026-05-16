import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/models/training_session.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/services/cache_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/notification_service.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/program_generator_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/workout_service.dart';
import 'package:sportwai/data/standard_programs.dart';
import 'package:sportwai/screens/workouts/generate_program_overlay.dart';
import 'package:sportwai/screens/workouts/generated_program_review_sheet.dart';
import 'package:sportwai/screens/workouts/quick_profile_wizard_sheet.dart';
import 'package:sportwai/screens/workouts/standard_workouts_screen.dart';
import 'package:sportwai/widgets/skeleton.dart';

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({super.key});

  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Workout> _workouts = [];
  Map<String, Map<String, dynamic>> _sessionInfo = {};
  Map<String, Map<String, dynamic>> _upcomingInfo = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadWorkouts();
  }

  void _onTabChanged() {
    // Refresh when switching back to "Мои программы" tab
    if (_tabController.index == 0 && !_tabController.indexIsChanging) {
      _loadWorkouts();
    }
  }

  /// Generates a workout program using profile data. If goal/level are missing,
  /// shows a quick wizard first; otherwise jumps straight to the loading
  /// animation. After generation we show a review sheet so the user can
  /// keep / regenerate / cancel before the draft commits to "Мои программы".
  Future<void> _runProgramGeneration() async {
    var profile = await ProfileService.getProfile();

    if (!ProgramGeneratorService.canGenerateFor(profile)) {
      if (!mounted) return;
      final answers = await QuickProfileWizardSheet.show(context, profile);
      if (answers == null) return; // user dismissed
      profile = (profile ??
              Profile(
                id: '',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ))
          .copyWith(goal: answers.goal, level: answers.level);
    }

    if (!mounted) return;
    final navigator = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Loop so the "Перегенерировать" button can re-enter the flow without
    // recursing or duplicating wizard logic.
    while (true) {
      if (!mounted) return;
      GeneratedProgram? result;
      try {
        result = await showGenerationOverlay<GeneratedProgram>(
          // ignore: use_build_context_synchronously
          context,
          message: 'Подбираем программу под вас',
          task: () => ProgramGeneratorService.generate(profile!),
        );
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Не удалось сгенерировать программу: $e')),
        );
        return;
      }

      if (!mounted) return;
      final action = await GeneratedProgramReviewSheet.show(
        // ignore: use_build_context_synchronously
        context,
        result,
      );

      if (action == GeneratedProgramAction.save) {
        EventLogger.workoutCreated(workoutName: result.firstWorkout.name);
        await _loadWorkouts();
        if (!mounted) return;
        navigator.push('/workouts/${result.firstWorkout.id}/exercises');
        return;
      }

      // Regenerate or Cancel — both delete the just-created draft so it does
      // not pollute "Мои программы". Run deletes in parallel for speed.
      await Future.wait(
        result.workouts.map((w) => WorkoutService.deleteWorkout(w.id)),
      );

      if (action == GeneratedProgramAction.cancel || action == null) {
        await _loadWorkouts();
        return;
      }
      // action == regenerate → loop again with the same profile.
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkouts() async {
    // Phase 1: show cache immediately if available
    final cached = await CacheService.loadWorkouts();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _workouts = cached;
        _loading = false;
      });
    }
    // Phase 2: refresh from network silently
    _refreshWorkouts();
  }

  Future<void> _refreshWorkouts() async {
    try {
      final list = await WorkoutService.getMyWorkouts()
          .timeout(const Duration(seconds: 15));
      final inactiveIds =
          list.where((w) => w.days.isEmpty).map((w) => w.id).toList();
      final results = await Future.wait([
        TrainingService.getLastSessionInfoForWorkouts(inactiveIds),
        TrainingService.getUpcomingSessionsForWorkouts(inactiveIds),
      ]);
      await CacheService.saveWorkouts(list);
      if (mounted) {
        setState(() {
          _workouts = list;
          _sessionInfo = results[0];
          _upcomingInfo = results[1];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Мои программы тренировок',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: AppColors.accent,
                    labelColor: AppColors.accent,
                    unselectedLabelColor: AppColors.textSecondary,
                    tabs: const [
                      Tab(text: 'Мои программы'),
                      Tab(text: 'Готовые'),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MyProgramsTab(
                    workouts: _workouts,
                    sessionInfo: _sessionInfo,
                    upcomingInfo: _upcomingInfo,
                    loading: _loading,
                    onRefresh: _loadWorkouts,
                    onDelete: (id) async {
                      // Optimistic: drop the row from the in-memory list
                      // immediately so the user sees the card disappear
                      // before the network round-trip completes. If the
                      // delete fails, _loadWorkouts() at the end re-syncs.
                      final messenger = ScaffoldMessenger.of(context);
                      final removed =
                          _workouts.where((w) => w.id == id).toList();
                      if (mounted) {
                        setState(() {
                          _workouts =
                              _workouts.where((w) => w.id != id).toList();
                        });
                      }
                      try {
                        await WorkoutService.deleteWorkout(id);
                      } catch (e) {
                        // Restore on failure so the user does not silently
                        // lose the workout from view while the row still
                        // exists in the DB.
                        if (mounted) {
                          setState(() {
                            _workouts = [..._workouts, ...removed];
                          });
                          messenger.showSnackBar(
                            SnackBar(content: Text('Ошибка удаления: $e')),
                          );
                        }
                      }
                      await _loadWorkouts();
                    },
                    onCreateTap: () async {
                      await context.push('/workouts/create');
                      _loadWorkouts();
                    },
                    onGenerateTap: _runProgramGeneration,
                    onWorkoutTap: (w) =>
                        context.push('/workouts/${w.id}/exercises'),
                  ),
                  StandardWorkoutsTab(
                    onProgramAdded: () {
                      _tabController.animateTo(0);
                      _refreshWorkouts();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── My Programs Tab ──────────────────────────────────────────────────────────

class _MyProgramsTab extends StatefulWidget {
  final List<Workout> workouts;
  final Map<String, Map<String, dynamic>> sessionInfo;
  final Map<String, Map<String, dynamic>> upcomingInfo;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onCreateTap;
  final VoidCallback onGenerateTap;
  final void Function(Workout) onWorkoutTap;
  final Future<void> Function(String id) onDelete;

  const _MyProgramsTab({
    required this.workouts,
    required this.sessionInfo,
    required this.upcomingInfo,
    required this.onRefresh,
    required this.onCreateTap,
    required this.onGenerateTap,
    required this.onWorkoutTap,
    required this.onDelete,
    this.loading = false,
  });

  @override
  State<_MyProgramsTab> createState() => _MyProgramsTabState();
}

class _MyProgramsTabState extends State<_MyProgramsTab> {
  List<String> _orderedIds = [];
  Set<String> _hiddenIds = {};
  String? _openSwipeId;

  // Multi-select delete mode
  bool _deleteMode = false;
  Set<String> _selectedIds = {};
  bool _inactiveDeleteMode = false;
  Set<String> _inactiveSelectedIds = {};

  static const _kOrder = 'workout_order';
  static const _kHidden = 'hidden_workout_ids';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _orderedIds = prefs.getStringList(_kOrder) ?? [];
      _hiddenIds = (prefs.getStringList(_kHidden) ?? []).toSet();
    });
  }

  Future<void> _saveOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kOrder, _orderedIds);
  }

  Future<void> _saveHidden() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kHidden, _hiddenIds.toList());
  }

  // Active programs (have scheduled days) — reorderable.
  // Sections of the same multi-section program are kept contiguous and sorted
  // by their first weekday (so Mon comes before Wed which comes before Fri),
  // regardless of the order they were created in.
  List<Workout> get _sortedWorkouts {
    final active = widget.workouts.where((w) => w.days.isNotEmpty).toList();
    final Map<String, int> orderMap = {
      for (int i = 0; i < _orderedIds.length; i++) _orderedIds[i]: i,
    };

    int minDay(Workout w) =>
        w.days.isEmpty ? 99 : w.days.reduce((a, b) => a < b ? a : b);

    // Bucket position of the group: the smallest user-drag rank of any of its
    // sections (so dragging any one section moves the whole group together);
    // un-ranked groups fall back to the smallest first-weekday in the group.
    String bucketKey(Workout w) => w.groupId ?? w.id;
    final groupRank = <String, int>{};
    final groupMinDay = <String, int>{};
    for (final w in active) {
      final k = bucketKey(w);
      final r = orderMap[w.id];
      if (r != null) {
        groupRank[k] = math.min(groupRank[k] ?? r, r);
      }
      final d = minDay(w);
      groupMinDay[k] = math.min(groupMinDay[k] ?? d, d);
    }

    return active
      ..sort((a, b) {
        final ka = bucketKey(a);
        final kb = bucketKey(b);
        if (ka != kb) {
          // Cross-group ordering: respect drag rank, then min weekday, then id.
          final ra = groupRank[ka];
          final rb = groupRank[kb];
          if (ra != null && rb != null && ra != rb) return ra.compareTo(rb);
          if (ra != null && rb == null) return -1;
          if (ra == null && rb != null) return 1;
          final cmp = (groupMinDay[ka] ?? 99).compareTo(groupMinDay[kb] ?? 99);
          if (cmp != 0) return cmp;
          return ka.compareTo(kb);
        }
        // Same group: ascending by first weekday so Mon → Wed → Fri.
        return minDay(a).compareTo(minDay(b));
      });
  }

  // Inactive workouts that have an upcoming (future, non-skipped) session
  /// Rest-only / no-active-days sections live as separate workouts in the DB
  /// (so the notification system can pick up their rest days), but they
  /// should never appear as standalone cards anywhere in the list — they
  /// belong to their parent program.
  ///
  /// Two ways a section can be a "rest companion":
  ///   1. days=[] AND restDays != [] (explicit rest day)
  ///   2. days=[] AND groupId != null (orphan section of a group, name like
  ///      "Отдых"). This catches the case the user just hit, where neither
  ///      array carries useful state but the row still belongs to a group.
  bool _isRestOnlySection(Workout w) =>
      w.days.isEmpty &&
      (w.restDays.isNotEmpty || w.groupId != null);

  List<Workout> get _upcomingWorkouts {
    return widget.workouts
        .where((w) =>
            w.days.isEmpty &&
            !_isRestOnlySection(w) &&
            widget.upcomingInfo.containsKey(w.id))
        .toList()
      ..sort((a, b) {
        final da = widget.upcomingInfo[a.id]?['date'] as String? ?? '';
        final db = widget.upcomingInfo[b.id]?['date'] as String? ?? '';
        return da.compareTo(db); // soonest first
      });
  }

  // One-time / inactive workouts (no scheduled days) — sorted by last session date
  List<Workout> get _inactiveWorkouts {
    final inactive = widget.workouts
        .where((w) =>
            w.days.isEmpty &&
            !_isRestOnlySection(w) &&
            !widget.upcomingInfo.containsKey(w.id))
        .toList();
    inactive.sort((a, b) {
      final da = widget.sessionInfo[a.id]?['date'] as String? ?? '';
      final db = widget.sessionInfo[b.id]?['date'] as String? ?? '';
      return db.compareTo(da); // most recent first
    });
    return inactive;
  }

  void _onReorder(int oldIndex, int newIndex) {
    final sorted = _sortedWorkouts;
    if (newIndex > oldIndex) newIndex--;
    final item = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, item);
    setState(() {
      _orderedIds = sorted.map((w) => w.id).toList();
      _openSwipeId = null;
    });
    _saveOrder();
  }

  /// Hide/show every section of a multi-section program in one go.
  /// Toggle direction is decided by the representative section (first id).
  void _toggleHiddenGroup(List<String> ids) {
    if (ids.isEmpty) return;
    final shouldHide = !_hiddenIds.contains(ids.first);
    setState(() {
      if (shouldHide) {
        _hiddenIds.addAll(ids);
      } else {
        _hiddenIds.removeAll(ids);
      }
      _openSwipeId = null;
    });
    _saveHidden();
  }

  void _setOpen(String? id) {
    if (_openSwipeId != id) setState(() => _openSwipeId = id);
  }

  void _enterDeleteMode() {
    setState(() {
      _deleteMode = true;
      _selectedIds = {};
      _openSwipeId = null;
    });
  }

  void _exitDeleteMode() {
    setState(() {
      _deleteMode = false;
      _selectedIds = {};
    });
  }

  void _enterInactiveDeleteMode() {
    setState(() {
      _inactiveDeleteMode = true;
      _inactiveSelectedIds = {};
    });
  }

  void _exitInactiveDeleteMode() {
    setState(() {
      _inactiveDeleteMode = false;
      _inactiveSelectedIds = {};
    });
  }

  void _toggleInactiveSelect(String id) {
    setState(() {
      if (_inactiveSelectedIds.contains(id)) {
        _inactiveSelectedIds.remove(id);
      } else {
        _inactiveSelectedIds.add(id);
      }
    });
  }

  void _toggleInactiveSelectAll() {
    final inactive = _inactiveWorkouts;
    setState(() {
      if (_inactiveSelectedIds.length == inactive.length) {
        _inactiveSelectedIds.clear();
      } else {
        _inactiveSelectedIds = inactive.map((w) => w.id).toSet();
      }
    });
  }

  Future<void> _confirmInactiveBulkDelete() async {
    final inactive = _inactiveWorkouts;
    final selected =
        inactive.where((w) => _inactiveSelectedIds.contains(w.id)).toList();
    if (selected.isEmpty) {
      _exitInactiveDeleteMode();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Удалить ${selected.length} ${_plural(selected.length, 'программу', 'программы', 'программ')}?',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: selected.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('• ${selected[i].name}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14)),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _exitInactiveDeleteMode();
    for (final w in selected) {
      await widget.onDelete(w.id);
    }
  }

  /// Select/unselect every section of a program at once. State is decided by
  /// whether the representative is currently selected.
  void _toggleSelectGroup(List<String> ids) {
    if (ids.isEmpty) return;
    final shouldSelect = !_selectedIds.contains(ids.first);
    setState(() {
      if (shouldSelect) {
        _selectedIds.addAll(ids);
      } else {
        _selectedIds.removeAll(ids);
      }
    });
  }

  void _toggleSelectAll() {
    final sorted = _sortedWorkouts;
    setState(() {
      if (_selectedIds.length == sorted.length) {
        _selectedIds.clear();
      } else {
        _selectedIds = sorted.map((w) => w.id).toSet();
      }
    });
  }

  Future<void> _confirmBulkDelete() async {
    final selected =
        _sortedWorkouts.where((w) => _selectedIds.contains(w.id)).toList();
    if (selected.isEmpty) {
      _exitDeleteMode();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Удалить ${selected.length} ${_plural(selected.length, 'программу', 'программы', 'программ')}?',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: selected.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '• ${selected[i].name}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Удалить', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final deletedIds = selected.map((w) => w.id).toSet();
    final messenger = ScaffoldMessenger.of(context);

    // Optimistic UI: hide rows immediately so the cards don't drop one-by-one
    // as each network call resolves.
    setState(() {
      _orderedIds.removeWhere(deletedIds.contains);
      _hiddenIds.removeWhere(deletedIds.contains);
      _selectedIds = {};
      _deleteMode = false;
      _openSwipeId = null;
    });

    try {
      await Future.wait(selected.map((w) {
        EventLogger.workoutDeleted(workoutName: w.name);
        return WorkoutService.deleteWorkout(w.id);
      }));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Ошибка удаления: $e')),
        );
      }
    }
    // Single refresh at the end — avoids N back-to-back reloads, which made
    // the list "blink" and items appear to disappear one-by-one.
    widget.onRefresh();
  }

  String _plural(int n, String one, String few, String many) {
    if (n % 10 == 1 && n % 100 != 11) return one;
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return few;
    }
    return many;
  }

  Future<void> _confirmDelete(Workout w) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Удалить программу?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(w.name,
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Отмена', style: TextStyle(color: AppColors.accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Удалить', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      EventLogger.workoutDeleted(workoutName: w.name);
      await widget.onDelete(w.id);
      if (mounted) {
        setState(() {
          _orderedIds.remove(w.id);
          _hiddenIds.remove(w.id);
          _openSwipeId = null;
        });
      }
    }
  }

  /// Group-aware variant — confirms once and deletes every section in the
  /// program. The N round-trips run in parallel (see WorkoutService.deleteWorkout).
  Future<void> _confirmDeleteGroup(List<String> ids) async {
    if (ids.isEmpty) return;
    if (ids.length == 1) {
      final w = widget.workouts.firstWhere((x) => x.id == ids.first);
      return _confirmDelete(w);
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Удалить программу?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Будут удалены все ${ids.length} ${_plural(ids.length, "день", "дня", "дней")} программы.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Отмена', style: TextStyle(color: AppColors.accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Удалить', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final idSet = ids.toSet();
    setState(() {
      _orderedIds.removeWhere(idSet.contains);
      _hiddenIds.removeWhere(idSet.contains);
      _openSwipeId = null;
    });
    try {
      await Future.wait(ids.map((id) {
        EventLogger.workoutDeleted(workoutName: id);
        return WorkoutService.deleteWorkout(id);
      }));
    } catch (_) {/* swallowed; widget.onRefresh below resyncs */}
    widget.onRefresh();
  }

  /// Archive every section in a program in one shot.
  Future<void> _archiveGroup(List<String> ids) async {
    if (ids.isEmpty) return;
    setState(() => _openSwipeId = null);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('В архив?'),
        content: Text(
          ids.length == 1
              ? 'Программа будет перенесена в архив. Вы сможете восстановить её, добавив дни тренировок.'
              : 'Все ${ids.length} ${_plural(ids.length, "день", "дня", "дней")} программы будут перенесены в архив.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('В архив',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await Future.wait(
          ids.map((id) => WorkoutService.updateWorkout(id, days: <int>[])));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Не удалось переместить в архив')),
        );
      }
    }
    widget.onRefresh();
  }

  Future<void> _duplicateWorkout(Workout w) async {
    setState(() => _openSwipeId = null);
    if (w.days.isEmpty) {
      await _scheduleOneTime(w);
    } else {
      await _copyActiveProgram(w);
    }
  }

  Future<void> _cancelUpcomingSession(Workout w) async {
    final sessionId = widget.upcomingInfo[w.id]?['session_id'] as String?;
    if (sessionId == null) return;
    try {
      // Cancel the notification first (best-effort)
      try {
        await NotificationService.cancelSessionNotification(sessionId);
      } catch (_) {}
      await TrainingService.deleteSession(sessionId);
      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Тренировка отменена')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WorkoutsScreen] _cancelUpcomingSession error: $e');
      }
    }
  }

  /// One-time workout → show date picker → schedule a new session.
  Future<void> _scheduleOneTime(Workout w) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Выберите дату тренировки',
      confirmText: 'Запланировать',
      cancelText: 'Отмена',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accent,
            surface: AppColors.card,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Время начала тренировки',
      cancelText: 'Без времени',
      confirmText: 'Выбрать',
    );
    if (!mounted) return;

    final TrainingSession session;
    try {
      session = await TrainingService.scheduleSession(
        w.id,
        picked,
        plannedTime: pickedTime,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[WorkoutsScreen] _scheduleOneTime error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось запланировать тренировку')),
        );
      }
      return;
    }

    // Notification is best-effort — failure must not block the success flow.
    if (pickedTime != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final mode = prefs.getString('notif_mode') ?? 'fixed';
        final minutesBefore =
            mode == 'before' ? (prefs.getInt('notif_minutes_before') ?? 30) : 0;
        await NotificationService.scheduleSessionNotification(
          sessionId: session.id,
          date: picked,
          plannedTime: pickedTime,
          workoutName: w.name,
          minutesBefore: minutesBefore,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[WorkoutsScreen] notification scheduling failed: $e');
        }
      }
    }

    if (mounted) {
      widget.onRefresh();
      final d =
          '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
      final t = pickedTime != null
          ? ' в ${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Запланировано на $d$t'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Active program → duplicate → check day conflicts → offer to replace.
  Future<void> _copyActiveProgram(Workout w) async {
    try {
      final copy = await WorkoutService.duplicateWorkout(w.id);

      // Find other active programs that share any days with the copy.
      final conflicting = widget.workouts
          .where((other) =>
              other.id != w.id &&
              other.days.isNotEmpty &&
              other.days.any((d) => copy.days.contains(d)))
          .toList();

      if (conflicting.isEmpty || !mounted) {
        widget.onRefresh();
        return;
      }

      final names = conflicting.map((c) => '"${c.name}"').join(', ');
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Конфликт расписания',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Text(
            'Новая программа пересекается по дням с: $names.\nЗаменить их на копию "${copy.name}"?',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Оставить обе',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Заменить',
                  style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      );

      if (replace == true) {
        for (final c in conflicting) {
          await WorkoutService.updateWorkout(c.id, days: []);
        }
      }
      widget.onRefresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось скопировать программу')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const WorkoutListSkeleton();

    final sorted = _sortedWorkouts;
    final upcoming = _upcomingWorkouts;
    final inactive = _inactiveWorkouts;
    // Count sections per group + collect day-of-week labels so the program
    // card can show "Программа · 6 дней · Пн, Ср, Пт" without us having to
    // re-traverse the workouts list inside the card widget.
    final groupSizes = <String, int>{};
    final groupDays = <String, List<int>>{};
    for (final w in sorted) {
      final key = w.groupId ?? w.id;
      groupSizes[key] = (groupSizes[key] ?? 0) + 1;
      (groupDays[key] ??= []).addAll(w.days);
    }
    int sizeOf(Workout w) => groupSizes[w.groupId ?? w.id] ?? 1;
    List<int> daysOf(Workout w) {
      final list = (groupDays[w.groupId ?? w.id] ?? const <int>[]).toList()
        ..sort();
      return list;
    }

    // Dedupe to one card per program. The representative is the section with
    // the smallest first weekday — already the first occurrence in `sorted`
    // because _sortedWorkouts sorts within a group by min day ascending.
    final seenGroupKeys = <String>{};
    final visible = <Workout>[];
    for (final w in sorted) {
      final key = w.groupId ?? w.id;
      if (seenGroupKeys.add(key)) visible.add(w);
    }
    // Build the set of all section ids belonging to a given representative.
    List<String> sectionIdsOf(Workout repr) {
      final key = repr.groupId ?? repr.id;
      return [
        for (final w in sorted)
          if ((w.groupId ?? w.id) == key) w.id,
      ];
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        if (_openSwipeId != null) setState(() => _openSwipeId = null);
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async => widget.onRefresh(),
        child: ReorderableListView(
          padding: EdgeInsets.fromLTRB(
              24, 0, 24, MediaQuery.of(context).padding.bottom + 100),
          buildDefaultDragHandles: false,
          onReorder: _onReorder,
          proxyDecorator: (child, index, animation) => Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: AppColors.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: widget.onCreateTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: AppColors.accent, size: 28),
                        SizedBox(width: 12),
                        Text(
                          'Создать программу',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: widget.onGenerateTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome,
                            color: AppColors.accent, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Сгенерировать программу',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (sorted.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Expanded(
                          child: Text(
                            'Действующие программы',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (_deleteMode)
                          GestureDetector(
                            onTap: _toggleSelectAll,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: _selectedIds.length == sorted.length
                                      ? AppColors.accent
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: _selectedIds.length == sorted.length
                                        ? AppColors.accent
                                        : AppColors.textSecondary,
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: _selectedIds.length == sorted.length
                                    ? const Icon(Icons.check,
                                        size: 13, color: AppColors.textOnAccent)
                                    : null,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _deleteMode
                              ? _confirmBulkDelete
                              : _enterDeleteMode,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: _deleteMode && _selectedIds.isNotEmpty
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (_deleteMode)
                          GestureDetector(
                            onTap: _exitDeleteMode,
                            child: const Padding(
                              padding:
                                  EdgeInsets.only(left: 8, top: 2, bottom: 2),
                              child: Icon(Icons.close,
                                  size: 18, color: AppColors.textSecondary),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      const Text(
                        'Удерживайте программу — история тренировок · Смахните влево — действия',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              if (sorted.isEmpty && inactive.isEmpty)
                SizedBox(
                  height: MediaQuery.of(context).size.height - 300,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.fitness_center_rounded,
                            size: 48,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Нет программ тренировок',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Создайте свою или выберите\nготовую во вкладке «Готовые»',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          footer: (upcoming.isEmpty && inactive.isEmpty)
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (upcoming.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Предстоящие',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        for (final w in upcoming)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _InactiveWorkoutCard(
                              workout: w,
                              upcomingDate:
                                  widget.upcomingInfo[w.id]?['date'] as String?,
                              upcomingSessionId: widget.upcomingInfo[w.id]
                                  ?['session_id'] as String?,
                              sessionDate:
                                  widget.sessionInfo[w.id]?['date'] as String?,
                              durationSeconds: widget.sessionInfo[w.id]
                                  ?['duration_seconds'] as int?,
                              onTap: () => widget.onWorkoutTap(w),
                              onDelete: () => _confirmDelete(w),
                              onCopy: () => _duplicateWorkout(w),
                              onCancelSession: () => _cancelUpcomingSession(w),
                            ),
                          ),
                      ],
                      if (inactive.isNotEmpty) ...[
                        Padding(
                          padding: EdgeInsets.only(
                              top: upcoming.isNotEmpty ? 8 : 0, bottom: 12),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Завершённые / неактивные',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              if (_inactiveDeleteMode)
                                GestureDetector(
                                  onTap: _toggleInactiveSelectAll,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 2),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: _inactiveSelectedIds.length ==
                                                inactive.length
                                            ? AppColors.accent
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: _inactiveSelectedIds.length ==
                                                  inactive.length
                                              ? AppColors.accent
                                              : AppColors.textSecondary,
                                          width: 1.5,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: _inactiveSelectedIds.length ==
                                              inactive.length
                                          ? const Icon(Icons.check,
                                              size: 13,
                                              color: AppColors.textOnAccent)
                                          : null,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _inactiveDeleteMode
                                    ? _confirmInactiveBulkDelete
                                    : _enterInactiveDeleteMode,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  child: Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: _inactiveDeleteMode &&
                                            _inactiveSelectedIds.isNotEmpty
                                        ? AppColors.error
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              if (_inactiveDeleteMode)
                                GestureDetector(
                                  onTap: _exitInactiveDeleteMode,
                                  child: const Padding(
                                    padding: EdgeInsets.only(
                                        left: 8, top: 2, bottom: 2),
                                    child: Icon(Icons.close,
                                        size: 18,
                                        color: AppColors.textSecondary),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        for (final w in inactive)
                          Padding(
                            key: ValueKey(w.id),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: _inactiveDeleteMode ? 36 : 0,
                                  alignment: Alignment.center,
                                  child: _inactiveDeleteMode
                                      ? GestureDetector(
                                          onTap: () =>
                                              _toggleInactiveSelect(w.id),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 150),
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              color: _inactiveSelectedIds
                                                      .contains(w.id)
                                                  ? AppColors.accent
                                                  : Colors.transparent,
                                              border: Border.all(
                                                color: _inactiveSelectedIds
                                                        .contains(w.id)
                                                    ? AppColors.accent
                                                    : AppColors.textSecondary,
                                                width: 1.5,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: _inactiveSelectedIds
                                                    .contains(w.id)
                                                ? const Icon(Icons.check,
                                                    size: 14,
                                                    color:
                                                        AppColors.textOnAccent)
                                                : null,
                                          ),
                                        )
                                      : null,
                                ),
                                Expanded(
                                  child: _InactiveWorkoutCard(
                                    workout: w,
                                    sessionDate: widget.sessionInfo[w.id]
                                        ?['date'] as String?,
                                    durationSeconds: widget.sessionInfo[w.id]
                                        ?['duration_seconds'] as int?,
                                    onTap: _inactiveDeleteMode
                                        ? () => _toggleInactiveSelect(w.id)
                                        : () => widget.onWorkoutTap(w),
                                    onDelete: () => _confirmDelete(w),
                                    onCopy: () => _duplicateWorkout(w),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
          children: [
            for (int i = 0; i < visible.length; i++)
              Padding(
                key: ValueKey(visible[i].groupId ?? visible[i].id),
                padding: const EdgeInsets.only(bottom: 0),
                child: Row(
                  children: [
                    // ── Checkbox (delete mode only) ──────────────────
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _deleteMode ? 36 : 0,
                      alignment: Alignment.center,
                      child: _deleteMode
                          ? GestureDetector(
                              onTap: () =>
                                  _toggleSelectGroup(sectionIdsOf(visible[i])),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: _selectedIds.contains(visible[i].id)
                                      ? AppColors.accent
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: _selectedIds.contains(visible[i].id)
                                        ? AppColors.accent
                                        : AppColors.textSecondary,
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: _selectedIds.contains(visible[i].id)
                                    ? const Icon(Icons.check,
                                        size: 14, color: AppColors.textOnAccent)
                                    : null,
                              ),
                            )
                          : null,
                    ),
                    // ── Card ─────────────────────────────────────────
                    Expanded(
                      child: _SwipeableCard(
                        workout: visible[i],
                        index: i,
                        groupSize: sizeOf(visible[i]),
                        groupDays: daysOf(visible[i]),
                        inDeleteMode: _deleteMode,
                        isHidden: _hiddenIds.contains(visible[i].id),
                        isOpen: !_deleteMode && _openSwipeId == visible[i].id,
                        onOpen: () => _setOpen(visible[i].id),
                        onClose: () => _setOpen(null),
                        onTap: _deleteMode
                            ? () => _toggleSelectGroup(sectionIdsOf(visible[i]))
                            : () => widget.onWorkoutTap(visible[i]),
                        onLongPress: () =>
                            _showWorkoutHistory(context, visible[i]),
                        onToggleHide: () =>
                            _toggleHiddenGroup(sectionIdsOf(visible[i])),
                        onDelete: () =>
                            _confirmDeleteGroup(sectionIdsOf(visible[i])),
                        onCopy: () => _duplicateWorkout(visible[i]),
                        onArchive: () =>
                            _archiveGroup(sectionIdsOf(visible[i])),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showWorkoutHistory(BuildContext context, Workout workout) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkoutHistorySheet(workout: workout),
    );
  }
}

// ─── Swipeable Card ───────────────────────────────────────────────────────────

class _SwipeableCard extends StatefulWidget {
  final Workout workout;
  final int index;
  final bool isHidden;
  final bool isOpen;
  final bool inDeleteMode;

  /// Total number of sections in this workout's program (1 = standalone).
  final int groupSize;

  /// All weekdays covered by the program across its sections (0=Mon…6=Sun).
  /// Empty list = inherit from workout.days only.
  final List<int> groupDays;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleHide;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onArchive;

  const _SwipeableCard({
    required this.workout,
    required this.index,
    required this.isHidden,
    required this.isOpen,
    this.inDeleteMode = false,
    this.groupSize = 1,
    this.groupDays = const [],
    required this.onOpen,
    required this.onClose,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleHide,
    required this.onDelete,
    required this.onCopy,
    required this.onArchive,
  });

  @override
  State<_SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<_SwipeableCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  static const _actionWidth = 208.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(_SwipeableCard old) {
    super.didUpdateWidget(old);
    if (!widget.isOpen && old.isOpen) {
      _ctrl.animateTo(0.0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = -details.delta.dx / _actionWidth;
    _ctrl.value = (_ctrl.value + delta).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (_ctrl.value > 0.4 || velocity < -300) {
      _ctrl.animateTo(1.0, duration: const Duration(milliseconds: 200));
      widget.onOpen();
    } else {
      _ctrl.animateTo(0.0, duration: const Duration(milliseconds: 200));
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final offset = -_anim.value * _actionWidth;
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // ── Action panel (revealed on swipe) ──────────────────────
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Opacity(
                      opacity: _anim.value.clamp(0.0, 1.0),
                      child: _ActionPanel(
                        width: _actionWidth,
                        isHidden: widget.isHidden,
                        onToggleHide: widget.onToggleHide,
                        onDelete: widget.onDelete,
                        onCopy: widget.onCopy,
                        onArchive: widget.onArchive,
                      ),
                    ),
                  ),
                ),

                // ── Sliding card (front) ───────────────────────────────────
                Transform.translate(
                  offset: Offset(offset, 0),
                  child: GestureDetector(
                    onTap: () {
                      if (widget.inDeleteMode) {
                        widget.onTap(); // in delete mode tap = toggle select
                        return;
                      }
                      if (widget.isOpen) {
                        _ctrl.animateTo(0.0,
                            duration: const Duration(milliseconds: 200));
                        widget.onClose();
                      } else {
                        widget.onTap();
                      }
                    },
                    onLongPress: widget.inDeleteMode
                        ? null
                        : () {
                            if (widget.isOpen) {
                              _ctrl.animateTo(0.0,
                                  duration: const Duration(milliseconds: 200));
                              widget.onClose();
                            }
                            widget.onLongPress();
                          },
                    onHorizontalDragUpdate:
                        widget.inDeleteMode ? null : _onDragUpdate,
                    onHorizontalDragEnd:
                        widget.inDeleteMode ? null : _onDragEnd,
                    child: Opacity(
                      opacity: widget.isHidden ? 0.5 : 1.0,
                      child: _WorkoutCardContent(
                        workout: widget.workout,
                        index: widget.index,
                        groupSize: widget.groupSize,
                        groupDays: widget.groupDays,
                        inDeleteMode: widget.inDeleteMode,
                        onActionsOpen: widget.inDeleteMode
                            ? null
                            : () {
                                if (widget.isOpen) {
                                  _ctrl.animateTo(0.0,
                                      duration:
                                          const Duration(milliseconds: 200));
                                  widget.onClose();
                                } else {
                                  _ctrl.animateTo(1.0,
                                      duration:
                                          const Duration(milliseconds: 250));
                                  widget.onOpen();
                                }
                              },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Action Panel ─────────────────────────────────────────────────────────────

class _ActionPanel extends StatelessWidget {
  final double width;
  final bool isHidden;
  final VoidCallback onToggleHide;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onArchive;

  const _ActionPanel({
    required this.width,
    required this.isHidden,
    required this.onToggleHide,
    required this.onDelete,
    required this.onCopy,
    required this.onArchive,
  });

  Widget _btn({
    required VoidCallback onTap,
    required IconData icon,
    required Color bg,
    Color iconColor = AppColors.textOnAccent,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same fill + radius as the card itself so the swipe-reveal looks like a
    // continuation of the card, not a separate rectangular drawer.
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _btn(
            onTap: onToggleHide,
            icon: isHidden ? Icons.visibility_off : Icons.visibility,
            bg: AppColors.textSecondary.withValues(alpha: 0.15),
            iconColor: AppColors.textSecondary,
          ),
          _btn(
            onTap: onArchive,
            icon: Icons.archive_outlined,
            bg: const Color(0xFFFF9500).withValues(alpha: 0.15),
            iconColor: const Color(0xFFFF9500),
          ),
          _btn(
            onTap: onCopy,
            icon: Icons.copy_rounded,
            bg: AppColors.accent.withValues(alpha: 0.15),
            iconColor: AppColors.accent,
          ),
          _btn(
            onTap: onDelete,
            icon: Icons.delete_outline,
            bg: AppColors.error,
          ),
        ],
      ),
    );
  }
}

// ─── Workout Card Content ─────────────────────────────────────────────────────

class _WorkoutCardContent extends StatelessWidget {
  final Workout workout;
  final int index;
  final VoidCallback? onActionsOpen;
  final bool inDeleteMode;

  /// Total sections in this workout's program (1 = standalone). When > 1 we
  /// show a "Программа · 6 дней · Пн, Ср, Пт" subtitle so the user can see at
  /// a glance that this card represents a multi-day split.
  final int groupSize;

  /// All weekdays covered by the program (across its sections), used to print
  /// the day labels in the subtitle for multi-section programs.
  final List<int> groupDays;

  const _WorkoutCardContent({
    required this.workout,
    required this.index,
    this.onActionsOpen,
    this.inDeleteMode = false,
    this.groupSize = 1,
    this.groupDays = const [],
  });

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  static String _pluralDays(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'день';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'дня';
    }
    return 'дней';
  }

  /// What to put under the card title:
  ///   • multi-section program → "Программа · N дней · Пн, Ср, Пт"
  ///   • single-section → "X тренировок в неделю"
  static String _subtitleFor(Workout w, int groupSize, List<int> groupDays) {
    if (groupSize > 1) {
      final daySet = (groupDays.isEmpty ? w.days : groupDays).toSet().toList()
        ..sort();
      final dayStr = daySet.map((d) => _dayLabels[d]).join(', ');
      final base = 'Программа · $groupSize ${_pluralDays(groupSize)}';
      return dayStr.isEmpty ? base : '$base · $dayStr';
    }
    return '${w.daysPerWeek} тренировок в неделю';
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = premiumWorkoutNames.contains(workout.name);
    final isUserCreated = !allStandardWorkoutNames.contains(workout.name);

    // icon tint: yellow=Pro, purple=user-created, blue=standard free
    const Color kPremiumColor = AppColors.favorite;
    const Color kUserColor = AppColors.metric;
    final Color iconColor = isPremium
        ? kPremiumColor
        : isUserCreated
            ? kUserColor
            : AppColors.accent;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder, width: 1),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Hero(
            tag: 'workout-icon-${workout.id}',
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.fitness_center_rounded,
                color: iconColor,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  // Show the parent program name when one is set for a
                  // multi-section group; otherwise fall back to the section
                  // name (current behaviour for legacy / single-section data).
                  groupSize > 1 && (workout.groupName?.isNotEmpty ?? false)
                      ? workout.groupName!
                      : workout.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _subtitleFor(workout, groupSize, groupDays),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (isPremium) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: kPremiumColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded,
                                size: 10, color: kPremiumColor),
                            SizedBox(width: 2),
                            Text(
                              'Pro',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: kPremiumColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          if (!inDeleteMode) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onActionsOpen,
              behavior: HitTestBehavior.opaque,
              child: ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Icon(
                    Icons.drag_handle,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                    size: 22,
                  ),
                ),
              ),
            ),
          ], // end if (!inDeleteMode)
        ],
      ),
    );
  }
}

// ─── Inactive / Completed Workout Card ───────────────────────────────────────

class _InactiveWorkoutCard extends StatelessWidget {
  final Workout workout;
  final String? sessionDate; // 'yyyy-MM-dd' — last completed session
  final String? upcomingDate; // 'yyyy-MM-dd' — next scheduled session
  final String? upcomingSessionId; // id of the upcoming session (to cancel)
  final int? durationSeconds;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback? onCancelSession;

  const _InactiveWorkoutCard({
    required this.workout,
    required this.onTap,
    required this.onDelete,
    required this.onCopy,
    this.sessionDate,
    this.upcomingDate,
    this.upcomingSessionId,
    this.durationSeconds,
    this.onCancelSession,
  });

  String _formatDate(String? raw) {
    if (raw == null || raw.length < 10) return '';
    // raw = 'yyyy-MM-dd'
    return '${raw.substring(8, 10)}.${raw.substring(5, 7)}.${raw.substring(0, 4)}';
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$hч $mмин';
    return '$mмин';
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatDate(sessionDate);
    final durStr = _formatDuration(durationSeconds);
    final hasInfo = dateStr.isNotEmpty || durStr.isNotEmpty;
    final isUpcoming = upcomingDate != null;
    final upcomingStr = _formatDate(upcomingDate);

    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isUpcoming
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.textSecondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isUpcoming
                      ? Icons.calendar_today_rounded
                      : Icons.event_note_rounded,
                  color:
                      isUpcoming ? AppColors.accent : AppColors.textSecondary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workout.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isUpcoming)
                      Text(
                        'Предстоит: $upcomingStr',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else if (hasInfo)
                      Text(
                        [dateStr, durStr]
                            .where((s) => s.isNotEmpty)
                            .join('  ·  '),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      )
                    else
                      const Text(
                        'Не завершена',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded,
                    color: AppColors.textSecondary, size: 20),
                onPressed: onCopy,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Повторить тренировку',
              ),
              if (onCancelSession != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined,
                      color: Color(0xFFFF9500), size: 20),
                  onPressed: onCancelSession,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Отменить',
                ),
              ],
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 20),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Workout History Sheet ────────────────────────────────────────────────────

class _WorkoutHistorySheet extends StatefulWidget {
  final Workout workout;
  const _WorkoutHistorySheet({required this.workout});

  @override
  State<_WorkoutHistorySheet> createState() => _WorkoutHistorySheetState();
}

class _WorkoutHistorySheetState extends State<_WorkoutHistorySheet> {
  bool _loading = true;
  int _totalSessions = 0;
  String? _firstDate;
  Map<int, Map<String, dynamic>> _byDay = {};

  static const _dayNames = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];
  static const _monthNames = [
    '',
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // For multi-section programs (group_id), aggregate history across ALL
      // sections — the sheet header shows the parent program name, so its
      // numbers should reflect the whole program, not just the one section
      // the user happened to long-press.
      final ids = widget.workout.groupId == null
          ? <String>[widget.workout.id]
          : (await WorkoutService.getSectionsByGroupId(widget.workout.groupId!))
              .map((w) => w.id)
              .toList();
      final data = await TrainingService.getWorkoutDayHistory(
          ids.isEmpty ? widget.workout.id : ids);
      if (!mounted) return;
      setState(() {
        _totalSessions = data['totalSessions'] as int;
        _firstDate = data['firstDate'] as String?;
        _byDay = Map<int, Map<String, dynamic>>.from(
          (data['byDay'] as Map).map((k, v) =>
              MapEntry(k as int, Map<String, dynamic>.from(v as Map))),
        );
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<int> get _activeDays {
    final scheduled = widget.workout.days.toSet();
    return _byDay.keys
        .where((d) => scheduled.isEmpty || scheduled.contains(d))
        .toList()
      ..sort();
  }

  String _fmtDate(String isoDate) {
    final d = DateTime.tryParse(isoDate);
    if (d == null) return isoDate;
    return '${d.day} ${_monthNames[d.month]}';
  }

  String _startedLabel() {
    if (_firstDate == null) return '';
    final d = DateTime.tryParse(_firstDate!);
    if (d == null) return '';
    final days = DateTime.now().difference(d).inDays;
    if (days == 0) return 'Начато сегодня';
    if (days < 7) return 'Начато $days дн. назад';
    final weeks = days ~/ 7;
    return 'Начато $weeks нед. назад';
  }

  double get _progressFraction {
    final daysPerWeek = widget.workout.days.length.clamp(1, 7);
    return _totalSessions / (8 * daysPerWeek);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // Prefer the parent program name for multi-section
                      // programs — the bottom sheet represents the whole
                      // program's history, not just the picked section.
                      widget.workout.groupName?.isNotEmpty == true
                          ? widget.workout.groupName!
                          : widget.workout.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!_loading)
                    Text(
                      '$_totalSessions трен.',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (!_loading) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(children: [
                        Container(height: 6, color: AppColors.surface),
                        FractionallySizedBox(
                          widthFactor: _progressFraction.clamp(0.0, 1.0),
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: LinearGradient(
                                colors: _progressFraction >= 1.0
                                    ? [
                                        AppColors.success,
                                        const Color(0xFF00D084)
                                      ]
                                    : [
                                        AppColors.accent,
                                        AppColors.accent.withValues(alpha: 0.7)
                                      ],
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          _startedLabel(),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const Spacer(),
                        _progressFraction >= 1.0
                            ? const Text('Цель выполнена',
                                style: TextStyle(
                                    color: AppColors.success,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600))
                            : Text(
                                '${(_progressFraction * 100).round()}% от 8 недель',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.surface, height: 24),
            ],
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _activeDays.isEmpty
                      ? const Center(
                          child: Text('Тренировок ещё не было',
                              style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          itemCount: _activeDays.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final day = _activeDays[i];
                            final info = _byDay[day]!;
                            return _DayPanel(
                              dayName: _dayNames[day],
                              sessionDate: _fmtDate(info['date'] as String),
                              rpe: info['rpe'] as int?,
                              durationSeconds: info['durationSeconds'] as int?,
                              exercises: (info['exercises'] as List)
                                  .cast<Map<String, dynamic>>(),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Day Panel ────────────────────────────────────────────────────────────────

class _DayPanel extends StatelessWidget {
  final String dayName;
  final String sessionDate;
  final int? rpe;
  final int? durationSeconds;
  final List<Map<String, dynamic>> exercises;

  const _DayPanel({
    required this.dayName,
    required this.sessionDate,
    required this.rpe,
    required this.durationSeconds,
    required this.exercises,
  });

  String _fmtDuration(int s) {
    final m = s ~/ 60;
    return m < 60 ? '$m мин' : '${m ~/ 60} ч ${m % 60} мин';
  }

  Color _rpeColor(int rpe) {
    if (rpe <= 5) return AppColors.success;
    if (rpe <= 7) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(dayName,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(sessionDate,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              if (durationSeconds != null && durationSeconds! > 0) ...[
                const SizedBox(width: 8),
                Text(_fmtDuration(durationSeconds!),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
              if (rpe != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _rpeColor(rpe!).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _rpeColor(rpe!).withValues(alpha: 0.4),
                        width: 1),
                  ),
                  child: Text('RPE $rpe',
                      style: TextStyle(
                          color: _rpeColor(rpe!),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
          if (exercises.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(color: AppColors.card, height: 1),
            const SizedBox(height: 8),
            for (final ex in exercises)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(ex['name'] as String? ?? '—',
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _exerciseStr(ex),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Нет данных о подходах',
                  style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.6),
                      fontSize: 12)),
            ),
        ],
      ),
    );
  }

  String _exerciseStr(Map<String, dynamic> ex) {
    final sets = ex['setCount'] as int;
    final reps = ex['lastReps'] as int;
    final weight = ex['maxWeight'] as double;
    final wStr =
        weight > 0 ? '  ${weight % 1 == 0 ? weight.toInt() : weight} кг' : '';
    return '$sets × $reps$wStr';
  }
}
