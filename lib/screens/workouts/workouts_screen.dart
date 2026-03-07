import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/services/workout_service.dart';
import 'package:sportwai/screens/workouts/standard_workouts_screen.dart';

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({super.key});

  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Workout> _workouts = [];

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
    final list = await WorkoutService.getMyWorkouts();
    if (mounted) setState(() => _workouts = list);
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
  final VoidCallback onRefresh;
  final VoidCallback onCreateTap;
  final void Function(Workout) onWorkoutTap;
  final Future<void> Function(String id) onDelete;

  const _MyProgramsTab({
    required this.workouts,
    required this.onRefresh,
    required this.onCreateTap,
    required this.onWorkoutTap,
    required this.onDelete,
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

  List<Workout> get _sortedWorkouts {
    final Map<String, int> orderMap = {
      for (int i = 0; i < _orderedIds.length; i++) _orderedIds[i]: i,
    };
    return [...widget.workouts]..sort((a, b) {
        final ia = orderMap[a.id] ?? 999999;
        final ib = orderMap[b.id] ?? 999999;
        return ia.compareTo(ib);
      });
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

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedWorkouts;

    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        if (_openSwipeId != null) setState(() => _openSwipeId = null);
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async => widget.onRefresh(),
        child: ReorderableListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          buildDefaultDragHandles: false,
          onReorder: _onReorder,
          header: Column(
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
              if (sorted.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Пока нет программ.\nСоздайте первую!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
          children: [
            for (int i = 0; i < sorted.length; i++)
              ReorderableDelayedDragStartListener(
                key: ValueKey(sorted[i].id),
                index: i,
                child: _SwipeableCard(
                  workout: sorted[i],
                  isHidden: _hiddenIds.contains(sorted[i].id),
                  isOpen: _openSwipeId == sorted[i].id,
                  onOpen: () => _setOpen(sorted[i].id),
                  onClose: () => _setOpen(null),
                  onTap: () => widget.onWorkoutTap(sorted[i]),
                  onToggleHide: () => _toggleHidden(sorted[i].id),
                  onDelete: () => _confirmDelete(sorted[i]),
                ),
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
  final bool isHidden;
  final bool isOpen;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onTap;
  final VoidCallback onToggleHide;
  final VoidCallback onDelete;

  const _SwipeableCard({
    required this.workout,
    required this.isHidden,
    required this.isOpen,
    required this.onOpen,
    required this.onClose,
    required this.onTap,
    required this.onToggleHide,
    required this.onDelete,
  });

  @override
  State<_SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<_SwipeableCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  static const _actionWidth = 116.0;

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
                        child: _WorkoutCardContent(workout: widget.workout),
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

  const _ActionPanel({
    required this.width,
    required this.isHidden,
    required this.onToggleHide,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: AppColors.card,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Eye toggle
          GestureDetector(
            onTap: onToggleHide,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isHidden ? Icons.visibility_off : Icons.visibility,
                color: AppColors.textSecondary,
                size: 22,
              ),
            ),
          ),
          // Delete button
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Workout Card Content ─────────────────────────────────────────────────────

class _WorkoutCardContent extends StatelessWidget {
  final Workout workout;

  const _WorkoutCardContent({required this.workout});

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
          Icon(
            Icons.drag_handle,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
            size: 20,
          ),
        ],
      ),
    );
  }
}
