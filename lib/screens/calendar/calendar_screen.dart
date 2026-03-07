import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/services/exercise_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/workout_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  List<Workout> _workouts = [];
  bool _loading = true;

  Map<DateTime, List<_DayEvent>> _events = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final workouts = await WorkoutService.getMyWorkouts();
      final now = DateTime.now();
      final rangeStart = DateTime(now.year, now.month - 2, 1);
      final maxCycle =
          workouts.fold(0, (m, w) => w.cycleWeeks > m ? w.cycleWeeks : m);
      final rangeEnd =
          now.add(Duration(days: (maxCycle > 0 ? maxCycle : 16) * 7));

      final sessions =
          await TrainingService.getSessionsByDateRange(rangeStart, rangeEnd);

      final events = <DateTime, List<_DayEvent>>{};

      for (final s in sessions) {
        final d = _dayOnly(s.date);
        events.putIfAbsent(d, () => []).add(
              _DayEvent(workoutId: s.workoutId, completed: s.completed),
            );
      }

      for (final w in workouts) {
        if (w.days.isEmpty) continue;
        final cycleEnd = now.add(Duration(days: w.cycleWeeks * 7));
        var cursor = now;
        while (!cursor.isAfter(cycleEnd)) {
          final dayIndex = cursor.weekday - 1;
          if (w.days.contains(dayIndex)) {
            final d = _dayOnly(cursor);
            // Only hide cyclic if THIS workout already has a concrete session on this day
            final workoutHasSession =
                events[d]?.any((e) => e.workoutId == w.id && !e.planned) ??
                    false;
            if (!workoutHasSession) {
              final alreadyHas =
                  events[d]?.any((e) => e.workoutId == w.id && e.planned) ??
                      false;
              if (!alreadyHas) {
                events.putIfAbsent(d, () => []).add(
                      _DayEvent(workoutId: w.id, completed: false, planned: true),
                    );
              }
            }
          }
          cursor = cursor.add(const Duration(days: 1));
        }
      }

      if (mounted) {
        setState(() {
          _workouts = workouts;
          _events = events;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<_DayEvent> _eventsFor(DateTime day) =>
      _events[_dayOnly(day)] ?? [];

  void _onDaySelected(DateTime selected, DateTime focused) {
    setState(() {
      _selectedDay =
          (_selectedDay != null && isSameDay(_selectedDay!, selected))
              ? null
              : selected;
      _focusedDay = focused;
    });
  }

  Future<void> _addOnetimeSession(DateTime day) async {
    final events = _eventsFor(day);
    final cyclicEvent = events.where((e) => e.planned).firstOrNull;

    if (cyclicEvent != null) {
      final cyclicName = _workoutName(cyclicEvent.workoutId);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _ConflictAddSheet(
          cyclicName: cyclicName,
          onUseCyclic: () async {
            Navigator.pop(ctx);
            await _scheduleAndRefresh(cyclicEvent.workoutId, day);
          },
          onCreateOnetime: () async {
            Navigator.pop(ctx);
            await _pickOrBuildSession(day);
          },
        ),
      );
    } else {
      await _pickOrBuildSession(day);
    }
  }

  /// Shows either a two-option picker (from program / from exercises) or goes
  /// straight to the exercise builder if the user has no saved programs.
  Future<void> _pickOrBuildSession(DateTime day) async {
    if (_workouts.isNotEmpty) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => const _AddTypeSheet(),
      );
      if (!mounted || choice == null) return;
      if (choice == 'from_program') {
        await _pickAndSchedule(day);
      } else {
        await _buildAndSchedule(day);
      }
    } else {
      await _buildAndSchedule(day);
    }
  }

  Future<void> _pickAndSchedule(DateTime day) async {
    final workoutId = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _WorkoutPickerSheet(workouts: _workouts),
    );
    if (workoutId == null || !mounted) return;
    await _scheduleAndRefresh(workoutId, day);
  }

  Future<void> _buildAndSchedule(DateTime day) async {
    final workoutId = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ExerciseBuilderSheet(date: day),
    );
    if (workoutId == null || !mounted) return;
    // Session was already created inside the sheet; just reload
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Тренировка запланирована'),
        backgroundColor: Color(0xFF30D158),
        duration: Duration(seconds: 2),
      ),
    );
    await _load(silent: true);
  }

  Future<void> _scheduleAndRefresh(String workoutId, DateTime day) async {
    try {
      await TrainingService.scheduleSession(workoutId, day);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Тренировка запланирована'),
          backgroundColor: Color(0xFF30D158),
          duration: Duration(seconds: 2),
        ),
      );
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _showEditConflictSheet({
    required String sessionWorkoutId,
    required String programWorkoutId,
  }) async {
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Что изменить?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _ActionBtn(
              icon: Icons.calendar_month_outlined,
              label:
                  'Плановую по программе: ${_workoutName(programWorkoutId)}',
              onTap: () {
                Navigator.pop(ctx);
                context.push('/workouts/$programWorkoutId/exercises');
              },
            ),
            const SizedBox(height: 8),
            _ActionBtn(
              icon: Icons.fitness_center_outlined,
              label: 'Разовую: ${_workoutName(sessionWorkoutId)}',
              onTap: () {
                Navigator.pop(ctx);
                context.push('/workouts/$sessionWorkoutId/exercises');
              },
            ),
          ],
        ),
      ),
    );
  }

  String _workoutName(String workoutId) {
    try {
      return _workouts.firstWhere((w) => w.id == workoutId).name;
    } catch (_) {
      return 'Тренировка';
    }
  }

  Widget _buildActionButtons(DateTime day) {
    final events = _eventsFor(day);

    // разовая = actual DB session not yet completed
    final hasSession = events.any((e) => !e.planned && !e.completed);
    // программа = future weekly-schedule slot (no session row yet)
    final hasProgram = events.any((e) => e.planned);

    final sessionWorkoutId = hasSession
        ? events.firstWhere((e) => !e.planned && !e.completed).workoutId
        : null;
    final programWorkoutId = hasProgram
        ? events.firstWhere((e) => e.planned).workoutId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionBtn(
          icon: Icons.fitness_center_outlined,
          label: 'Добавить разовую тренировку',
          onTap: () => _addOnetimeSession(day),
        ),
        const SizedBox(height: 8),
        _ActionBtn(
          icon: Icons.calendar_month_outlined,
          label: 'Добавить программу тренировок',
          onTap: () => context.push('/workouts/create'),
        ),
        if (hasSession && hasProgram) ...[
          const SizedBox(height: 8),
          _ActionBtn(
            icon: Icons.edit_outlined,
            label: 'Изменить тренировку',
            accent: true,
            onTap: () => _showEditConflictSheet(
              sessionWorkoutId: sessionWorkoutId!,
              programWorkoutId: programWorkoutId!,
            ),
          ),
        ] else if (hasSession) ...[
          const SizedBox(height: 8),
          _ActionBtn(
            icon: Icons.edit_outlined,
            label: 'Изменить разовую тренировку',
            accent: true,
            onTap: () =>
                context.push('/workouts/$sessionWorkoutId/exercises'),
          ),
        ] else if (hasProgram) ...[
          const SizedBox(height: 8),
          _ActionBtn(
            icon: Icons.edit_calendar_outlined,
            label: 'Изменить программу тренировок',
            accent: true,
            onTap: () =>
                context.push('/workouts/$programWorkoutId/exercises'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Календарь',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TableCalendar<_DayEvent>(
                    firstDay: DateTime.now()
                        .subtract(const Duration(days: 365)),
                    lastDay:
                        DateTime.now().add(const Duration(days: 365)),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (d) =>
                        _selectedDay != null &&
                        isSameDay(d, _selectedDay!),
                    eventLoader: _eventsFor,
                    onDaySelected: _onDaySelected,
                    onPageChanged: (d) =>
                        setState(() => _focusedDay = d),
                    locale: 'ru_RU',
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      defaultTextStyle:
                          const TextStyle(color: AppColors.textPrimary),
                      weekendTextStyle:
                          const TextStyle(color: AppColors.textPrimary),
                      // Custom selectedBuilder overrides this, set transparent
                      selectedDecoration: const BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle:
                          const TextStyle(color: AppColors.textPrimary),
                      markerDecoration: const BoxDecoration(
                        color: Colors.transparent,
                      ),
                      markersMaxCount: 0,
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      leftChevronIcon: Icon(
                        Icons.chevron_left,
                        color: AppColors.textSecondary,
                      ),
                      rightChevronIcon: Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                      weekendStyle: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (ctx, day, focused) =>
                          _DayCell(day: day, events: _eventsFor(day)),
                      todayBuilder: (ctx, day, focused) => _DayCell(
                          day: day,
                          events: _eventsFor(day),
                          isToday: true),
                      selectedBuilder: (ctx, day, focused) => _DayCell(
                        day: day,
                        events: _eventsFor(day),
                        isSelected: true,
                      ),
                      outsideBuilder: (ctx, day, focused) =>
                          _DayCell(day: day, events: const [], outside: true),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Legend
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const _LegendDot(
                            color: AppColors.accent, label: 'Выполнено'),
                        const SizedBox(width: 16),
                        _LegendDot(
                          color:
                              AppColors.accent.withValues(alpha: 0.35),
                          label: 'Запланировано',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Buttons + events list
                  Expanded(
                    child: SingleChildScrollView(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      child: _selectedDay == null
                          ? (_workouts.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(32),
                                  child: Center(
                                    child: Text(
                                      'Создайте программу тренировок,\nчтобы видеть расписание',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: AppColors.textSecondary),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink())
                          : Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                _buildActionButtons(_selectedDay!),
                                if (_eventsFor(_selectedDay!)
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  ..._eventsFor(_selectedDay!).map(
                                      (ev) => Padding(
                                            padding:
                                                const EdgeInsets.only(
                                                    bottom: 8),
                                            child: _EventCard(
                                              name: _workoutName(
                                                  ev.workoutId),
                                              completed: ev.completed,
                                              planned: ev.planned,
                                              onTap: () => context.push(
                                                  '/workouts/${ev.workoutId}/exercises'),
                                            ),
                                          )),
                                ],
                              ],
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Модели ──────────────────────────────────────────────────────────────────

class _DayEvent {
  final String workoutId;
  final bool completed;
  final bool planned;

  const _DayEvent({
    required this.workoutId,
    required this.completed,
    this.planned = false,
  });
}

// ─── Action button ────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent
          ? AppColors.accent.withValues(alpha: 0.12)
          : AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: accent
                    ? AppColors.accent
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent
                        ? AppColors.accent
                        : AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: accent
                    ? AppColors.accent.withValues(alpha: 0.6)
                    : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Conflict sheet (cyclic + add one-time) ───────────────────────────────────

class _ConflictAddSheet extends StatelessWidget {
  final String cyclicName;
  final VoidCallback onUseCyclic;
  final VoidCallback onCreateOnetime;

  const _ConflictAddSheet({
    required this.cyclicName,
    required this.onUseCyclic,
    required this.onCreateOnetime,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'На этот день уже запланирована тренировка',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '«$cyclicName» по расписанию программы',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Material(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onUseCyclic,
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_outlined,
                        size: 20, color: AppColors.accent),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Использовать запланированную',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18, color: AppColors.accent),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onCreateOnetime,
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.fitness_center_outlined,
                        size: 20, color: AppColors.textSecondary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Создать разовую вместо неё',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Workout picker sheet ────────────────────────────────────────────────────

class _WorkoutPickerSheet extends StatelessWidget {
  final List<Workout> workouts;

  const _WorkoutPickerSheet({required this.workouts});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Выберите тренировку',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ...workouts.map(
            (w) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => Navigator.pop(context, w.id),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.fitness_center,
                            size: 18, color: AppColors.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            w.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 18,
                            color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add-type picker (from program vs from exercises) ────────────────────────

class _AddTypeSheet extends StatelessWidget {
  const _AddTypeSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Тип тренировки',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _sheetBtn(
            context,
            icon: Icons.calendar_month_outlined,
            label: 'Из программы тренировок',
            sub: 'Выбрать готовую программу',
            value: 'from_program',
          ),
          const SizedBox(height: 8),
          _sheetBtn(
            context,
            icon: Icons.fitness_center_outlined,
            label: 'Собрать из упражнений',
            sub: 'Выбрать упражнения вручную',
            value: 'from_exercises',
          ),
        ],
      ),
    );
  }

  Widget _sheetBtn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String sub,
    required String value,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => Navigator.pop(context, value),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        )),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        )),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Exercise builder sheet ───────────────────────────────────────────────────

class _ExerciseBuilderSheet extends StatefulWidget {
  final DateTime date;

  const _ExerciseBuilderSheet({required this.date});

  @override
  State<_ExerciseBuilderSheet> createState() => _ExerciseBuilderSheetState();
}

class _ExerciseBuilderSheetState extends State<_ExerciseBuilderSheet> {
  List<Exercise> _exercises = [];
  final Set<String> _selectedIds = {};
  bool _loading = true;
  bool _saving = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    final list = await ExerciseService.getExercises();
    if (mounted) setState(() { _exercises = list; _loading = false; });
  }

  List<Exercise> get _filtered {
    if (_search.isEmpty) return _exercises;
    final q = _search.toLowerCase();
    return _exercises.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _confirm() async {
    if (_selectedIds.isEmpty) return;
    setState(() => _saving = true);
    try {
      final workout = await WorkoutService.createWorkout(
        'Разовая тренировка',
        [],
        cycleWeeks: 0,
      );
      for (final id in _selectedIds) {
        await WorkoutService.addExerciseToWorkout(workout.id, id);
      }
      await TrainingService.scheduleSession(workout.id, widget.date);
      if (mounted) Navigator.pop(context, workout.id);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final byCategory = <String, List<Exercise>>{};
    for (final e in _filtered) {
      byCategory.putIfAbsent(e.category, () => []).add(e);
    }
    final categories = byCategory.keys.toList()..sort();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Выберите упражнения',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (_selectedIds.isNotEmpty)
                    Text(
                      '${_selectedIds.length} выбрано',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.accent,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Поиск упражнений...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.textSecondary, size: 20),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? const Center(
                          child: Text('Ничего не найдено',
                              style: TextStyle(
                                  color: AppColors.textSecondary)),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                          itemCount: categories.length,
                          itemBuilder: (_, i) {
                            final cat = categories[i];
                            final items = byCategory[cat]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    Exercise.categoryDisplayName(cat),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                ...items.map((ex) {
                                  final selected =
                                      _selectedIds.contains(ex.id);
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 6),
                                    child: Material(
                                      color: selected
                                          ? AppColors.accent
                                              .withValues(alpha: 0.12)
                                          : AppColors.surface,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      child: InkWell(
                                        onTap: () => setState(() {
                                          if (selected) {
                                            _selectedIds.remove(ex.id);
                                          } else {
                                            _selectedIds.add(ex.id);
                                          }
                                        }),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  ex.name,
                                                  style: TextStyle(
                                                    color: selected
                                                        ? AppColors.accent
                                                        : AppColors
                                                            .textPrimary,
                                                    fontWeight: selected
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                selected
                                                    ? Icons.check_circle
                                                    : Icons.circle_outlined,
                                                color: selected
                                                    ? AppColors.accent
                                                    : AppColors.textSecondary,
                                                size: 20,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                        ),
            ),
            // Confirm button
            Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 8, 24, MediaQuery.of(context).padding.bottom + 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      (_selectedIds.isEmpty || _saving) ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor:
                        AppColors.accent.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          _selectedIds.isEmpty
                              ? 'Выберите упражнения'
                              : 'Создать тренировку (${_selectedIds.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Виджеты ─────────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final DateTime day;
  final List<_DayEvent> events;
  final bool isToday;
  final bool isSelected;
  final bool outside;

  const _DayCell({
    required this.day,
    required this.events,
    this.isToday = false,
    this.isSelected = false,
    this.outside = false,
  });

  @override
  Widget build(BuildContext context) {
    Color? bgColor;
    if (isSelected) bgColor = AppColors.accent;
    if (isToday && !isSelected) {
      bgColor = AppColors.accent.withValues(alpha: 0.25);
    }

    final hasCompleted = events.any((e) => e.completed);
    final hasPlanned = events.any((e) => e.planned);

    // Selected circle is independently sized so the text stays at 14px
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${day.day}',
          style: TextStyle(
            fontSize: 14,
            color: outside
                ? AppColors.textSecondary.withValues(alpha: 0.4)
                : isSelected
                    ? Colors.black
                    : AppColors.textPrimary,
          ),
        ),
        if (hasCompleted || hasPlanned) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasCompleted)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.black : AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              if (hasCompleted && hasPlanned) const SizedBox(width: 2),
              if (hasPlanned && !hasCompleted)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.black.withValues(alpha: 0.5)
                        : AppColors.accent.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ],
      ],
    );

    if (isSelected) {
      return Center(
        child: Container(
          width: 50,
          height: 50,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: Center(child: content),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Center(child: content),
    );
  }
}

class _EventCard extends StatelessWidget {
  final String name;
  final bool completed;
  final bool planned;
  final VoidCallback onTap;

  const _EventCard({
    required this.name,
    required this.completed,
    required this.planned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: completed
                      ? AppColors.accent
                      : AppColors.accent.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      completed
                          ? 'Выполнено'
                          : planned
                              ? 'Запланировано'
                              : 'Не завершено',
                      style: TextStyle(
                        fontSize: 12,
                        color: completed
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}
