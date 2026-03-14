import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/providers/active_session_provider.dart';
import 'package:sportwai/services/notification_service.dart';
import 'package:sportwai/services/training_service.dart';

class SessionSummaryScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String workoutId;
  final int durationSeconds;

  const SessionSummaryScreen({
    super.key,
    required this.sessionId,
    required this.workoutId,
    required this.durationSeconds,
  });

  @override
  ConsumerState<SessionSummaryScreen> createState() =>
      _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends ConsumerState<SessionSummaryScreen> {
  bool _loading = true;
  bool _saving = false;
  double _totalVolume = 0;

  // Grouped exercise data: exerciseName → list of _SetRow
  final List<_ExerciseGroup> _groups = [];
  final TextEditingController _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSets();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSets() async {
    final rows = await TrainingService.getSessionSets(widget.sessionId);

    // Group by workoutExercise order
    final Map<String, _ExerciseGroup> map = {};

    for (final row in rows) {
      final weInfo =
          row['workout_exercises'] as Map<String, dynamic>? ?? {};
      final exInfo = weInfo['exercises'] as Map<String, dynamic>? ?? {};
      final exerciseName =
          exInfo['name'] as String? ?? 'Упражнение';
      final weOrder = weInfo['order'] as int? ?? 0;
      final key = '${weOrder}_$exerciseName';

      map.putIfAbsent(
        key,
        () => _ExerciseGroup(name: exerciseName, order: weOrder),
      );
      map[key]!.sets.add(_SetRow(
        id: row['id'] as String,
        setNumber: row['set_number'] as int? ?? 1,
        weight: (row['weight'] as num?)?.toDouble(),
        reps: row['reps'] as int?,
        rpe: row['rpe'] as int?,
        isWarmup: row['is_warmup'] as bool? ?? false,
      ));
    }

    final sorted = map.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    double vol = 0;
    for (final g in sorted) {
      for (final s in g.sets) {
        if (!s.isWarmup && s.weight != null && s.reps != null) {
          vol += s.weight! * s.reps!;
        }
      }
    }

    if (mounted) {
      setState(() {
        _groups
          ..clear()
          ..addAll(sorted);
        _totalVolume = vol;
        _loading = false;
      });
    }
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '$h ч $m мин $s сек';
    if (m > 0) return '$m мин $s сек';
    return '$s сек';
  }

  /// Returns sets that have no reps (null or 0) — grouped for display.
  List<String> _invalidSetDescriptions() {
    final result = <String>[];
    for (final group in _groups) {
      for (final set in group.sets) {
        if ((set.reps ?? 0) == 0) {
          result.add('${group.name}, подход ${set.setNumber}');
        }
      }
    }
    return result;
  }

  Future<bool> _confirmSaveWithWarnings(List<String> warnings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Не указаны повторения',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'В следующих подходах не указаны повторения:\n\n'
          '${warnings.join('\n')}\n\nСохранить всё равно?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить всё равно',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _save() async {
    // Validate before saving
    final warnings = _invalidSetDescriptions();
    if (warnings.isNotEmpty) {
      final proceed = await _confirmSaveWithWarnings(warnings);
      if (!proceed) return;
    }

    setState(() => _saving = true);
    try {
      // Update edited sets
      for (final group in _groups) {
        for (final set in group.sets) {
          await TrainingService.updateSet(
            set.id,
            weight: set.weight,
            reps: set.reps,
            rpe: set.rpe,
          );
        }
      }
      // Mark session complete
      await TrainingService.completeSession(
        widget.sessionId,
        durationSeconds: widget.durationSeconds,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      // Aggregate kcal and volume from individual sets and persist
      await TrainingService.saveSessionKcal(widget.sessionId);
      await TrainingService.saveSessionVolume(widget.sessionId);
      // Schedule inactivity reminder (fires in 3 days if no workout)
      NotificationService.scheduleInactivityReminder(daysLater: 3);
      // Clear global session state
      ref.read(activeSessionProvider.notifier).stop();
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _onWillPop() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Выйти без сохранения?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Данные тренировки будут потеряны.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      ref.read(activeSessionProvider.notifier).stop();
    }
    return confirm ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && context.mounted) context.go('/home');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Итоги тренировки'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) context.go('/home');
            },
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Duration card ──────────────────────────────────────
                  _SummaryHeader(
                    durationLabel: _formatDuration(widget.durationSeconds),
                    setsCount: _groups.fold(0, (s, g) => s + g.sets.length),
                    exercisesCount: _groups.length,
                    totalVolume: _totalVolume,
                  ),
                  const SizedBox(height: 20),
                  // ── Exercise groups ────────────────────────────────────
                  ..._groups.map((group) => _ExerciseCard(group: group)),
                  const SizedBox(height: 16),
                  // ── Notes ─────────────────────────────────────────────
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Заметки к тренировке (самочувствие, что помогло…)',
                      filled: true,
                      fillColor: AppColors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 24),
                  // ── Save button ────────────────────────────────────────
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Сохранить тренировку'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }
}

// ─── Data models ─────────────────────────────────────────────────────────────

