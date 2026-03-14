import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/services/cache_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/notification_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/workout_service.dart';
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
    _loadWorkouts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkouts() async {
    setState(() => _loading = true);
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
      final cached = await CacheService.loadWorkouts();
      if (mounted) setState(() { _workouts = cached; _loading = false; });
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
                      await WorkoutService.deleteWorkout(id);
                      await _loadWorkouts();
                    },
                    onCreateTap: () async {
                      await context.push('/workouts/create');
                      _loadWorkouts();
                    },
                    onWorkoutTap: (w) =>
                        context.push('/workouts/${w.id}/exercises'),
                  ),
                  const StandardWorkoutsTab(),
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
      firstDate: now,
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

    try {
      final session = await TrainingService.scheduleSession(
        w.id, picked, plannedTime: pickedTime,
      );
      if (pickedTime != null) {
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
    } catch (e) {
      debugPrint('[WorkoutsScreen] _scheduleOneTime error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось запланировать тренировку')),
        );
      }
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
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
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
                              sessionDate: widget.sessionInfo[w.id]?['date'] as String?,
                              durationSeconds: widget.sessionInfo[w.id]?['duration_seconds'] as int?,
                              onTap: () => widget.onWorkoutTap(w),
                              onDelete: () => _confirmDelete(w),
                              onCopy: () => _duplicateWorkout(w),
                            ),
                          ),
                      ],
                      if (inactive.isNotEmpty) ...[
                        Padding(
                          padding: EdgeInsets.only(
                              top: upcoming.isNotEmpty ? 8 : 0, bottom: 12),
                          child: const Text(
                            'Завершённые / неактивные',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        for (final w in inactive)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _InactiveWorkoutCard(
                              workout: w,
                              sessionDate: widget.sessionInfo[w.id]?['date'] as String?,
                              durationSeconds: widget.sessionInfo[w.id]?['duration_seconds'] as int?,
                              onTap: () => widget.onWorkoutTap(w),
                              onDelete: () => _confirmDelete(w),
                              onCopy: () => _duplicateWorkout(w),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
          children: [
            for (int i = 0; i < sorted.length; i++)
              _SwipeableCard(
                key: ValueKey(sorted[i].id),
                workout: sorted[i],
                index: i,
                isHidden: _hiddenIds.contains(sorted[i].id),
                isOpen: _openSwipeId == sorted[i].id,
                onOpen: () => _setOpen(sorted[i].id),
                onClose: () => _setOpen(null),
                onTap: () => widget.onWorkoutTap(sorted[i]),
                onToggleHide: () => _toggleHidden(sorted[i].id),
                onDelete: () => _confirmDelete(sorted[i]),
                onCopy: () => _duplicateWorkout(sorted[i]),
                onArchive: () => _archiveWorkout(sorted[i]),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Swipeable Card ───────────────────────────────────────────────────────────

class _SwipeableCard extends StatefulWidget {
  final Workout workout;
  final int index;
  final bool isHidden;
  final bool isOpen;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onTap;
  final VoidCallback onToggleHide;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onArchive;

  const _SwipeableCard({
    super.key,
    required this.workout,
    required this.index,
    required this.isHidden,
    required this.isOpen,
    required this.onOpen,
    required this.onClose,
    required this.onTap,
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
            child: SizedBox(
              height: 96,
              child: Stack(
                children: [
                  // ── Action panel (revealed on swipe) ──────────────────────
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
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

                  // ── Sliding card (front) ───────────────────────────────────
                  Transform.translate(
                    offset: Offset(offset, 0),
                    child: GestureDetector(
                      onTap: () {
                        if (widget.isOpen) {
                          _ctrl.animateTo(0.0,
                              duration: const Duration(milliseconds: 200));
                          widget.onClose();
                        } else {
                          widget.onTap();
                        }
                      },
                      onHorizontalDragUpdate: _onDragUpdate,
                      onHorizontalDragEnd: _onDragEnd,
                      child: Opacity(
                        opacity: widget.isHidden ? 0.5 : 1.0,
                        child: _WorkoutCardContent(
                          workout: widget.workout,
                          index: widget.index,
                        ),
                      ),
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

  const _WorkoutCardContent({required this.workout, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.fitness_center_rounded,
              color: AppColors.accent,
              size: 28,
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
                Text(
                  '${workout.daysPerWeek} тренировок в неделю',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          ReorderableDragStartListener(
            index: index,
            child: Icon(
              Icons.drag_handle,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Inactive / Completed Workout Card ───────────────────────────────────────

class _InactiveWorkoutCard extends StatelessWidget {
  final Workout workout;
  final String? sessionDate;    // 'yyyy-MM-dd' — last completed session
  final String? upcomingDate;   // 'yyyy-MM-dd' — next scheduled session
  final int? durationSeconds;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onCopy;

  const _InactiveWorkoutCard({
    required this.workout,
    required this.onTap,
    required this.onDelete,
    required this.onCopy,
    this.sessionDate,
    this.upcomingDate,
    this.durationSeconds,
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
