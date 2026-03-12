import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/providers/active_session_provider.dart';
import 'package:sportwai/screens/onboarding/onboarding_overlay.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/body_metrics_service.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/wellness_service.dart';

// ─── Metric options for body progress panel ───────────────────────────────────

const _metricOptions = <String, (String label, String unit)>{
  'weight_kg':       ('Вес',        'кг'),
  'body_fat_pct':    ('% жира',     '%'),
  'waist_cm':        ('Талия',      'см'),
  'chest_cm':        ('Грудь',      'см'),
  'hips_cm':         ('Бёдра',      'см'),
  'right_arm_cm':    ('Бицепс',     'см'),
  'shoulders_cm':    ('Плечи',      'см'),
};

// ─── Pure helpers (top-level for testability) ─────────────────────────────────

/// Format a numeric value: integers shown without decimal point.
String fmtMetricValue(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

/// Returns whether the goal has been reached (within 0.05 tolerance).
bool bodyProgressGoalReached(double current, double? target) =>
    target != null && (target - current).abs() < 0.05;

/// Human-readable "remaining" line for the body progress panel.
String bodyProgressRemainingText(double current, double? target, String unit) {
  if (target == null) return "Нажмите на «Цель» для установки";
  if (bodyProgressGoalReached(current, target)) return 'Цель достигнута!';
  final diff = (target - current).abs();
  final sign = target < current ? '−' : '+';
  return 'До цели: $sign${fmtMetricValue(diff)} $unit';
}

/// Returns a human-readable elapsed-time string for goal achievement.
/// e.g. "за 5 дн.", "за 3 нед.", "за 2 мес."
String elapsedGoalText(DateTime startDate) {
  final days = DateTime.now().difference(startDate).inDays.clamp(1, 999);
  if (days < 7) return 'за $days дн.';
  if (days < 30) return 'за ${(days / 7).round()} нед.';
  return 'за ${(days / 30).round()} мес.';
}

/// Format the "+X кг" / "+X повт." badge text for an achievement card.
String achievementDiffText(WorkoutInsight insight) {
  final diff = insight.newValue - insight.prevValue;
  final unit = insight.isWeight ? 'кг' : 'повт.';
  return '+${fmtMetricValue(diff)} $unit';
}

/// Sentinel used in the target dialog to distinguish "Clear" from "Cancel".
const _kClearTarget = _ClearSentinel();

class _ClearSentinel {
  const _ClearSentinel();
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Profile? _profile;
  Workout? _todayWorkout;
  bool _loadingWorkout = true;
  bool _wellnessLogged = true;

  WorkoutInsight? _insight;
  Map<String, dynamic>? _latestBodyMetrics;
  String _goalMetric = 'weight_kg';
  double? _goalTarget;
  DateTime? _goalStartDate;

  @override
  void initState() {
    super.initState();
    _load();
    _showOnboardingOnce();
    _checkCrashRecovery();
  }

  Future<void> _showOnboardingOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('onboarding_shown') ?? false;
    if (shown) return;
    await prefs.setBool('onboarding_shown', true);
    if (mounted) await showOnboardingIfNeeded(context);
  }

  Future<void> _checkCrashRecovery() async {
    // Skip if a session is already active in memory
    if (ref.read(activeSessionProvider).isActive) return;
    final saved = await ActiveSessionNotifier.loadPersisted();
    if (saved == null || !mounted) return;
    // Verify the session still exists and is not completed in DB
    final sessions = await TrainingService.getSessionsByDateRange(
      DateTime.now().subtract(const Duration(days: 1)),
      DateTime.now().add(const Duration(days: 1)),
    );
    final found = sessions.where((s) => s.id == saved.sessionId && !s.completed).firstOrNull;
    if (found == null || !mounted) return;
    // Restore provider state
    ref.read(activeSessionProvider.notifier).start(
      sessionId: saved.sessionId!,
      workoutId: saved.workoutId ?? '',
      workoutName: saved.workoutName ?? '',
      startTime: saved.startTime,
    );
    // Show banner
    if (!mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: AppColors.card,
        content: const Text(
          'Незавершённая тренировка. Продолжить?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              ref.read(activeSessionProvider.notifier).stop();
            },
            child: const Text('Отмена',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              context.push('/session/${saved.sessionId}');
            },
            child: const Text('Продолжить',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ProfileService.getProfile(),
        TrainingService.getTodayWorkout(),
        WellnessService.getTodayLog(),
        AnalyticsService.getLastWorkoutInsight(),
        BodyMetricsService.getLatest(),
        _loadGoalPrefs(),
      ]).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      setState(() {
        _profile = results[0] as Profile?;
        _todayWorkout = results[1] as Workout?;
        _loadingWorkout = false;
        _wellnessLogged = results[2] != null;
        _insight = results[3] as WorkoutInsight?;
        _latestBodyMetrics = results[4] as Map<String, dynamic>?;
        final goalPrefs = results[5] as (String, double?, DateTime?);
        _goalMetric = goalPrefs.$1;
        _goalTarget = goalPrefs.$2;
        _goalStartDate = goalPrefs.$3;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingWorkout = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Не удалось загрузить данные'),
            action: SnackBarAction(label: 'Повторить', onPressed: _load),
          ),
        );
      }
    }
  }

  Future<(String, double?, DateTime?)> _loadGoalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final metric = prefs.getString('home_goal_metric') ?? 'weight_kg';
    final targetStr = prefs.getString('home_goal_target_$metric');
    final startStr = prefs.getString('home_goal_start_$metric');
    return (
      metric,
      targetStr != null ? double.tryParse(targetStr) : null,
      startStr != null ? DateTime.tryParse(startStr) : null,
    );
  }

  Future<void> _saveGoalMetric(String metric) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('home_goal_metric', metric);
    final targetStr = prefs.getString('home_goal_target_$metric');
    final startStr = prefs.getString('home_goal_start_$metric');
    setState(() {
      _goalMetric = metric;
      _goalTarget = targetStr != null ? double.tryParse(targetStr) : null;
      _goalStartDate = startStr != null ? DateTime.tryParse(startStr) : null;
    });
  }

  Future<void> _saveGoalTarget(double? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('home_goal_target_$_goalMetric');
      await prefs.remove('home_goal_start_$_goalMetric');
      setState(() {
        _goalTarget = null;
        _goalStartDate = null;
      });
    } else {
      await prefs.setString('home_goal_target_$_goalMetric', value.toString());
      // Reset start date whenever the target value changes
      final today = DateTime.now().toIso8601String().split('T')[0];
      await prefs.setString('home_goal_start_$_goalMetric', today);
      setState(() {
        _goalTarget = value;
        _goalStartDate = DateTime.parse(today);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?.fullName?.split(' ').first ?? 'Атлет';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).padding.bottom + 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Привет, $name!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (!_wellnessLogged) ...[
                  const SizedBox(height: 24),
                  _WellnessCard(
                    onSaved: () => setState(() => _wellnessLogged = true),
                  ),
                ],
                const SizedBox(height: 24),
                _TodayCard(
                  workout: _todayWorkout,
                  loading: _loadingWorkout,
                  onTap: () => context.push('/today'),
                  onCreateProgram: () => context.go('/workouts'),
                ),

                // ── Achievement card ──────────────────────────────────────
                if (_insight != null) ...[
                  const SizedBox(height: 16),
                  _AchievementCard(insight: _insight!),
                ],

                // ── Body progress card ────────────────────────────────────
                const SizedBox(height: 16),
                _BodyProgressCard(
                  latestMetrics: _latestBodyMetrics,
                  metric: _goalMetric,
                  target: _goalTarget,
                  goalStartDate: _goalStartDate,
                  onMetricChanged: _saveGoalMetric,
                  onTargetChanged: _saveGoalTarget,
                  onAddMetrics: () => context.push('/body-metrics'),
                ),

                const SizedBox(height: 12),
                _QuickWeightCard(
                  currentWeight: (_latestBodyMetrics?['weight_kg'] as num?)?.toDouble(),
                  onSaved: () async {
                    if (mounted) _load();
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Быстрые действия',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.fitness_center_rounded,
                        label: 'Мои программы',
                        onTap: () => context.go('/workouts'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.analytics_rounded,
                        label: 'Аналитика',
                        onTap: () => context.go('/analytics'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  icon: Icons.calendar_month_rounded,
                  label: 'Календарь тренировок',
                  onTap: () => context.push('/calendar'),
                  fullWidth: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Achievement Card ─────────────────────────────────────────────────────────

class _AchievementCard extends StatelessWidget {
  final WorkoutInsight insight;

  const _AchievementCard({required this.insight});

  String _formatDate(String raw) {
    if (raw.length < 10) return raw;
    return '${raw.substring(8, 10)}.${raw.substring(5, 7)}';
  }

  @override
  Widget build(BuildContext context) {
    final diff = insight.newValue - insight.prevValue;
    final unit = insight.isWeight ? 'кг' : 'повт.';
    final diffStr = '+${diff % 1 == 0 ? diff.toInt() : diff.toStringAsFixed(1)} $unit';

    final prevStr = insight.isWeight
        ? '${insight.prevValue % 1 == 0 ? insight.prevValue.toInt() : insight.prevValue} кг'
        : '${insight.prevValue.toInt()} повт.';
    final newStr = insight.isWeight
        ? '${insight.newValue % 1 == 0 ? insight.newValue.toInt() : insight.newValue} кг'
        : '${insight.newValue.toInt()} повт.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.trending_up_rounded,
              color: AppColors.accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Прогресс ${_formatDate(insight.sessionDate)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  insight.exerciseName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$prevStr → $newStr',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              diffStr,
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Body Progress Card ───────────────────────────────────────────────────────

class _BodyProgressCard extends StatelessWidget {
  final Map<String, dynamic>? latestMetrics;
  final String metric;
  final double? target;
  final DateTime? goalStartDate;
  final ValueChanged<String> onMetricChanged;
  final ValueChanged<double?> onTargetChanged;
  final VoidCallback onAddMetrics;

  const _BodyProgressCard({
    required this.latestMetrics,
    required this.metric,
    required this.target,
    this.goalStartDate,
    required this.onMetricChanged,
    required this.onTargetChanged,
    required this.onAddMetrics,
  });

  double? get _currentValue {
    final v = latestMetrics?[metric];
    return (v as num?)?.toDouble();
  }

  String get _unit => _metricOptions[metric]?.$2 ?? '';
  String get _label => _metricOptions[metric]?.$1 ?? metric;

  void _showMetricPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  'Отслеживаемый параметр',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    for (final entry in _metricOptions.entries)
                      ListTile(
                        title: Text(
                          '${entry.value.$1}, ${entry.value.$2}',
                          style: TextStyle(
                            color: entry.key == metric
                                ? AppColors.accent
                                : AppColors.textPrimary,
                            fontWeight: entry.key == metric
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: entry.key == metric
                            ? const Icon(Icons.check,
                                color: AppColors.accent, size: 20)
                            : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          onMetricChanged(entry.key);
                        },
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    SizedBox(
                        height: MediaQuery.of(ctx).padding.bottom + 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTargetDialog(BuildContext context) async {
    final ctrl = TextEditingController(
      text: target != null ? fmtMetricValue(target!) : '',
    );
    final result = await showDialog<Object>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Целевой $_label',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(suffixText: _unit),
        ),
        actions: [
          if (target != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, _kClearTarget),
              child: const Text('Сбросить',
                  style: TextStyle(color: AppColors.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final v = double.tryParse(
                  ctrl.text.trim().replaceAll(',', '.'));
              if (v != null && v > 0 && v < 1000) Navigator.pop(ctx, v);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == _kClearTarget) {
      onTargetChanged(null);
    } else if (result is double) {
      onTargetChanged(result);
    }
    // null == Отмена — do nothing
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentValue;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with metric picker
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                const Text(
                  'Прогресс тела',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showMetricPicker(context),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_label, $_unit',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more,
                            size: 16, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (current == null) ...[
            // No data yet
            InkWell(
              onTap: onAddMetrics,
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Row(
                  children: [
                    const Icon(Icons.add_circle_outline,
                        color: AppColors.accent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Добавить первый замер $_label',
                      style: const TextStyle(
                          color: AppColors.accent, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Current vs Target boxes
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Row(
                children: [
                  Expanded(child: _MetricBox(
                    label: 'Фактический',
                    value: '${fmtMetricValue(current)} $_unit',
                    onTap: null,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _MetricBox(
                    label: 'Цель',
                    value: target != null
                        ? '${fmtMetricValue(target!)} $_unit'
                        : '—',
                    hint: target == null ? 'Установить' : null,
                    onTap: () => _showTargetDialog(context),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Remaining info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.surface, width: 1),
                ),
              ),
              child: Center(
                child: Text(
                  _remainingText(current),
                  style: TextStyle(
                    fontSize: 13,
                    color: _remainingColor(current),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _remainingText(double current) {
    if (target == null) return 'Нажмите на «Цель» для установки';
    final diff = (target! - current).abs();
    if (diff < 0.05) {
      if (goalStartDate != null) {
        return 'Цель достигнута ${elapsedGoalText(goalStartDate!)}!';
      }
      return 'Цель достигнута!';
    }
    final sign = target! < current ? '−' : '+';
    return 'До цели: $sign${fmtMetricValue(diff)} $_unit';
  }

  Color _remainingColor(double current) {
    if (target == null) return AppColors.textSecondary;
    final diff = (target! - current).abs();
    if (diff < 0.05) return AppColors.accent;
    return AppColors.textSecondary;
  }
}

class _MetricBox extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final VoidCallback? onTap;

  const _MetricBox({
    required this.label,
    required this.value,
    this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: onTap != null
              ? Border.all(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  width: 1,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: onTap != null && value == '—'
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Today Card ───────────────────────────────────────────────────────────────

class _TodayCard extends StatelessWidget {
  final Workout? workout;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback? onCreateProgram;

  const _TodayCard({
    required this.workout,
    required this.loading,
    required this.onTap,
    this.onCreateProgram,
  });

  @override
  Widget build(BuildContext context) {
    final hasWorkout = workout != null;
    return Material(
      color: hasWorkout ? AppColors.card : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: hasWorkout ? onTap : onCreateProgram,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hasWorkout
                      ? AppColors.accent.withValues(alpha: 0.2)
                      : AppColors.separator.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasWorkout
                      ? Icons.fitness_center_rounded
                      : Icons.today_rounded,
                  color: hasWorkout
                      ? AppColors.accent
                      : AppColors.textSecondary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: loading
                    ? const Text('Загрузка...',
                        style: TextStyle(color: AppColors.textSecondary))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasWorkout
                                ? workout!.name
                                : 'Сегодня тренировки нет',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: hasWorkout
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          if (hasWorkout) ...[
                            const SizedBox(height: 4),
                            const Text(
                              'Нажми, чтобы начать',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary),
                            ),
                          ] else if (onCreateProgram != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Создать программу →',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.accent.withValues(alpha: 0.8)),
                            ),
                          ],
                        ],
                      ),
              ),
              if (hasWorkout)
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Wellness check-in card ───────────────────────────────────────────────────

class _WellnessCard extends StatefulWidget {
  final VoidCallback onSaved;

  const _WellnessCard({required this.onSaved});

  @override
  State<_WellnessCard> createState() => _WellnessCardState();
}

class _WellnessCardState extends State<_WellnessCard> {
  double _sleep = 7;
  int _stress = 3;
  int _energy = 3;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await WellnessService.upsert(
      sleepHours: _sleep,
      stress: _stress,
      energy: _energy,
    );
    if (mounted) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Как самочувствие?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _SleepRow(
            value: _sleep,
            onChanged: (v) => setState(() => _sleep = v),
          ),
          const SizedBox(height: 12),
          _RatingRow(
            label: 'Стресс',
            value: _stress,
            onChanged: (v) => setState(() => _stress = v),
          ),
          const SizedBox(height: 12),
          _RatingRow(
            label: 'Энергия',
            value: _energy,
            onChanged: (v) => setState(() => _energy = v),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _RatingRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
        const SizedBox(width: 8),
        ...List.generate(5, (i) {
          final selected = i < value;
          return GestureDetector(
            onTap: () => onChanged(i + 1),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                selected ? Icons.star_rounded : Icons.star_outline_rounded,
                color: selected
                    ? AppColors.accent
                    : AppColors.textSecondary,
                size: 28,
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _SleepRow extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _SleepRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 72,
          child: Text(
            'Сон',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.surface,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accent.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: value,
              min: 4,
              max: 12,
              divisions: 16,
              onChanged: onChanged,
            ),
          ),
        ),
        Text(
          '${value.toStringAsFixed(1)}ч',
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ─── Quick action card ────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool fullWidth;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: fullWidth
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 28, color: AppColors.accent),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Icon(icon, size: 32, color: AppColors.accent),
                    const SizedBox(height: 12),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── Quick weight logging card ────────────────────────────────────────────────

class _QuickWeightCard extends StatefulWidget {
  final double? currentWeight;
  final Future<void> Function() onSaved;

  const _QuickWeightCard({this.currentWeight, required this.onSaved});

  @override
  State<_QuickWeightCard> createState() => _QuickWeightCardState();
}

class _QuickWeightCardState extends State<_QuickWeightCard> {
  late final TextEditingController _ctrl;
  bool _saving = false;
  bool _saved = false;
  List<Map<String, dynamic>> _todayLogs = [];

  @override
  void initState() {
    super.initState();
    final hint = widget.currentWeight;
    _ctrl = TextEditingController(
        text: hint != null
            ? (hint % 1 == 0 ? hint.toInt().toString() : hint.toStringAsFixed(1))
            : '');
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final logs = await BodyMetricsService.getTodayWeightLogs();
    if (mounted) setState(() => _todayLogs = logs);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save({bool updateDaily = true}) async {
    final v = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (v == null || v <= 0 || v > 500) return;
    setState(() => _saving = true);
    await BodyMetricsService.logWeight(v, updateDaily: updateDaily);
    await _loadLogs();
    await widget.onSaved();
    if (mounted) setState(() { _saving = false; _saved = true; });
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _saved = false);
  }

  String _formatTime(String isoUtc) {
    final dt = DateTime.parse(isoUtc).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _actionButton({
    required String label,
    required VoidCallback? onTap,
    bool secondary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: secondary
              ? AppColors.surface
              : AppColors.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: secondary ? AppColors.textSecondary : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTodayLogs = _todayLogs.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.monitor_weight_outlined,
                  color: AppColors.accent, size: 22),
              const SizedBox(width: 10),
              const Text(
                'Вес сегодня',
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w500),
              ),
              if (hasTodayLogs) ...[
                const Spacer(),
                // Today's log chips
                Wrap(
                  spacing: 6,
                  children: _todayLogs.map((log) {
                    final w = (log['weight_kg'] as num).toDouble();
                    final t = _formatTime(log['measured_at'] as String);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$t · ${w % 1 == 0 ? w.toInt() : w.toStringAsFixed(1)} кг',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Input + buttons
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: '—',
                    suffixText: 'кг',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _saved
                    ? const Icon(Icons.check_circle,
                        key: ValueKey('check'),
                        color: AppColors.accent,
                        size: 28)
                    : _saving
                        ? const SizedBox(
                            key: ValueKey('loader'),
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.accent),
                          )
                        : hasTodayLogs
                            ? Row(
                                key: const ValueKey('two-btn'),
                                children: [
                                  _actionButton(
                                    label: 'Обновить',
                                    onTap: () => _save(updateDaily: true),
                                  ),
                                  const SizedBox(width: 6),
                                  _actionButton(
                                    label: '+ Ещё раз',
                                    onTap: () => _save(updateDaily: false),
                                    secondary: true,
                                  ),
                                ],
                              )
                            : _actionButton(
                                label: 'Сохранить',
                                onTap: () => _save(),
                              ),
              ),
            ],
          ),
          if (hasTodayLogs)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Обновить — заменит ежедневный вес · Ещё раз — сохранит как отдельное взвешивание',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}
