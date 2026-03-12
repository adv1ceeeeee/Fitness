import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/widgets/skeleton.dart';

// ─── Pure helpers (top-level for testability) ─────────────────────────────────

String formatSessionDuration(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  if (h > 0) return '$hч $mмин';
  return '$mмин';
}

String weekdayShort(int dartWeekday) {
  const days = ['', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  if (dartWeekday < 1 || dartWeekday > 7) return '';
  return days[dartWeekday];
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

const _kPageSize = 20;

class _HistoryScreenState extends State<HistoryScreen> {
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _hasMore = true; });
    final sessions = await TrainingService.getCompletedSessions(
        limit: _kPageSize, offset: 0);
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
        _hasMore = sessions.length == _kPageSize;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final more = await TrainingService.getCompletedSessions(
        limit: _kPageSize, offset: _sessions.length);
    if (mounted) {
      setState(() {
        _sessions.addAll(more);
        _loadingMore = false;
        _hasMore = more.length == _kPageSize;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История тренировок')),
      body: _loading
          ? const SingleChildScrollView(child: HistoryListSkeleton())
          : _sessions.isEmpty
              ? _EmptyHistory()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _sessions.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _sessions.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      final s = _sessions[i];
                      final prevDate = i > 0
                          ? _parseDate(_sessions[i - 1]['date'] as String)
                          : null;
                      final curDate = _parseDate(s['date'] as String);
                      final showMonth = prevDate == null ||
                          prevDate.month != curDate.month ||
                          prevDate.year != curDate.year;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showMonth) _MonthHeader(date: curDate),
                          _SessionCard(session: s),
                        ],
                      );
                    },
                  ),
                ),
    );
  }

  static DateTime _parseDate(String s) => DateTime.parse(s);
}

// ─── Month divider ─────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  final DateTime date;

  const _MonthHeader({required this.date});

  static const _months = [
    '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
      child: Text(
        '${_months[date.month]} ${date.year}',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Session card ──────────────────────────────────────────────────────────────

class _SessionCard extends StatefulWidget {
  final Map<String, dynamic> session;
  const _SessionCard({required this.session});

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _expanded = false;
  bool _loadingDetails = false;
  // grouped: exerciseName → list of completed sets
  List<_ExerciseSummary>? _details;

  Future<void> _toggle() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    setState(() => _expanded = true);
    if (_details != null) return; // already loaded
    setState(() => _loadingDetails = true);
    try {
      final sets = await TrainingService.getSessionSets(
          widget.session['id'] as String);
      final grouped = <String, _ExerciseSummary>{};
      for (final s in sets) {
        if (s['completed'] != true) continue;
        final ex = s['workout_exercises'] as Map<String, dynamic>?;
        final name =
            (ex?['exercises'] as Map<String, dynamic>?)?['name'] as String? ??
                'Упражнение';
        grouped.putIfAbsent(name, () => _ExerciseSummary(name));
        grouped[name]!.addSet(
          weight: (s['weight'] as num?)?.toDouble(),
          reps: s['reps'] as int?,
        );
      }
      if (mounted) {
        setState(() {
          _details = grouped.values.toList();
          _loadingDetails = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(widget.session['date'] as String);
    final workoutName =
        (widget.session['workouts'] as Map<String, dynamic>?)?['name']
                as String? ??
            'Тренировка';
    final durSec = widget.session['duration_seconds'] as int?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: _toggle,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Text(
                              '${date.day}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accent,
                              ),
                            ),
                            Text(
                              weekdayShort(date.weekday),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const VerticalDivider(width: 24, thickness: 1),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              workoutName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (durSec != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.timer_outlined,
                                      size: 13,
                                      color: AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    formatSessionDuration(durSec),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 280),
                        child: const Icon(Icons.keyboard_arrow_down_rounded,
                            color: AppColors.textSecondary, size: 20),
                      ),
                    ],
                  ),
                ),

                // ── Expanded details ────────────────────────────────────────
                if (_expanded) ...[
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.separator,
                    indent: 16,
                    endIndent: 16,
                  ),
                  if (_loadingDetails)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                          child:
                              CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (_details == null || _details!.isEmpty)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Text('Нет данных о подходах',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _details!.map((ex) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ex.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: ex.sets.asMap().entries.map((e) {
                                    final i = e.key + 1;
                                    final set = e.value;
                                    final label = set.weight != null &&
                                            set.reps != null
                                        ? '$i. ${set.weight!.toStringAsFixed(set.weight! % 1 == 0 ? 0 : 1)} кг × ${set.reps}'
                                        : set.reps != null
                                            ? '$i. ${set.reps} повт.'
                                            : '$i. —';
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Exercise summary helper ───────────────────────────────────────────────────

class _SetEntry {
  final double? weight;
  final int? reps;
  const _SetEntry({this.weight, this.reps});
}

class _ExerciseSummary {
  final String name;
  final List<_SetEntry> sets = [];
  _ExerciseSummary(this.name);
  void addSet({double? weight, int? reps}) =>
      sets.add(_SetEntry(weight: weight, reps: reps));
}

// ─── Empty state ───────────────────────────────────────────────────────────────

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 72, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'История пуста',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Завершите первую тренировку, чтобы она появилась здесь',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