class _ExerciseGroup {
  final String name;
  final int order;
  final List<_SetRow> sets;

  _ExerciseGroup({required this.name, required this.order})
      : sets = [];
}

class _SetRow {
  final String id;
  final int setNumber;
  double? weight;
  int? reps;
  int? rpe;
  final bool isWarmup;

  _SetRow({
    required this.id,
    required this.setNumber,
    this.weight,
    this.reps,
    this.rpe,
    this.isWarmup = false,
  });
}

// ─── Widgets ─────────────────────────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  final String durationLabel;
  final int setsCount;
  final int exercisesCount;
  final double totalVolume;

  const _SummaryHeader({
    required this.durationLabel,
    required this.setsCount,
    required this.exercisesCount,
    required this.totalVolume,
  });

  @override
  Widget build(BuildContext context) {
    final volLabel = totalVolume >= 1000
        ? '${(totalVolume / 1000).toStringAsFixed(1)} т'
        : '${totalVolume.toStringAsFixed(0)} кг';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events_rounded,
              color: AppColors.accent, size: 40),
          const SizedBox(height: 8),
          const Text(
            'Тренировка завершена!',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatChip(
                  icon: Icons.timer_outlined,
                  label: durationLabel,
                  title: 'Время'),
              _StatChip(
                  icon: Icons.fitness_center_rounded,
                  label: '$exercisesCount',
                  title: 'Упражнений'),
              _StatChip(
                  icon: Icons.repeat_rounded,
                  label: '$setsCount',
                  title: 'Подходов'),
              if (totalVolume > 0)
                _StatChip(
                    icon: Icons.bar_chart_rounded,
                    label: volLabel,
                    title: 'Объём'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String title;

  const _StatChip(
      {required this.icon, required this.label, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.accent, size: 22),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        Text(title,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

class _ExerciseCard extends StatefulWidget {
  final _ExerciseGroup group;

  const _ExerciseCard({required this.group});

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                widget.group.name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.surface),
            ...widget.group.sets.map((set) => _SetRowWidget(
                  set: set,
                  onChanged: () => setState(() {}),
                )),
          ],
        ),
      ),
    );
  }
}

class _SetRowWidget extends StatelessWidget {
  final _SetRow set;
  final VoidCallback onChanged;

  const _SetRowWidget({required this.set, required this.onChanged});

  void _editSet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SetEditSheet(set: set, onSave: onChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _editSet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: set.isWarmup
                    ? const Color(0xFFB8690A).withValues(alpha: 0.15)
                    : AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: set.isWarmup
                    ? const Icon(Icons.local_fire_department,
                        size: 15, color: Color(0xFFB8690A))
                    : Text(
                        '${set.setNumber}',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _label(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
            if (set.rpe != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'RPE ${set.rpe}',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.edit_outlined,
                size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  String _label() {
    final parts = <String>[];
    if (set.weight != null) {
      final w = set.weight! % 1 == 0
          ? '${set.weight!.toInt()} кг'
          : '${set.weight} кг';
      parts.add(w);
    }
    if (set.reps != null) parts.add('${set.reps} повт.');
    if (parts.isEmpty) return '—';
    return parts.join('  ×  ');
  }
}

// ─── Edit sheet ───────────────────────────────────────────────────────────────

class _SetEditSheet extends StatefulWidget {
  final _SetRow set;
  final VoidCallback onSave;

  const _SetEditSheet({required this.set, required this.onSave});

  @override
  State<_SetEditSheet> createState() => _SetEditSheetState();
}

class _SetEditSheetState extends State<_SetEditSheet> {
  late TextEditingController _weightCtrl;
  late TextEditingController _repsCtrl;
  int? _rpe;

  static const _rpeOptions = [null, 6, 7, 8, 9, 10];

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController(
        text: widget.set.weight != null
            ? widget.set.weight!.toStringAsFixed(
                widget.set.weight! % 1 == 0 ? 0 : 1)
            : '');
    _repsCtrl = TextEditingController(
        text: widget.set.reps != null ? '${widget.set.reps}' : '');
    _rpe = widget.set.rpe;
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    final w = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    final r = int.tryParse(_repsCtrl.text);
    widget.set.weight = w;
    widget.set.reps = r;
    widget.set.rpe = _rpe;
    widget.onSave();
    Navigator.pop(context);
    // Autosave: persist immediately so changes survive navigation without saving
    TrainingService.updateSet(widget.set.id, weight: w, reps: r, rpe: _rpe);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Подход ${widget.set.setNumber}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Вес (кг)'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _repsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Повторения'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('RPE',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _rpeOptions.map((v) {
              final sel = _rpe == v;
              return ChoiceChip(
                label: Text(v == null ? '—' : '$v'),
                selected: sel,
                onSelected: (_) => setState(() => _rpe = v),
                selectedColor: AppColors.accent,
                checkmarkColor: Colors.black,
                labelStyle: TextStyle(
                  color: sel ? Colors.black : AppColors.textPrimary,
                  fontWeight:
                      sel ? FontWeight.w600 : FontWeight.w400,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _apply,
              child: const Text('Применить'),
            ),
          ),
        ],
      ),
    );
  }
}
