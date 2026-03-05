import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/training_session.dart';
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
  List<TrainingSession> _sessions = [];
  bool _loading = true;

  // date → список (workoutId, isCompleted)
  Map<DateTime, List<_DayEvent>> _events = {};

  // Double-tap detection
  DateTime? _lastTappedDay;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final workouts = await WorkoutService.getMyWorkouts();
    final now = DateTime.now();
    final rangeStart = DateTime(now.year, now.month - 2, 1);
    // будущее: берём макс. цикл среди программ (или 16 нед. по умолчанию)
    final maxCycle =
        workouts.fold(0, (m, w) => w.cycleWeeks > m ? w.cycleWeeks : m);
    final rangeEnd =
        now.add(Duration(days: (maxCycle > 0 ? maxCycle : 16) * 7));

    final sessions = await TrainingService.getSessionsByDateRange(
        rangeStart, rangeEnd);

    final events = <DateTime, List<_DayEvent>>{};

    // Прошедшие сессии из БД
    for (final s in sessions) {
      final d = _dayOnly(s.date);
      events.putIfAbsent(d, () => []).add(
            _DayEvent(workoutId: s.workoutId, completed: s.completed),
          );
    }

    // Будущие запланированные даты
    final sessionDays =
        sessions.map((s) => _dayOnly(s.date)).toSet();

    for (final w in workouts) {
      if (w.days.isEmpty) continue;
      final cycleEnd = now.add(Duration(days: w.cycleWeeks * 7));
      var cursor = now;
      while (!cursor.isAfter(cycleEnd)) {
        // 0=Пн … 6=Вс; Dart weekday: 1=Пн … 7=Вс
        final dayIndex = cursor.weekday - 1;
        if (w.days.contains(dayIndex)) {
          final d = _dayOnly(cursor);
          if (!sessionDays.contains(d)) {
            // Не дублируем, если уже есть событие от другой программы
            final existing = events[d];
            final alreadyHas =
                existing?.any((e) => e.workoutId == w.id) ?? false;
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
        _sessions = sessions;
        _events = events;
        _loading = false;
      });
    }
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<_DayEvent> _eventsFor(DateTime day) =>
      _events[_dayOnly(day)] ?? [];

  void _onDaySelected(DateTime selected, DateTime focused) {
    final now = DateTime.now();
    final isDoubleTap = _lastTappedDay != null &&
        isSameDay(_lastTappedDay!, selected) &&
        _lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 400;

    _lastTappedDay = selected;
    _lastTapTime = now;

    setState(() {
      _selectedDay = selected;
      _focusedDay = focused;
    });

    if (isDoubleTap) {
      _showDayActions(selected);
    }
  }

  void _showDayActions(DateTime day) {
    final events = _eventsFor(day);
    final isFuture = _dayOnly(day).isAfter(_dayOnly(DateTime.now()));
    final dateStr = '${day.day}.${day.month.toString().padLeft(2, '0')}.${day.year}';

    showModalBottomSheet(
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
            Text(
              dateStr,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // Существующие тренировки
            if (events.isNotEmpty) ...[
              const Text(
                'Тренировки',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              ...events.map((ev) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/workouts/${ev.workoutId}/exercises');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: ev.completed
                                      ? AppColors.accent
                                      : AppColors.accent.withValues(alpha: 0.45),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _workoutName(ev.workoutId),
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                              const Icon(Icons.tune,
                                  size: 18, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
              const SizedBox(height: 8),
            ],

            // Создать программу (всегда, если будущая дата или нет событий)
            if (isFuture || events.isEmpty)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/workouts/create');
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Создать программу'),
                ),
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
                    firstDay: DateTime.now().subtract(const Duration(days: 365)),
                    lastDay: DateTime.now().add(const Duration(days: 365)),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (d) =>
                        _selectedDay != null &&
                        isSameDay(d, _selectedDay!),
                    eventLoader: _eventsFor,
                    onDaySelected: _onDaySelected,
                    onPageChanged: (d) => setState(() => _focusedDay = d),
                    locale: 'ru_RU',
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      defaultTextStyle:
                          const TextStyle(color: AppColors.textPrimary),
                      weekendTextStyle:
                          const TextStyle(color: AppColors.textPrimary),
                      selectedDecoration: const BoxDecoration(
                        color: AppColors.accent,
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
                      weekdayStyle:
                          TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      weekendStyle:
                          TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (ctx, day, focused) =>
                          _DayCell(day: day, events: _eventsFor(day)),
                      todayBuilder: (ctx, day, focused) =>
                          _DayCell(day: day, events: _eventsFor(day), isToday: true),
                      selectedBuilder: (ctx, day, focused) =>
                          _DayCell(day: day, events: _eventsFor(day), isSelected: true),
                      outsideBuilder: (ctx, day, focused) =>
                          _DayCell(day: day, events: const [], outside: true),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Легенда
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const _LegendDot(color: AppColors.accent, label: 'Выполнено'),
                        const SizedBox(width: 16),
                        _LegendDot(
                          color: AppColors.accent.withValues(alpha: 0.35),
                          label: 'Запланировано',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Список событий выбранного дня
                  if (_selectedDay != null &&
                      _eventsFor(_selectedDay!).isNotEmpty)
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: _eventsFor(_selectedDay!).map((ev) {
                          return _EventCard(
                            name: _workoutName(ev.workoutId),
                            completed: ev.completed,
                            planned: ev.planned,
                            onTap: () => context
                                .push('/workouts/${ev.workoutId}/exercises'),
                          );
                        }).toList(),
                      ),
                    )
                  else if (_workouts.isEmpty && !_loading)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Создайте программу тренировок,\nчтобы видеть расписание',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
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
