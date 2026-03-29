import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/training_session.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/services/cache_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/notification_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/workout_service.dart';
import 'package:sportwai/data/standard_programs.dart';
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
      setState(() { _workouts = cached; _loading = false; });
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
                      Tab(text: 'Стандартные'),
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
                      try {
                        await WorkoutService.deleteWorkout(id);
                        await _loadWorkouts();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка удаления: $e')),
                          );
                        }
                      }
                    },
                    onCreateTap: () async {
                      await context.push('/workouts/create');
                      _loadWorkouts();
                    },
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
  final void Function(Workout) onWorkoutTap;
  final Future<void> Function(String id) onDelete;

  const _MyProgramsTab({
    required this.workouts,
    required this.sessionInfo,
    required this.upcomingInfo,
    required this.onRefresh,
    required this.onCreateTap,
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

  // Active programs (have scheduled days) — reorderable
  List<Workout> get _sortedWorkouts {
    final active = widget.workouts.where((w) => w.days.isNotEmpty).toList();
    final Map<String, int> orderMap = {
      for (int i = 0; i < _orderedIds.length; i++) _orderedIds[i]: i,
    };
    return active..sort((a, b) {
      final ia = orderMap[a.id] ?? 999999;
      final ib = orderMap[b.id] ?? 999999;
      return ia.compareTo(ib);
    });
  }

  // Inactive workouts that have an upcoming (future, non-skipped) session
  List<Workout> get _upcomingWorkouts {
    return widget.workouts
        .where((w) => w.days.isEmpty && widget.upcomingInfo.containsKey(w.id))
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
        .where((w) => w.days.isEmpty && !widget.upcomingInfo.containsKey(w.id))
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

  void _toggleHidden(String id) {
    setState(() {
      if (_hiddenIds.contains(id)) {
        _hiddenIds.remove(id);
      } else {
        _hiddenIds.add(id);
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
    if (selected.isEmpty) { _exitInactiveDeleteMode(); return; }

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

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
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
            child: const Text('Удалить',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await Future.wait(selected.map((w) {
        EventLogger.workoutDeleted(workoutName: w.name);
        return widget.onDelete(w.id);
      }));
      if (mounted) {
        setState(() {
          _orderedIds.removeWhere((id) => _selectedIds.contains(id));
          _hiddenIds.removeWhere((id) => _selectedIds.contains(id));
          _selectedIds = {};
          _deleteMode = false;
          _openSwipeId = null;
        });
      }
    }
  }

  String _plural(int n, String one, String few, String many) {
    if (n % 10 == 1 && n % 100 != 11) return one;
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return few;
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
            child: const Text('Отмена',
                style: TextStyle(color: AppColors.accent)),
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
      if (kDebugMode) debugPrint('[WorkoutsScreen] _cancelUpcomingSession error: $e');
    }
  }

  Future<void> _archiveWorkout(Workout w) async {
    setState(() => _openSwipeId = null);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('В архив?'),
        content: Text(
          'Программа «${w.name}» будет перенесена в архив. '
          'Вы сможете восстановить её, добавив дни тренировок.',
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
      await WorkoutService.updateWorkout(w.id, days: []);
      widget.onRefresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось переместить в архив')),
        );
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
        w.id, picked, plannedTime: pickedTime,
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
        if (kDebugMode) debugPrint('[WorkoutsScreen] notification scheduling failed: $e');
      }
    }

    if (mounted) {
      widget.onRefresh();
      final d = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
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

    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        if (_openSwipeId != null) setState(() => _openSwipeId = null);
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async => widget.onRefresh(),
        child: ReorderableListView(
          padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).padding.bottom + 100),
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
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                                      size: 13, color: Colors.white)
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
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                            padding: EdgeInsets.only(left: 8, top: 2, bottom: 2),
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
                          'Создайте свою или выберите\nготовую во вкладке «Стандартные»',
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
                              upcomingDate: widget.upcomingInfo[w.id]?['date'] as String?,
                              upcomingSessionId: widget.upcomingInfo[w.id]?['session_id'] as String?,
                              sessionDate: widget.sessionInfo[w.id]?['date'] as String?,
                              durationSeconds: widget.sessionInfo[w.id]?['duration_seconds'] as int?,
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
                                              size: 13, color: Colors.white)
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
                                                    color: Colors.white)
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
            for (int i = 0; i < sorted.length; i++)
              Padding(
                key: ValueKey(sorted[i].id),
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
                              onTap: () => _toggleSelect(sorted[i].id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: _selectedIds.contains(sorted[i].id)
                                      ? AppColors.accent
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: _selectedIds.contains(sorted[i].id)
                                        ? AppColors.accent
                                        : AppColors.textSecondary,
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: _selectedIds.contains(sorted[i].id)
                                    ? const Icon(Icons.check,
                                        size: 14, color: Colors.white)
                                    : null,
                              ),
                            )
                          : null,
                    ),
                    // ── Card ─────────────────────────────────────────
                    Expanded(
                      child: _SwipeableCard(
                        workout: sorted[i],
                        index: i,
                        inDeleteMode: _deleteMode,
                        isHidden: _hiddenIds.contains(sorted[i].id),
                        isOpen: !_deleteMode && _openSwipeId == sorted[i].id,
                        onOpen: () => _setOpen(sorted[i].id),
                        onClose: () => _setOpen(null),
                        onTap: _deleteMode
                            ? () => _toggleSelect(sorted[i].id)
                            : () => widget.onWorkoutTap(sorted[i]),
                        onLongPress: () => _showWorkoutHistory(context, sorted[i]),
                        onToggleHide: () => _toggleHidden(sorted[i].id),
                        onDelete: () => _confirmDelete(sorted[i]),
                        onCopy: () => _duplicateWorkout(sorted[i]),
                        onArchive: () => _archiveWorkout(sorted[i]),
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
                      onLongPress: widget.inDeleteMode ? null : () {
                        if (widget.isOpen) {
                          _ctrl.animateTo(0.0,
                              duration: const Duration(milliseconds: 200));
                          widget.onClose();
                        }
                        widget.onLongPress();
                      },
                      onHorizontalDragUpdate: widget.inDeleteMode ? null : _onDragUpdate,
                      onHorizontalDragEnd: widget.inDeleteMode ? null : _onDragEnd,
                      child: Opacity(
                        opacity: widget.isHidden ? 0.5 : 1.0,
                        child: _WorkoutCardContent(
                          workout: widget.workout,
                          index: widget.index,
                          inDeleteMode: widget.inDeleteMode,
                          onActionsOpen: widget.inDeleteMode ? null : () {
                            if (widget.isOpen) {
                              _ctrl.animateTo(0.0,
                                  duration: const Duration(milliseconds: 200));
                              widget.onClose();
                            } else {
                              _ctrl.animateTo(1.0,
                                  duration: const Duration(milliseconds: 250));
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

  Widget _btn({required VoidCallback onTap, required IconData icon, required Color bg, Color iconColor = Colors.white}) {
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
    return Container(
      width: width,
      color: AppColors.card,
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

  const _WorkoutCardContent({
    required this.workout,
    required this.index,
    this.onActionsOpen,
    this.inDeleteMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPremium = premiumWorkoutNames.contains(workout.name);
    final isUserCreated = !allStandardWorkoutNames.contains(workout.name);

    // icon tint: yellow=Pro, purple=user-created, blue=standard free
    const Color kPremiumColor = Color(0xFFFFB800);
    const Color kUserColor = Color(0xFFAB7FF8); // purple
    final Color iconColor = isPremium
        ? kPremiumColor
        : isUserCreated
            ? kUserColor
            : AppColors.accent;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
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
                  workout.name,
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
                        '${workout.daysPerWeek} тренировок в неделю',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (isPremium) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: kPremiumColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, size: 10, color: kPremiumColor),
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
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
  final String? sessionDate;      // 'yyyy-MM-dd' — last completed session
  final String? upcomingDate;     // 'yyyy-MM-dd' — next scheduled session
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
      borderRadius: BorderRadius.circular(16),
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
                  color: isUpcoming
                      ? AppColors.accent
                      : AppColors.textSecondary,
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
    'Понедельник', 'Вторник', 'Среда',
    'Четверг', 'Пятница', 'Суббота', 'Воскресенье',
  ];
  static const _monthNames = [
    '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await TrainingService.getWorkoutDayHistory(widget.workout.id);
      if (!mounted) return;
      setState(() {
        _totalSessions = data['totalSessions'] as int;
        _firstDate     = data['firstDate'] as String?;
        _byDay         = Map<int, Map<String, dynamic>>.from(
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
    if (days < 7)  return 'Начато $days дн. назад';
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
              width: 36, height: 4,
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
                      widget.workout.name,
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
                                    ? [AppColors.success, const Color(0xFF00D084)]
                                    : [AppColors.accent,
                                       AppColors.accent.withValues(alpha: 0.7)],
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
                                    color: AppColors.textSecondary, fontSize: 12)),
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
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final day  = _activeDays[i];
                            final info = _byDay[day]!;
                            return _DayPanel(
                              dayName:         _dayNames[day],
                              sessionDate:     _fmtDate(info['date'] as String),
                              rpe:             info['rpe'] as int?,
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
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
    final sets   = ex['setCount']  as int;
    final reps   = ex['lastReps']  as int;
    final weight = ex['maxWeight'] as double;
    final wStr   = weight > 0
        ? '  ${weight % 1 == 0 ? weight.toInt() : weight} кг'
        : '';
    return '$sets × $reps$wStr';
  }
}
