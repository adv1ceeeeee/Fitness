import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/providers/active_session_provider.dart';
import 'package:sportwai/services/achievement_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/local_storage.dart';
import 'package:sportwai/services/notification_service.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/recsys_service.dart';
import 'package:sportwai/services/calorie_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/gamification_service.dart';
import 'package:sportwai/services/gamification_config.dart';
import 'package:sportwai/screens/shared/feedback_sheets.dart';
import 'package:sportwai/services/feedback_service.dart';

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
  int? _sessionRpe;
  List<PostSessionInsight> _postInsights = [];

  // Grouped exercise data: exerciseName → list of _SetRow
  final List<_ExerciseGroup> _groups = [];
  final TextEditingController _notesCtrl = TextEditingController();
  late final ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));
    _loadSets();
  }

  @override
  void dispose() {
    _confettiController.dispose();
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
      final exerciseName = (exInfo['name_ru'] as String?)
          ?? exInfo['name'] as String?
          ?? 'Упражнение';
      final exerciseCategory = exInfo['category'] as String? ?? 'chest';
      final weOrder = weInfo['order'] as int? ?? 0;
      final key = '${weOrder}_$exerciseName';

      map.putIfAbsent(
        key,
        () => _ExerciseGroup(name: exerciseName, order: weOrder, category: exerciseCategory),
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
      _confettiController.play();
      _checkNewAchievements();
      _loadInsights(vol, sorted);
    }
  }

  Future<void> _loadInsights(
      double sessionVolume, List<_ExerciseGroup> groups) async {
    try {
      final results = await Future.wait([
        AnalyticsService.getCurrentStreak(),
        AnalyticsService.getRecentSessionVolumes(),
      ]);
      final streak = results[0] as int;
      final recentVolumes = results[1] as List<double>;
      final recentAvg = recentVolumes.isEmpty
          ? null
          : recentVolumes.reduce((a, b) => a + b) / recentVolumes.length;
      final workingSets = groups.fold<int>(
        0,
        (sum, g) => sum + g.sets.where((s) => !s.isWarmup).length,
      );
      final insights = evaluatePostSession(
        streak: streak,
        sessionVolume: sessionVolume,
        recentAvgVolume: recentAvg,
        workingSetsCount: workingSets,
      );
      if (mounted) setState(() => _postInsights = insights);
    } catch (_) {}
  }

  Future<void> _checkNewAchievements() async {
    try {
      final all = await AchievementService.getAchievements();
      final unlocked = all.where((a) => a.unlocked).toList();
      final seen = AppStorage.seenAchievementIds;
      final newOnes = unlocked.where((a) => !seen.contains(a.id)).toList();
      if (newOnes.isEmpty || !mounted) return;

      // Mark as seen immediately so we don't show again
      await AppStorage.setSeenAchievementIds([
        ...seen,
        ...newOnes.map((a) => a.id),
      ]);

      // Award XP for each newly unlocked achievement
      for (final ach in newOnes) {
        await GamificationService.award(
          'achievement',
          amount: ach.rarity.xpReward,
          sourceId: ach.id,
        );
      }

      if (!mounted) return;
      for (final ach in newOnes) {
        await showModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          backgroundColor: AppColors.card,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) => _AchievementUnlockSheet(achievement: ach),
        );
        if (!mounted) return;
      }
    } catch (_) {}
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
      // Update edited sets (including recalculated kcal_estimated)
      for (final group in _groups) {
        for (final set in group.sets) {
          final kcal = (set.reps != null && set.reps! > 0)
              ? estimateSetKcal(category: group.category, reps: set.reps!, rpe: set.rpe)
              : null;
          await TrainingService.updateSet(
            set.id,
            weight: set.weight,
            reps: set.reps,
            rpe: set.rpe,
            kcalEstimated: kcal,
          );
        }
      }
      // Mark session complete
      await TrainingService.completeSession(
        widget.sessionId,
        durationSeconds: widget.durationSeconds,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        sessionRpe: _sessionRpe,
      );
      if (_sessionRpe != null) {
        EventLogger.sessionRpeLogged(
          sessionId: widget.sessionId,
          rpe: _sessionRpe!,
        );
      }
      // kcal_total and volume_kg are now computed inside fn_complete_session
      // ── XP awards ──────────────────────────────────────────────────────────
      int xpGained = 0;
      final totalSets = _groups.fold<int>(0, (s, g) => s + g.sets.length);
      final duration = widget.durationSeconds;
      if (duration >= minWorkoutDurationForXp) {
        xpGained += await GamificationService.award('workout_completed', sourceId: widget.sessionId);
        xpGained += await GamificationService.awardSets(totalSets, sessionId: widget.sessionId);
        xpGained += await GamificationService.awardDuration(duration, sessionId: widget.sessionId);
        final streak = await AnalyticsService.getCurrentStreak();
        if (streak >= 7) {
          xpGained += await GamificationService.award('streak_bonus', sourceId: widget.sessionId);
        }
      }
      // Schedule inactivity reminder (fires in 3 days if no workout)
      NotificationService.scheduleInactivityReminder(daysLater: 3);
      // Clear global session state
      ref.read(activeSessionProvider.notifier).stop();
      // Show NPS survey after 3rd session (before navigating away)
      final showNps = await FeedbackService.shouldShowNps();
      if (mounted && showNps) {
        // ignore: use_build_context_synchronously
        await showNpsSheet(context);
      }
      if (mounted) {
        if (xpGained > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('+$xpGained XP'),
              backgroundColor: AppColors.accent,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        context.go('/home');
      }
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
        body: Stack(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 80),
                children: [
                  // ── Duration card ──────────────────────────────────────
                  _SummaryHeader(
                    durationLabel: _formatDuration(widget.durationSeconds),
                    setsCount: _groups.fold(0, (s, g) => s + g.sets.length),
                    exercisesCount: _groups.length,
                    totalVolume: _totalVolume,
                  ),
                  const SizedBox(height: 20),
                  // ── Post-session insights ──────────────────────────────
                  if (_postInsights.isNotEmpty) ...[
                    ..._postInsights.map((ins) => _InsightChip(insight: ins)),
                    const SizedBox(height: 16),
                  ],
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
                  const SizedBox(height: 16),
                  // ── Session RPE ────────────────────────────────────────
                  _SessionRpeCard(
                    selected: _sessionRpe,
                    onChanged: (v) => setState(() => _sessionRpe = v),
                  ),
                  const SizedBox(height: 24),
                  // ── Save button ────────────────────────────────────────
                  GradientButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Сохранить тренировку'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            // ── Confetti overlay ───────────────────────────────────────
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: 0.05,
                numberOfParticles: 20,
                maxBlastForce: 20,
                minBlastForce: 8,
                gravity: 0.3,
                colors: const [
                  Color(0xFFE8C547),
                  Color(0xFF4CAF50),
                  Color(0xFF2196F3),
                  Color(0xFFFF5722),
                  Color(0xFFE91E63),
                ],
                createParticlePath: (size) {
                  final path = Path();
                  path.addOval(
                      Rect.fromCircle(center: Offset.zero, radius: size.width / 2));
                  return path;
                },
              ),
            ),
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
  final String category;
  final List<_SetRow> sets;

  _ExerciseGroup({required this.name, required this.order, required this.category})
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

