import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/workout.dart';
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
    if (_workouts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала создайте программу тренировок')),
      );
      return;
    }

    final events = _eventsFor(day);
    final cyclicEvent = events.where((e) => e.planned).firstOrNull;

    if (cyclicEvent != null) {
      // Conflict: a cyclic workout is already planned for this day
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
            await _pickAndSchedule(day);
          },
        ),
      );
    } else {
      await _pickAndSchedule(day);
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
                      // 2.5x bigger selected circle
                      selectedBuilder: (ctx, day, focused) =>
                          Transform.scale(
                        scale: 1.6,
                        child: _DayCell(
                          day: day,
                          events: _eventsFor(day),
                          isSelected: true,
                        ),
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

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Column(
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasCompleted)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.black
                          : AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                if (hasCompleted && hasPlanned)
                  const SizedBox(width: 2),
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
      ),
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
