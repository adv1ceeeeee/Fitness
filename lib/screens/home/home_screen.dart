import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/config/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/providers/active_session_provider.dart';
import 'package:sportwai/screens/onboarding/onboarding_overlay.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/body_metrics_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/wellness_service.dart';
import 'package:sportwai/services/workout_service.dart';

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
  List<Map<String, dynamic>> _bodyMetricsHistory = [];
  String _goalMetric = 'weight_kg';
  double? _goalTarget;
  DateTime? _goalStartDate;
  // Per-metric goal cache: metric → {target, start}
  Map<String, ({double? target, DateTime? start})> _goalCache = {};
  bool _showMeasurementReminder = false;

  // Weekly workout goal
  int _weeklyWorkoutGoal = 0;   // 0 = not set
  int _workoutsThisWeek = 0;
  int _daysSinceLastWorkout = -1;
  Workout? _nextScheduledWorkout;
  bool _isRestDay = false;

  @override
  void initState() {
    super.initState();
    _load();
    _showOnboardingOnce();
    _checkCrashRecovery();
  }

  Future<void> _showOnboardingOnce() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final key = 'onboarding_shown_${user.id}';
    final prefs = await SharedPreferences.getInstance();

    // Fast path: already cached locally
    if (prefs.getBool(key) == true) return;

    // Fallback: check Supabase so port changes don't re-show onboarding
    try {
      final row = await Supabase.instance.client
          .from('user_events')
          .select('id')
          .eq('user_id', user.id)
          .eq('event', 'onboarding_shown')
          .limit(1)
          .maybeSingle();
      if (row != null) {
        await prefs.setBool(key, true); // cache locally for next time
        return;
      }
    } catch (_) {
      // offline — fall through and show onboarding
    }

    // Mark as shown both locally and in Supabase
    await prefs.setBool(key, true);
    try {
      await Supabase.instance.client.from('user_events').insert({
        'user_id': user.id,
        'event': 'onboarding_shown',
        'props': <String, dynamic>{},
      });
    } catch (_) {}

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
    // Load local prefs first — independent of network, must never be lost.
    await _loadGoalPrefs();
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final weeklyGoal = prefs.getInt('weekly_workout_goal') ?? 0;

      final results = await Future.wait([
        ProfileService.getProfile(),
        TrainingService.getTodayWorkout(),
        WellnessService.getTodayLog(),
        AnalyticsService.getLastWorkoutInsight(),
        BodyMetricsService.getHistory(),
        AnalyticsService.getWorkoutsThisWeek(),
        TrainingService.getDaysSinceLastWorkout(),
      ]).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      final metricsHistory = (results[4] as List).cast<Map<String, dynamic>>();
      bool showReminder = false;
      if (metricsHistory.isEmpty) {
        showReminder = true;
      } else {
        final lastDateStr = metricsHistory.last['date'] as String?;
        if (lastDateStr != null) {
          final lastDate = DateTime.tryParse(lastDateStr);
          if (lastDate != null &&
              DateTime.now().difference(lastDate).inDays > 28) {
            showReminder = true;
          }
        }
      }
      final daysSince = results[6] as int;
      // Check if today is a rest day in any active workout
      final todayAppDay = DateTime.now().weekday - 1; // 0=Mon…6=Sun
      final allWorkouts = await WorkoutService.getMyWorkouts();
      final isRestDay = allWorkouts.any((w) => w.restDays.contains(todayAppDay));
      // Load next scheduled workout if inactive for 2+ days
      Workout? nextWorkout;
      if (daysSince >= 2 && !isRestDay) {
        nextWorkout = results[1] as Workout? ?? await TrainingService.getNextScheduledWorkout();
      }
      setState(() {
        _profile = results[0] as Profile?;
        _todayWorkout = results[1] as Workout?;
        _loadingWorkout = false;
        _wellnessLogged = results[2] != null;
        _insight = results[3] as WorkoutInsight?;
        _bodyMetricsHistory = metricsHistory;
        _showMeasurementReminder = showReminder;
        _weeklyWorkoutGoal = weeklyGoal;
        _workoutsThisWeek = results[5] as int;
        _daysSinceLastWorkout = daysSince;
        _nextScheduledWorkout = nextWorkout;
        _isRestDay = isRestDay;
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

  static SupabaseClient get _db => Supabase.instance.client;

  Future<void> _loadGoalPrefs() async {
    try {
      final userId = _db.auth.currentUser?.id;
      if (userId == null) return;

      // Load from reliable old single-metric columns (always present since migration 023)
      final row = await _db
          .from('profiles')
          .select('goal_metric, goal_target, goal_start')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return;

      final metric = (row['goal_metric'] as String?) ?? 'weight_kg';
      final cache = <String, ({double? target, DateTime? start})>{};

      // Try to also load multi-metric JSON (migration 029, may not be applied)
      try {
        final jsonRow = await _db
            .from('profiles')
            .select('goal_targets_json')
            .eq('id', userId)
            .maybeSingle();
        final rawJson =
            (jsonRow?['goal_targets_json'] as Map<String, dynamic>?) ?? {};
        for (final entry in rawJson.entries) {
          final v = entry.value as Map<String, dynamic>;
          cache[entry.key] = (
            target:
                v['target'] != null ? (v['target'] as num).toDouble() : null,
            start: v['start'] != null
                ? DateTime.tryParse(v['start'] as String)
                : null,
          );
        }
      } catch (_) {}

      // Fall back to old columns if JSON cache is empty or unavailable
      if (cache[metric] == null && row['goal_target'] != null) {
        cache[metric] = (
          target: (row['goal_target'] as num).toDouble(),
          start: row['goal_start'] != null
              ? DateTime.tryParse(row['goal_start'] as String)
              : null,
        );
      }

      if (!mounted) return;
      setState(() {
        _goalCache = cache;
        _goalMetric = metric;
        final g = cache[metric];
        _goalTarget = g?.target;
        _goalStartDate = g?.start;
      });
    } catch (e) {
      debugPrint('[HomeScreen] _loadGoalPrefs error: $e');
    }
  }

  Future<void> _saveGoalMetric(String metric) async {
    final entry = _goalCache[metric];
    setState(() {
      _goalMetric = metric;
      _goalTarget = entry?.target;
      _goalStartDate = entry?.start;
    });
    try {
      final userId = _db.auth.currentUser?.id;
      if (userId == null) return;
      await _db.from('profiles').update({'goal_metric': metric}).eq('id', userId);
      EventLogger.goalSet(goal: metric);
    } catch (_) {}
  }

  Future<void> _saveGoalTarget(double? value) async {
    final now = DateTime.now();
    final newEntry = value != null
        ? (target: value, start: now)
        : (target: null as double?, start: null as DateTime?);
    final newCache = Map<String, ({double? target, DateTime? start})>.from(_goalCache);
    if (value != null) {
      newCache[_goalMetric] = newEntry;
    } else {
      newCache.remove(_goalMetric);
    }
    setState(() {
      _goalTarget = value;
      _goalStartDate = value != null ? now : null;
      _goalCache = newCache;
    });
    try {
      final userId = _db.auth.currentUser?.id;
      if (userId == null) return;
      // Always save to reliable old columns (migration 023, guaranteed to exist)
      await _db.from('profiles').update({
        'goal_metric': _goalMetric,
        'goal_target': value,
        'goal_start': value != null ? now.toIso8601String() : null,
      }).eq('id', userId);
      // Also try multi-metric JSON (migration 029, best-effort)
      try {
        final jsonData = {
          for (final e in newCache.entries)
            if (e.value.target != null)
              e.key: {
                'target': e.value.target,
                'start': e.value.start?.toUtc().toIso8601String(),
              }
        };
        await _db.from('profiles').update({
          'goal_targets_json': jsonData,
        }).eq('id', userId);
      } catch (_) {}
    } catch (e) {
      debugPrint('[HomeScreen] _saveGoalTarget error: $e');
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

                // ── Weekly goal card ──────────────────────────────────────
                if (_weeklyWorkoutGoal > 0) ...[
                  const SizedBox(height: 16),
                  _WeeklyGoalCard(
                    goal: _weeklyWorkoutGoal,
                    done: _workoutsThisWeek,
                  ),
                ],

                // ── Rest day card ─────────────────────────────────────────
                if (_isRestDay) ...[
                  const SizedBox(height: 16),
                  const _RestDayCard(),
                ],

                // ── Inactivity suggestion ─────────────────────────────────
                if (_daysSinceLastWorkout >= 2 && _todayWorkout == null && !_isRestDay) ...[
                  const SizedBox(height: 16),
                  _InactivityCard(
                    days: _daysSinceLastWorkout,
                    nextWorkout: _nextScheduledWorkout,
                    onTap: () => context.go('/workouts'),
                  ),
                ],

                // ── Achievement card ──────────────────────────────────────
                if (_insight != null) ...[
                  const SizedBox(height: 16),
                  _AchievementCard(insight: _insight!),
                ],

                // ── Measurement reminder ──────────────────────────────────
                if (_showMeasurementReminder) ...[
                  const SizedBox(height: 16),
                  _MeasurementReminderBanner(
                    onDismiss: () =>
                        setState(() => _showMeasurementReminder = false),
                    onTap: () => context.push('/body-metrics'),
                  ),
                ],

                // ── Body progress card ────────────────────────────────────
                const SizedBox(height: 16),
                _BodyProgressCard(
                  metricsHistory: _bodyMetricsHistory,
                  metric: _goalMetric,
                  target: _goalTarget,
                  goalStartDate: _goalStartDate,
                  onMetricChanged: _saveGoalMetric,
                  onTargetChanged: _saveGoalTarget,
                  onAddMetrics: () => context.push('/body-metrics'),
                ),

                const SizedBox(height: 12),
                _QuickWeightCard(
                  currentWeight: () {
                    for (final m in _bodyMetricsHistory.reversed) {
                      if (m['weight_kg'] != null) return (m['weight_kg'] as num).toDouble();
                    }
                    return null;
                  }(),
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

// ─── Measurement Reminder Banner ──────────────────────────────────────────────

class _MeasurementReminderBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _MeasurementReminderBanner({
    required this.onDismiss,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.straighten_outlined,
                  color: AppColors.accent, size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Пора сделать замеры тела — прошло больше месяца',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 18, color: AppColors.textSecondary),
                onPressed: onDismiss,
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

// ─── Body Progress Card ───────────────────────────────────────────────────────

class _BodyProgressCard extends StatelessWidget {
  final List<Map<String, dynamic>> metricsHistory;
  final String metric;
  final double? target;
  final DateTime? goalStartDate;
  final ValueChanged<String> onMetricChanged;
  final ValueChanged<double?> onTargetChanged;
  final VoidCallback onAddMetrics;

  const _BodyProgressCard({
    required this.metricsHistory,
    required this.metric,
    required this.target,
    this.goalStartDate,
    required this.onMetricChanged,
    required this.onTargetChanged,
    required this.onAddMetrics,
  });

  /// Latest entry where the selected metric is not null.
  Map<String, dynamic>? get _latestEntry {
    for (final m in metricsHistory.reversed) {
      if (m[metric] != null) return m;
    }
    return null;
  }

  double? get _currentValue {
    final v = _latestEntry?[metric];
    return (v as num?)?.toDouble();
  }

  String? get _measurementDate {
    final entry = _latestEntry;
    if (entry == null) return null;
    final ts = entry['updated_at'] as String?;
    if (ts != null) {
      final dt = DateTime.tryParse(ts)?.toLocal();
      if (dt != null) return _fmtDT(dt);
    }
    final d = entry['date'] as String?;
    if (d == null || d.length < 10) return null;
    return '${d.substring(8, 10)}.${d.substring(5, 7)}.${d.substring(2, 4)}';
  }

  static String _fmtDT(DateTime dt) {
    final d = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year.toString().substring(2)}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }

  String? get _goalStartLabel => goalStartDate != null ? _fmtDT(goalStartDate!) : null;

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
                    subtitle: _measurementDate,
                    onTap: null,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _MetricBox(
                    label: 'Цель',
                    value: target != null
                        ? '${fmtMetricValue(target!)} $_unit'
                        : '—',
                    hint: target == null ? 'Установить' : null,
                    subtitle: _goalStartLabel,
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
  final String? subtitle;
  final VoidCallback? onTap;

  const _MetricBox({
    required this.label,
    required this.value,
    this.hint,
    this.subtitle,
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
            if (subtitle != null)
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
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
    try {
      await WellnessService.upsert(
        sleepHours: _sleep,
        stress: _stress,
        energy: _energy,
      );
      EventLogger.checkInSaved(type: 'wellness');
      if (mounted) widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
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
    try {
      await BodyMetricsService.logWeight(v, updateDaily: updateDaily);
      await _loadLogs();
      await widget.onSaved();
      if (mounted) setState(() { _saving = false; _saved = true; });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить вес')),
        );
      }
    }
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
                Builder(builder: (_) {
                  final log = _todayLogs.last;
                  final w = (log['weight_kg'] as num).toDouble();
                  final t = _formatTime(log['measured_at'] as String);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                }),
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

// ─── Weekly workout goal progress card ───────────────────────────────────────

class _WeeklyGoalCard extends StatelessWidget {
  final int goal;
  final int done;

  const _WeeklyGoalCard({required this.goal, required this.done});

  @override
  Widget build(BuildContext context) {
    final progress = (done / goal).clamp(0.0, 1.0);
    final isDone = done >= goal;
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
              Icon(
                isDone ? Icons.emoji_events_rounded : Icons.flag_rounded,
                color: AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isDone
                      ? 'Цель недели выполнена!'
                      : 'Цель на неделю: $done / $goal тренировок',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDone ? Colors.green : AppColors.accent,
              ),
            ),
          ),
          if (!isDone) ...[
            const SizedBox(height: 6),
            Text(
              'Осталось ${goal - done} ${_workoutWord(goal - done)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _workoutWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'тренировка';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'тренировки';
    }
    return 'тренировок';
  }
}

// ─── Inactivity suggestion card ───────────────────────────────────────────────

class _InactivityCard extends StatelessWidget {
  final int days;
  final Workout? nextWorkout;
  final VoidCallback onTap;

  const _InactivityCard({
    required this.days,
    required this.nextWorkout,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = nextWorkout != null
        ? 'Следующая: ${nextWorkout!.name}'
        : 'Откройте список тренировок';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.directions_run_rounded,
                  color: AppColors.accent, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Вы не тренировались $days ${_dayWord(days)}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  String _dayWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'день';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'дня';
    }
    return 'дней';
  }
}

// ─── Rest day card ────────────────────────────────────────────────────────────

class _RestDayCard extends StatelessWidget {
  const _RestDayCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1F0A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4A454).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFD4A454).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hotel_rounded,
                color: Color(0xFFD4A454), size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Сегодня день отдыха 🛏',
                  style: TextStyle(
                    color: Color(0xFFD4A454),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Восстановитесь и наберитесь сил',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