class _SessionRpeCard extends StatelessWidget {
  final int? selected;
  final ValueChanged<int?> onChanged;

  const _SessionRpeCard({required this.selected, required this.onChanged});

  static const _labels = {
    1: 'Очень легко', 2: 'Легко', 3: 'Умеренно', 4: 'Чуть тяжело',
    5: 'Тяжело', 6: 'Тяжело+', 7: 'Очень тяжело', 8: 'Предел',
    9: 'Почти максимум', 10: 'Максимум',
  };

  Color _rpeColor(int v) {
    if (v <= 3) return Colors.green;
    if (v <= 5) return Colors.yellow.shade700;
    if (v <= 7) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Сложность тренировки',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Влияет на следующие рекомендации',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected != null)
                Text(
                  _labels[selected] ?? '',
                  style: TextStyle(
                    color: _rpeColor(selected!),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(10, (i) {
              final v = i + 1;
              final sel = selected == v;
              return GestureDetector(
                onTap: () => onChanged(sel ? null : v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: sel
                        ? _rpeColor(v)
                        : _rpeColor(v).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '$v',
                      style: TextStyle(
                        color: sel ? Colors.white : _rpeColor(v),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

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
                  category: widget.group.category,
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
  final String category;
  final VoidCallback onChanged;

  const _SetRowWidget({required this.set, required this.category, required this.onChanged});

  void _editSet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SetEditSheet(set: set, category: category, onSave: onChanged),
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
  final String category;
  final VoidCallback onSave;

  const _SetEditSheet({required this.set, required this.category, required this.onSave});

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
    final kcal = (r != null && r > 0)
        ? estimateSetKcal(category: widget.category, reps: r, rpe: _rpe)
        : null;
    TrainingService.updateSet(widget.set.id, weight: w, reps: r, rpe: _rpe,
        kcalEstimated: kcal);
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

// ─── Achievement unlock popup ─────────────────────────────────────────────────

class _AchievementUnlockSheet extends StatelessWidget {
  final Achievement achievement;

  const _AchievementUnlockSheet({required this.achievement});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            achievement.emoji,
            style: const TextStyle(fontSize: 64),
          ),
          const SizedBox(height: 12),
          const Text(
            'Новое достижение!',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            achievement.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // Rarity badge + XP reward
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: achievement.rarity.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  achievement.rarity.label,
                  style: TextStyle(
                    color: achievement.rarity.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '+${achievement.rarity.xpReward} XP',
                style: TextStyle(
                  color: achievement.rarity.color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            achievement.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отлично!'),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () {
              Share.share(
                '${achievement.emoji} Разблокировал достижение «${achievement.title}» в Sportify!\n${achievement.description}',
                subject: 'Достижение в Sportify',
              );
            },
            icon: const Icon(Icons.share_rounded, size: 16),
            label: const Text('Поделиться'),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Post-session insight chip ────────────────────────────────────────────────

class _InsightChip extends StatelessWidget {
  final PostSessionInsight insight;

  const _InsightChip({required this.insight});

  static const _kindStyle = {
    PostSessionInsightKind.streak:     (Icons.local_fire_department_rounded, Color(0xFFFF9F0A)),
    PostSessionInsightKind.volumeUp:   (Icons.trending_up_rounded,           Color(0xFF32D74B)),
    PostSessionInsightKind.volumeDown: (Icons.trending_down_rounded,         Color(0xFF8E8E93)),
    PostSessionInsightKind.setsCount:  (Icons.check_circle_rounded,          Color(0xFF0A84FF)),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _kindStyle[insight.kind]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              insight.message,
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
