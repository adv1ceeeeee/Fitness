import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
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
import 'package:sportwai/services/app_cache.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/body_metrics_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/screens/shared/feedback_sheets.dart';
import 'package:sportwai/services/feedback_service.dart';
import 'package:sportwai/services/wellness_service.dart';
import 'package:sportwai/services/recsys_service.dart';
import 'package:sportwai/services/local_storage.dart';
import 'package:sportwai/services/workout_service.dart';
import 'package:sportwai/data/standard_programs.dart';

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

/// Returns the week key for the weekly summary (date of the preceding Sunday).
/// Format: "yyyy-MM-dd".  Example: Monday 2026-03-16 → "2026-03-15".
String weeklySummaryKeyFor(DateTime now) {
  final daysSinceSunday = now.weekday % 7; // 0=Sun, 1=Mon … 6=Sat
  final sunday = DateTime(now.year, now.month, now.day - daysSinceSunday);
  return '${sunday.year}-'
      '${sunday.month.toString().padLeft(2, '0')}-'
      '${sunday.day.toString().padLeft(2, '0')}';
}

/// Returns true only on Sunday, Monday, or Tuesday (the grace window for
/// showing the previous week's summary).
bool shouldShowWeeklySummaryOn(DateTime now) => now.weekday % 7 <= 2;

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
  Workout? _overrideWorkout; // user-selected program override for "Начать"
  bool _loadingWorkout = true;
  bool _wellnessLogged = true;
  Map<String, dynamic>? _todayWellness;
  WellnessRec? _wellnessRec;
  EnergyState? _energyState;

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
  int _streak = 0;
  Workout? _nextScheduledWorkout;
  bool _isRestDay = false;

  // Countdown to next planned workout
  DateTime? _todayPlannedTime;
  Timer? _countdownTimer;
  Duration? _timeUntilWorkout;

  @override
  void initState() {
    super.initState();
    _load();
    _loadOverrideWorkout();
    _showOnboardingOnce();
    _checkCrashRecovery();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (await FeedbackService.shouldShowMicroSurvey()) {
        if (mounted) await showMicroSurveySheet(context);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(DateTime plannedTime) {
    _countdownTimer?.cancel();
    _updateCountdown(plannedTime);
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _updateCountdown(plannedTime);
    });
  }

  void _updateCountdown(DateTime plannedTime) {
    final diff = plannedTime.difference(DateTime.now());
    setState(() {
      _timeUntilWorkout = diff.isNegative ? null : diff;
    });
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
    // Phase 1: show cached data immediately (no skeleton if cache exists)
    await _loadCached();
    // Phase 2: refresh from network silently in background
    _refreshFresh();
  }

  Future<void> _loadCached() async {
    if (!mounted) return;
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;

    // Skip stale phase-1 data to avoid flash (e.g. 0→1 workouts this week)
    final statsAreFresh = await AppCache.isFresh(
      'workouts_week:$userId',
      maxAge: const Duration(minutes: 10),
    );
    if (!statsAreFresh) return;

    final results = await Future.wait([
      AppCache.peek<int>(
        key: 'workouts_week:$userId',
        decode: (s) => int.tryParse(s) ?? 0,
      ),
      AppCache.peek<List<Map<String, dynamic>>>(
        key: 'body_metrics:$userId',
        decode: (s) => (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
      ),
    ]);

    final cachedWorkoutsThisWeek = results[0] as int?;
    final cachedBodyMetrics = results[1] as List<Map<String, dynamic>>?;

    if (cachedWorkoutsThisWeek == null && cachedBodyMetrics == null) return;
    if (!mounted) return;

    setState(() {
      if (cachedWorkoutsThisWeek != null) {
        _workoutsThisWeek = cachedWorkoutsThisWeek;
      }
      if (cachedBodyMetrics != null) {
        _bodyMetricsHistory = cachedBodyMetrics;
        if (cachedBodyMetrics.isEmpty) {
          _showMeasurementReminder = true;
        } else {
          final lastDateStr = cachedBodyMetrics.last['date'] as String?;
          if (lastDateStr != null) {
            final lastDate = DateTime.tryParse(lastDateStr);
            if (lastDate != null &&
                DateTime.now().difference(lastDate).inDays > 28) {
              _showMeasurementReminder = true;
            }
          }
        }
      }
      _loadingWorkout = false;
    });
  }

  Future<void> _refreshFresh() async {
    if (!mounted) return;
    try {
      await AppCache.withForceRefresh(() async {
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
        AnalyticsService.getCurrentStreak(),
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
      final streak = results[7] as int;
      // Check if today is a rest day in any active workout
      final todayAppDay = DateTime.now().weekday - 1; // 0=Mon…6=Sun
      final allWorkouts = await WorkoutService.getMyWorkouts();
      final isRestDay = allWorkouts.any((w) => w.restDays.contains(todayAppDay));
      // Load next scheduled workout if inactive for 2+ days
      Workout? nextWorkout;
      if (daysSince >= 2 && !isRestDay) {
        nextWorkout = results[1] as Workout? ?? await TrainingService.getNextScheduledWorkout();
      }
      // Load planned time for today's session (for countdown)
      final plannedTime = await TrainingService.getTodayPlannedTime();

      if (!mounted) return;
      setState(() {
        _profile = results[0] as Profile?;
        _todayWorkout = results[1] as Workout?;
        _loadingWorkout = false;
        _wellnessLogged = results[2] != null;
        _todayWellness = results[2] as Map<String, dynamic>?;
        _wellnessRec = evaluateWellness(_todayWellness);
        _insight = results[3] as WorkoutInsight?;
        // Energy state loaded separately (cached 30 min via AppCache).
        _bodyMetricsHistory = metricsHistory;
        _showMeasurementReminder = showReminder;
        _weeklyWorkoutGoal = weeklyGoal;
        _workoutsThisWeek = results[5] as int;
        _daysSinceLastWorkout = daysSince;
        _nextScheduledWorkout = nextWorkout;
        _isRestDay = isRestDay;
        _todayPlannedTime = plannedTime;
        _streak = streak;
      });
      if (plannedTime != null) _startCountdown(plannedTime);
      _maybeShowWeeklySummary(weeklyGoal);
      _maybeShowDeloadSuggestion();
      // Load energy state independently (cached 30 min — doesn't block main load).
      AnalyticsService.getEnergyState().then((es) {
        if (mounted) setState(() => _energyState = es);
      }).catchError((_) {});
      }); // end withForceRefresh
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

  /// Показывает еженедельный отчёт в воскресенье, понедельник или вторник,
  /// если он ещё не показывался на этой неделе и функция включена.
  void _maybeShowWeeklySummary(int weeklyGoal) {
    if (!AppStorage.weeklySummaryEnabled) return;
    final now = DateTime.now();
    if (!shouldShowWeeklySummaryOn(now)) return;

    final weekKey = weeklySummaryKeyFor(now);
    if (AppStorage.lastWeeklySummaryShownWeek == weekKey) return;

    // Откладываем до следующего кадра, чтобы Scaffold был готов
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await AppStorage.setLastWeeklySummaryShownWeek(weekKey);
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _WeeklySummarySheet(weeklyGoal: weeklyGoal),
      );
    });
  }

  Future<void> _maybeShowDeloadSuggestion() async {
    if (AppStorage.deloadActive) return; // уже включён
    final today = DateTime.now().toIso8601String().split('T')[0];
    if (AppStorage.lastDeloadSuggestionDate == today) return; // уже показывали сегодня
    final suggest = await AnalyticsService.shouldSuggestDeload();
    if (!suggest || !mounted) return;
    await AppStorage.setLastDeloadSuggestionDate(today);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text(
            'Пора на deload?',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: const Text(
            '4 недели подряд твой объём выше среднего. '
            'Неделя с пониженным весом поможет восстановиться и избежать плато.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Не сейчас',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await AppStorage.setDeloadActive(true);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Deload-режим включён (-40% веса)')),
                  );
                }
              },
              child: const Text('Включить deload',
                  style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      );
    });
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
      if (kDebugMode) debugPrint('[HomeScreen] _loadGoalPrefs error: $e');
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
      if (kDebugMode) debugPrint('[HomeScreen] _saveGoalTarget error: $e');
    }
  }

  static const _kOverrideWorkoutKey = 'home_override_workout_id';

  Future<void> _loadOverrideWorkout() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_kOverrideWorkoutKey);
    if (savedId == null) return;
    final workout = await WorkoutService.getWorkout(savedId);
    if (mounted && workout != null) {
      setState(() => _overrideWorkout = workout);
    } else if (workout == null) {
      // Workout was deleted — clear saved preference
      prefs.remove(_kOverrideWorkoutKey);
    }
  }

  Future<void> _saveOverrideWorkout(String? workoutId) async {
    final prefs = await SharedPreferences.getInstance();
    if (workoutId == null) {
      await prefs.remove(_kOverrideWorkoutKey);
    } else {
      await prefs.setString(_kOverrideWorkoutKey, workoutId);
    }
  }

  void _showChangeProgramSheet() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ChangeProgramSheet(
        currentWorkoutId: (_overrideWorkout ?? _todayWorkout)?.id,
        onSelected: (workout) {
          Navigator.of(ctx).pop();
          setState(() => _overrideWorkout = workout);
          _saveOverrideWorkout(workout.id);
        },
        onManageAll: () {
          Navigator.of(ctx).pop();
          context.go('/workouts');
        },
      ),
    );
  }

  Future<void> _startDisplayedWorkout() async {
    final workout = _overrideWorkout ?? _todayWorkout;
    if (workout == null) return;
    // If it's the scheduled workout, use the today screen flow
    if (_overrideWorkout == null) {
      context.push('/today');
      return;
    }
    // Override workout: create/get a session and go straight to it
    final session = await TrainingService.getOrCreateTodaySession(workout.id);
    if (!mounted || session == null) return;
    context.push('/session/${session.id}');
  }

  @override
  Widget build(BuildContext context) {
    final rawName = _profile?.fullName?.split(' ').first ?? 'Атлет';
    final name = rawName.isNotEmpty
        ? '${rawName[0].toUpperCase()}${rawName.substring(1)}'
        : 'Атлет';

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
                _GreetingHeader(
                  name: name,
                  timeUntilWorkout: _timeUntilWorkout,
                  plannedTime: _todayPlannedTime,
                  streak: _streak,
                ),
                const SizedBox(height: 24),
                _TodayCard(
                  workout: _overrideWorkout ?? _todayWorkout,
                  loading: _loadingWorkout,
                  onTap: _startDisplayedWorkout,
                  onCreateProgram: _showChangeProgramSheet,
                  onQuickStart: () => showModalBottomSheet<void>(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    backgroundColor: AppColors.card,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (ctx) => _QuickStartSheet(
                      onCreated: (workoutId) {
                        context.push('/workouts/$workoutId/exercises');
                      },
                    ),
                  ),
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

                // ── Wellness check-in ─────────────────────────────────────
                if (!_wellnessLogged) ...[
                  const SizedBox(height: 16),
                  _WellnessCard(
                    onSaved: () async {
                      final log = await WellnessService.getTodayLog();
                      if (mounted) setState(() {
                        _wellnessLogged = true;
                        _todayWellness = log;
                        _wellnessRec = evaluateWellness(log);
                      });
                    },
                  ),
                ],

                // ── Wellness advice ───────────────────────────────────────
                if (_todayWellness != null) ...[
                  const SizedBox(height: 16),
                  _WellnessAdviceCard(wellness: _todayWellness!),
                ],

                // ── Achievement card ──────────────────────────────────────
                if (_insight != null) ...[
                  const SizedBox(height: 16),
                  _AchievementCard(insight: _insight!),
                ],

                // ── Wellness recommendation ───────────────────────────────
                if (_wellnessRec != null) ...[
                  const SizedBox(height: 16),
                  _WellnessRecBanner(
                    rec: _wellnessRec!,
                    onDismiss: () => setState(() => _wellnessRec = null),
                  ),
                ],

                // ── Energy readiness card ─────────────────────────────────
                if (_energyState != null) ...[
                  const SizedBox(height: 16),
                  _EnergyReadinessCard(state: _energyState!),
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
                  metric: _goalMetric,
                  currentValue: () {
                    for (final m in _bodyMetricsHistory.reversed) {
                      if (m[_goalMetric] != null) return (m[_goalMetric] as num).toDouble();
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
                Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.calendar_month_rounded,
                        label: 'Календарь тренировок',
                        onTap: () => context.push('/calendar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.monitor_weight_rounded,
                        label: 'Параметры тела',
                        onTap: () => context.push('/body-metrics'),
                      ),
                    ),
                  ],
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

// ─── Energy Readiness Card ────────────────────────────────────────────────────

class _EnergyReadinessCard extends StatelessWidget {
  final EnergyState state;
  const _EnergyReadinessCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final bucket = state.bucket;

    // Colour: green for peak, amber for mid, red for depleted
    final Color color;
    final IconData icon;
    if (bucket <= 2) {
      color = const Color(0xFF30D158); // green
      icon  = Icons.bolt_rounded;
    } else if (bucket <= 4) {
      color = const Color(0xFF30D158);
      icon  = Icons.fitness_center_rounded;
    } else if (bucket <= 6) {
      color = const Color(0xFFFF9F0A); // amber
      icon  = Icons.show_chart_rounded;
    } else if (bucket <= 8) {
      color = const Color(0xFFFF6B35); // orange
      icon  = Icons.trending_down_rounded;
    } else {
      color = const Color(0xFFFF453A); // red
      icon  = Icons.warning_amber_rounded;
    }

    final pct = state.reserve.toStringAsFixed(0);
    final subtitle = switch (bucket) {
      <= 2 => 'Отличное время для тяжёлой тренировки.',
      <= 4 => 'Хорошее состояние — тренируйся в обычном режиме.',
      <= 6 => 'Умеренная усталость — слушай тело, не перегружайся.',
      <= 8 => 'Организм не восстановился — рассмотри лёгкую тренировку.',
      _    => 'Критическая усталость — рекомендуется полный отдых.',
    };

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Готовность: ${state.label} ($pct%) · бакет $bucket/10',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Wellness Recommendation Banner ──────────────────────────────────────────

class _WellnessRecBanner extends StatelessWidget {
  final WellnessRec rec;
  final VoidCallback onDismiss;

  const _WellnessRecBanner({required this.rec, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (rec.severity) {
      RecSeverity.critical => (const Color(0xFFFF453A), Icons.warning_rounded),
      RecSeverity.warning  => (const Color(0xFFFF9F0A), Icons.info_outline_rounded),
      RecSeverity.info     => (AppColors.accent,        Icons.info_outline_rounded),
    };
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rec.title,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rec.message,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
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

  /// Exponentially weighted OLS → estimated time to reach goal.
  /// Recent measurements carry more weight (λ = 0.07 per day ≈ half-life ~10d).
  /// Returns null when: < 3 points, flat trend, wrong direction, or > 2 years.
  String? _forecastText(double current) {
    if (target == null) return null;
    final diff = target! - current; // signed: positive = need to grow
    if (diff.abs() < 0.05) return null; // already at goal

    // Only last 30 days — old data is irrelevant for near-term forecasting
    final cutoff = DateTime.now().subtract(const Duration(days: 30));

    // Build (x=days_offset, y=value) series, oldest→newest
    final points = <(double, double)>[];
    DateTime? first;
    for (final m in metricsHistory) {
      final raw = m[metric];
      if (raw == null) continue;
      final dateStr = m['date'] as String?;
      if (dateStr == null || dateStr.length < 10) continue;
      final dt = DateTime.tryParse(dateStr);
      if (dt == null || dt.isBefore(cutoff)) continue;
      first ??= dt;
      final x = dt.difference(first).inHours / 24.0;
      points.add((x, (raw as num).toDouble()));
    }
    if (points.length < 3) return null;

    // Exponential decay weight: w_i = exp(-λ · (x_max − x_i))
    // → most recent point always gets w = 1.0; a point 10 days older gets ≈ 0.50
    const lambda = 0.07;
    final xMax = points.last.$1;

    double sw = 0, swx = 0, swy = 0, swxy = 0, swx2 = 0;
    for (final p in points) {
      final w = math.exp(-lambda * (xMax - p.$1));
      sw   += w;
      swx  += w * p.$1;
      swy  += w * p.$2;
      swxy += w * p.$1 * p.$2;
      swx2 += w * p.$1 * p.$1;
    }

    final det = sw * swx2 - swx * swx;
    if (det.abs() < 1e-9) return null; // all points on the same day
    final slope = (sw * swxy - swx * swy) / det;

    if (slope.abs() < 0.001) return null; // essentially flat
    if (diff > 0 && slope <= 0) return null; // need to grow, but declining
    if (diff < 0 && slope >= 0) return null; // need to shrink, but growing

    final daysToGoal = diff / slope;
    if (daysToGoal <= 0 || daysToGoal > 730) return null;

    final weeks = (daysToGoal / 7).round();
    if (weeks < 1) {
      final d = daysToGoal.round().clamp(1, 6);
      return '~$d дн.';
    }
    return '~$weeks нед.';
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
    final base = 'До цели: $sign${fmtMetricValue(diff)} $_unit';
    final forecast = _forecastText(current);
    return forecast != null ? '$base  ($forecast)' : base;
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

// ─── Skeleton placeholder ─────────────────────────────────────────────────────

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  // ignore: unused_element_parameter
  const _SkeletonBox({required this.width, required this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
      highlightColor: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// ─── Greeting header ──────────────────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  final String name;
  final Duration? timeUntilWorkout;
  final DateTime? plannedTime;
  final int streak;

  const _GreetingHeader({
    required this.name,
    required this.timeUntilWorkout,
    required this.plannedTime,
    this.streak = 0,
  });

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Доброе утро';
    if (hour < 18) return 'Добрый день';
    return 'Добрый вечер';
  }

  @override
  Widget build(BuildContext context) {
    final countdown = timeUntilWorkout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_greeting()}, $name!',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (streak > 0) ...[
              _StreakChip(streak: streak),
              const SizedBox(width: 8),
            ],
            if (countdown != null && plannedTime != null)
              _CountdownChip(duration: countdown, plannedTime: plannedTime!),
          ],
        ),
      ],
    );
  }
}

class _StreakChip extends StatelessWidget {
  final int streak;
  const _StreakChip({required this.streak});

  String _label() {
    if (streak == 1) return '1 день подряд';
    if (streak < 5) return '$streak дня подряд';
    return '$streak дней подряд';
  }

  @override
  Widget build(BuildContext context) {
    final hot = streak >= 7;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: hot
            ? const Color(0xFFFF9F0A).withValues(alpha: 0.15)
            : AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hot
              ? const Color(0xFFFF9F0A).withValues(alpha: 0.5)
              : AppColors.separator,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            _label(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: hot ? FontWeight.w600 : FontWeight.w400,
              color: hot ? const Color(0xFFFF9F0A) : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  final Duration duration;
  final DateTime plannedTime;

  const _CountdownChip({required this.duration, required this.plannedTime});

  String _format() {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    if (h > 0) return '$h ч ${m.toString().padLeft(2, '0')} мин';
    if (m > 0) return '$m мин';
    return 'Сейчас!';
  }

  String _timeLabel() {
    final h = plannedTime.hour.toString().padLeft(2, '0');
    final m = plannedTime.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final isIminent = duration.inMinutes <= 15;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isIminent ? AppColors.accent : AppColors.card),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 14,
            color: isIminent ? Colors.white : AppColors.accent,
          ),
          const SizedBox(width: 6),
          Text(
            'До тренировки (${_timeLabel()}): ${_format()}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isIminent ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Change Program Sheet ─────────────────────────────────────────────────────

class _ChangeProgramSheet extends StatefulWidget {
  final void Function(Workout workout) onSelected;
  final VoidCallback onManageAll;
  final String? currentWorkoutId;

  const _ChangeProgramSheet({
    required this.onSelected,
    required this.onManageAll,
    this.currentWorkoutId,
  });

  @override
  State<_ChangeProgramSheet> createState() => _ChangeProgramSheetState();
}

class _ChangeProgramSheetState extends State<_ChangeProgramSheet> {
  List<Workout>? _workouts;

  static const Color _kPremiumColor = Color(0xFFFFB800);
  static const Color _kUserColor = Color(0xFFAB7FF8);

  Color _iconColor(String name) {
    if (premiumWorkoutNames.contains(name)) return _kPremiumColor;
    if (allStandardWorkoutNames.contains(name)) return AppColors.accent;
    return _kUserColor;
  }

  @override
  void initState() {
    super.initState();
    WorkoutService.getMyWorkouts().then((list) {
      if (mounted) setState(() => _workouts = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Выбрать программу',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_workouts == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_workouts!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              child: Text(
                'Нет программ. Создайте первую программу тренировок.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shrinkWrap: true,
                itemCount: _workouts!.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final w = _workouts![i];
                  final color = _iconColor(w.name);
                  final isActive = w.id == widget.currentWorkoutId;
                  return Material(
                    color: isActive
                        ? color.withValues(alpha: 0.1)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => widget.onSelected(w),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.fitness_center_rounded,
                                  size: 18, color: color),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                w.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (isActive)
                              Icon(Icons.check_rounded,
                                  size: 18, color: color)
                            else
                              const Icon(Icons.chevron_right_rounded,
                                  size: 20, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomPad),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onManageAll,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: BorderSide(
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Управлять программами'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Schedule badge helpers ───────────────────────────────────────────────────

/// Returns (label, isToday) for the schedule badge on the today card.
/// days: 0=Пн … 6=Вс. Empty list = freestyle, shown as "СЕГОДНЯ".
({String label, bool isToday}) _workoutScheduleBadge(List<int> days) {
  if (days.isEmpty) return (label: 'СЕГОДНЯ', isToday: true);

  // Dart weekday: 1=Mon…7=Sun → convert to 0=Mon…6=Sun
  final today = DateTime.now().weekday - 1;

  if (days.contains(today)) return (label: 'СЕГОДНЯ', isToday: true);

  // Find closest upcoming day
  int minDays = 7;
  for (final d in days) {
    final diff = (d - today + 7) % 7;
    if (diff > 0 && diff < minDays) minDays = diff;
  }

  if (minDays == 1) return (label: 'ЗАВТРА', isToday: false);
  return (label: 'ЧЕРЕЗ $minDays ДН.', isToday: false);
}

// ─── Today Card ───────────────────────────────────────────────────────────────

class _TodayCard extends StatelessWidget {
  final Workout? workout;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback? onCreateProgram;
  final VoidCallback? onQuickStart;

  const _TodayCard({
    required this.workout,
    required this.loading,
    required this.onTap,
    this.onCreateProgram,
    this.onQuickStart,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonBox(width: 120, height: 14),
            SizedBox(height: 12),
            _SkeletonBox(width: 200, height: 20),
            SizedBox(height: 8),
            _SkeletonBox(width: 80, height: 12),
          ],
        ),
      );
    }
    final hasWorkout = workout != null;

    // ── Empty state for new users ──────────────────────────────────────────────
    if (!hasWorkout) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Subtle accent glow in the top-right corner
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.fitness_center_rounded,
                        size: 48,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Title
                    const Text(
                      'Начни своё первое занятие',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Subtitle
                    const Text(
                      'Создай программу тренировок — и мы всё настроим за тебя',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // CTA button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onCreateProgram,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Создать программу',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: onQuickStart,
                        child: const Text(
                          'Начать с готовой программы',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Workout exists — hero card (matches programs-tab style) ──────────────
    const Color kPremiumColor = Color(0xFFFFB800);
    const Color kUserColor = Color(0xFFAB7FF8);
    final bool isPremium = premiumWorkoutNames.contains(workout!.name);
    final bool isUserCreated = !allStandardWorkoutNames.contains(workout!.name);
    final Color iconColor = isPremium ? kPremiumColor : isUserCreated ? kUserColor : AppColors.accent;

    final badge = _workoutScheduleBadge(workout!.days);
    final badgeColor = badge.isToday ? AppColors.accent : AppColors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + name row (matches _WorkoutCardContent layout)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.fitness_center_rounded,
                  color: iconColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        badge.label,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      workout!.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // «Начать тренировку» — primary action
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Начать тренировку',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // «Изменить программу» — secondary action
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onCreateProgram,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Изменить программу',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Wellness advice card ─────────────────────────────────────────────────────

class _WellnessAdviceCard extends StatelessWidget {
  final Map<String, dynamic> wellness;
  const _WellnessAdviceCard({required this.wellness});

  String get _advice {
    final energy = wellness['energy'] as int?;
    final stress = wellness['stress'] as int?;
    final sleep = (wellness['sleep_hours'] as num?)?.toDouble();
    final soreness = wellness['soreness'] as int?;

    if (energy != null && energy <= 3) return 'Низкий уровень энергии — лучше отдохни или сделай лёгкую растяжку.';
    if (stress != null && stress >= 8) return 'Высокий стресс — избегай перегрузок, сфокусируйся на восстановлении.';
    if (sleep != null && sleep < 5.0) return 'Мало сна — организм не восстановился, избегай интенсивных нагрузок.';
    if (soreness != null && soreness >= 4) return 'Высокая крепатура — потренируй другие группы мышц или возьми день отдыха.';
    if (energy != null && energy <= 5) return 'Умеренный уровень энергии — подойдёт тренировка средней интенсивности.';
    if (sleep != null && sleep < 6.5) return 'Маловато сна — снизь интенсивность тренировки сегодня.';
    return 'Отличное состояние — хороший день для интенсивной тренировки!';
  }

  IconData get _icon {
    final energy = wellness['energy'] as int?;
    final stress = wellness['stress'] as int?;
    final sleep = (wellness['sleep_hours'] as num?)?.toDouble();
    final soreness = wellness['soreness'] as int?;
    final isBad = (energy != null && energy <= 3) ||
        (stress != null && stress >= 8) ||
        (sleep != null && sleep < 5.0) ||
        (soreness != null && soreness >= 4);
    final isMid = (energy != null && energy <= 5) || (sleep != null && sleep < 6.5);
    if (isBad) return Icons.bedtime_rounded;
    if (isMid) return Icons.trending_flat_rounded;
    return Icons.bolt_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _advice,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
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
  int _sleepQuality = 3;
  int _soreness = 3;
  bool _saving = false;
  bool _showExtra = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await WellnessService.upsert(
        sleepHours: _sleep,
        stress: _stress,
        energy: _energy,
        sleepQuality: _sleepQuality,
        soreness: _soreness,
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
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _showExtra = !_showExtra),
            child: Row(
              children: [
                Text(
                  _showExtra ? 'Свернуть' : 'Подробнее',
                  style: const TextStyle(color: AppColors.accent, fontSize: 13),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showExtra ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.accent,
                  size: 16,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _showExtra
                ? Column(
                    children: [
                      const SizedBox(height: 12),
                      _RatingRow(
                        label: 'Кач. сна',
                        value: _sleepQuality,
                        onChanged: (v) => setState(() => _sleepQuality = v),
                      ),
                      const SizedBox(height: 12),
                      _RatingRow(
                        label: 'Боль',
                        value: _soreness,
                        onChanged: (v) => setState(() => _soreness = v),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
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
          width: 96,
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

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
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
          child: Column(
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

// ─── Quick metric logging card ────────────────────────────────────────────────

class _QuickWeightCard extends StatefulWidget {
  final String metric;
  final double? currentValue;
  final Future<void> Function() onSaved;

  const _QuickWeightCard({
    this.metric = 'weight_kg',
    this.currentValue,
    required this.onSaved,
  });

  @override
  State<_QuickWeightCard> createState() => _QuickWeightCardState();
}

class _QuickWeightCardState extends State<_QuickWeightCard> {
  late TextEditingController _ctrl;
  bool _saving = false;
  bool _saved = false;
  // Only used for weight_kg (multi-log per day)
  List<Map<String, dynamic>> _todayWeightLogs = [];

  @override
  void initState() {
    super.initState();
    _ctrl = _buildController();
    if (widget.metric == 'weight_kg') _loadWeightLogs();
  }

  @override
  void didUpdateWidget(_QuickWeightCard old) {
    super.didUpdateWidget(old);
    if (old.metric != widget.metric || old.currentValue != widget.currentValue) {
      _ctrl.dispose();
      _ctrl = _buildController();
      _todayWeightLogs = [];
      if (widget.metric == 'weight_kg') _loadWeightLogs();
    }
  }

  TextEditingController _buildController() {
    final hint = widget.currentValue;
    return TextEditingController(
        text: hint != null ? fmtMetricValue(hint) : '');
  }

  Future<void> _loadWeightLogs() async {
    final logs = await BodyMetricsService.getTodayWeightLogs();
    if (mounted) setState(() => _todayWeightLogs = logs);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _unit => _metricOptions[widget.metric]?.$2 ?? '';
  String get _label => _metricOptions[widget.metric]?.$1 ?? widget.metric;
  bool get _isWeight => widget.metric == 'weight_kg';

  Future<void> _save({bool updateDaily = true}) async {
    final v = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (v == null || v <= 0) return;
    setState(() => _saving = true);
    try {
      if (_isWeight) {
        await BodyMetricsService.logWeight(v, updateDaily: updateDaily);
        await _loadWeightLogs();
      } else {
        await BodyMetricsService.upsert(
          weightKg:       widget.metric == 'weight_kg'       ? v : null,
          bodyFatPct:     widget.metric == 'body_fat_pct'    ? v : null,
          waistCm:        widget.metric == 'waist_cm'        ? v : null,
          chestCm:        widget.metric == 'chest_cm'        ? v : null,
          hipsCm:         widget.metric == 'hips_cm'         ? v : null,
          rightArmCm:     widget.metric == 'right_arm_cm'    ? v : null,
          shouldersCm:    widget.metric == 'shoulders_cm'    ? v : null,
        );
      }
      await widget.onSaved();
      if (mounted) setState(() { _saving = false; _saved = true; });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить $_label')),
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
          color: secondary ? AppColors.surface : AppColors.accent,
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
    final hasTodayWeightLogs = _isWeight && _todayWeightLogs.isNotEmpty;

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
              Icon(
                _isWeight ? Icons.monitor_weight_outlined : Icons.straighten_rounded,
                color: AppColors.accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                '$_label сегодня',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w500),
              ),
              if (hasTodayWeightLogs) ...[
                const Spacer(),
                Builder(builder: (_) {
                  final log = _todayWeightLogs.last;
                  final w = (log['weight_kg'] as num).toDouble();
                  final t = _formatTime(log['measured_at'] as String);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$t · ${fmtMetricValue(w)} кг',
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
                  decoration: InputDecoration(
                    hintText: '—',
                    suffixText: _unit,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                        : hasTodayWeightLogs
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
          if (hasTodayWeightLogs)
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
    final ringColor = isDone ? const Color(0xFF4CAF50) : AppColors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          // ── Circular ring ──────────────────────────────────────────────
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 7,
                    backgroundColor: AppColors.surface,
                    valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$done',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: ringColor,
                        height: 1,
                      ),
                    ),
                    Text(
                      'из $goal',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // ── Labels ────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDone ? 'Цель недели выполнена! 🎉' : 'Цель на неделю',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDone ? const Color(0xFF4CAF50) : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                if (isDone)
                  const Text(
                    'Отличная работа, так держать!',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  )
                else ...[
                  Text(
                    'Осталось ${goal - done} ${_workoutWord(goal - done)}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  // Mini progress dots
                  Row(
                    children: List.generate(goal, (i) => Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < done ? ringColor : AppColors.surface,
                        ),
                      ),
                    )),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _workoutWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'тренировка';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'тренировки';
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

// ─── Quick start sheet ────────────────────────────────────────────────────────

class _QuickTemplate {
  final String name;
  final String description;
  final String emoji;
  final List<int> days; // 0=Пн … 6=Вс

  const _QuickTemplate({
    required this.name,
    required this.description,
    required this.emoji,
    required this.days,
  });
}

class _QuickStartSheet extends StatefulWidget {
  final ValueChanged<String> onCreated; // receives new workout id

  const _QuickStartSheet({required this.onCreated});

  @override
  State<_QuickStartSheet> createState() => _QuickStartSheetState();
}

class _QuickStartSheetState extends State<_QuickStartSheet> {
  static const _templates = [
    _QuickTemplate(
      emoji: '💪',
      name: 'Фулл боди · 3 дня',
      description: 'Пн · Ср · Пт — прорабатываем всё тело на каждой тренировке',
      days: [0, 2, 4],
    ),
    _QuickTemplate(
      emoji: '🏋',
      name: 'Верх / Низ · 4 дня',
      description: 'Пн · Вт · Чт · Пт — чередование верха и низа тела',
      days: [0, 1, 3, 4],
    ),
    _QuickTemplate(
      emoji: '🔥',
      name: 'Push–Pull–Legs · 6 дней',
      description: 'Пн–Сб — классическое разделение на жим / тяга / ноги',
      days: [0, 1, 2, 3, 4, 5],
    ),
    _QuickTemplate(
      emoji: '🚀',
      name: 'Два дня в неделю',
      description: 'Вт · Пт — минимальная нагрузка для поддержания формы',
      days: [1, 4],
    ),
  ];

  bool _loading = false;

  Future<void> _select(_QuickTemplate t) async {
    setState(() => _loading = true);
    try {
      final workout = await WorkoutService.createWorkout(t.name, t.days);
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated(workout.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Готовые программы',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Выберите шаблон — добавьте упражнения и начинайте',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else
            ...List.generate(_templates.length, (i) {
              final t = _templates[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _select(t),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: AppColors.surface,
                  leading: Text(t.emoji, style: const TextStyle(fontSize: 28)),
                  title: Text(
                    t.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    t.description,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.textSecondary),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─── Weekly summary sheet ─────────────────────────────────────────────────────

class _WeeklySummarySheet extends StatefulWidget {
  final int weeklyGoal;
  const _WeeklySummarySheet({required this.weeklyGoal});

  @override
  State<_WeeklySummarySheet> createState() => _WeeklySummarySheetState();
}

class _WeeklySummarySheetState extends State<_WeeklySummarySheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  bool _loading = true;
  int _workouts = 0;
  double _volumeKg = 0;
  int _streak = 0;
  int _prs = 0;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final data = await AnalyticsService.getWeeklySummaryData();
      if (mounted) {
        setState(() {
          _workouts = data.workouts;
          _volumeKg = data.volumeKg;
          _streak = data.streak;
          _prs = data.prs;
          _loading = false;
        });
        _fadeCtrl.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _motivationText() {
    final goal = widget.weeklyGoal;
    if (goal > 0 && _workouts >= goal) return 'Цель недели выполнена! Отличная работа!';
    if (_workouts == 0) return 'На этой неделе ещё есть время начать. Вперёд!';
    if (goal > 0 && _workouts < goal) {
      return 'Ещё ${goal - _workouts} тренировки до цели — ты справишься!';
    }
    if (_streak >= 7) return 'Серия $_streak дней — это уже настоящая привычка!';
    if (_prs > 0) return '$_prs личных рекорда за неделю — огонь!';
    return 'Хорошая неделя, продолжай в том же духе!';
  }

  String _volLabel() {
    if (_volumeKg >= 1000) {
      return '${(_volumeKg / 1000).toStringAsFixed(1)} т';
    }
    return '${_volumeKg.toStringAsFixed(0)} кг';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bar_chart_rounded,
                    color: AppColors.accent, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Итоги недели',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Как прошла эта неделя',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: CircularProgressIndicator(),
            )
          else
            FadeTransition(
              opacity: _fade,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryTile(
                          emoji: '🏋',
                          value: '$_workouts',
                          label: 'тренировок',
                          sub: widget.weeklyGoal > 0
                              ? 'цель: ${widget.weeklyGoal}'
                              : null,
                          highlight: widget.weeklyGoal > 0 &&
                              _workouts >= widget.weeklyGoal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryTile(
                          emoji: '📦',
                          value: _volLabel(),
                          label: 'объём',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryTile(
                          emoji: '🔥',
                          value: '$_streak',
                          label: 'дней серии',
                          highlight: _streak >= 7,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryTile(
                          emoji: '🏆',
                          value: '$_prs',
                          label: 'личных рекорда',
                          highlight: _prs > 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      _motivationText(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отлично, вперёд!'),
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

class _SummaryTile extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final String? sub;
  final bool highlight;

  const _SummaryTile({
    required this.emoji,
    required this.value,
    required this.label,
    this.sub,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.accent.withValues(alpha: 0.12)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: highlight
            ? Border.all(color: AppColors.accent.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: highlight ? AppColors.accent : AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12),
          ),
          if (sub != null)
            Text(
              sub!,
              style: TextStyle(
                color: AppColors.accent.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}
