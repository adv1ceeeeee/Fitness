import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/services/achievement_service.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/app_cache.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/body_metrics_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/streak_freeze_service.dart';
import 'package:sportwai/widgets/skeleton.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final _shareKey = GlobalKey();

  Profile? _profile;
  int _totalWorkouts = 0;
  int _bestStreak = 0;
  int _workoutsThisWeek = 0;
  double _volumeThisWeek = 0;
  bool _loading = true;
  bool _sharing = false;

  List<Map<String, dynamic>> _trackedExercises = [];
  Map<String, dynamic>? _selectedExercise;
  Map<String, double> _exerciseProgress = {};
  double? _communityAvgExerciseWeight;
  bool _loadingChart = false;

  double? _communityAvgWeeklyVolume;

  List<Map<String, dynamic>> _bodyHistory = [];
  String _selectedBodyMetric = 'weight_kg';

  static const _bodyMetricOptions = <String, String>{
    'weight_kg':        'Вес (кг)',
    'neck_cm':          'Шея (см)',
    'shoulders_cm':     'Плечи (см)',
    'chest_cm':         'Грудь (см)',
    'waist_cm':         'Талия (см)',
    'hips_cm':          'Бёдра (см)',
    'left_thigh_cm':    'Бедро лев. (см)',
    'right_thigh_cm':   'Бедро пр. (см)',
    'left_calf_cm':     'Голень лев. (см)',
    'right_calf_cm':    'Голень пр. (см)',
    'left_forearm_cm':  'Предплечье лев. (см)',
    'right_forearm_cm': 'Предплечье пр. (см)',
  };

  Map<String, double> get _bodyMetricData {
    final result = <String, double>{};
    for (final row in _bodyHistory) {
      final date = row['date'] as String?;
      final v = row[_selectedBodyMetric];
      if (date != null && v != null) {
        result[date] = (v as num).toDouble();
      }
    }
    return result;
  }

  List<String> get _availableBodyMetrics => _bodyMetricOptions.keys
      .where((k) => _bodyHistory.any((r) => r[k] != null))
      .toList();

  Map<DateTime, double> _heatmapData = {};
  List<Achievement> _achievements = [];
  List<Map<String, dynamic>> _weeklyVolume = [];
  Map<String, int> _muscleBalance = {};
  Map<String, double> _muscleFrequency = {};
  List<Map<String, dynamic>> _caloriesPerSession = [];
  ({double volumeThisWeek, double volumeLastWeek, int sessionsThisWeek, int sessionsLastWeek})?
      _weekComparison;

  // New state variables
  List<Map<String, dynamic>> _topExercises = [];
  List<Map<String, dynamic>> _wellnessHistory = [];
  List<Map<String, dynamic>> _sessionDurations = [];
  List<Map<String, dynamic>> _sessionRpes = [];
  List<Map<String, dynamic>> _exerciseProgressList = [];

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    // Phase 1: load from cache (fast — no skeleton if cache exists)
    await _loadCached();
    // Phase 2: refresh from network in background (silent update)
    _refreshFresh();
  }

  Future<void> _loadCached() async {
    if (!mounted) return;
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;

    // Peek all keys in parallel
    final results = await Future.wait([
      AppCache.peek<int>(
        key: 'total_workouts:$userId',
        decode: (s) => int.tryParse(s) ?? 0,
      ),
      AppCache.peek<int>(
        key: 'best_streak:$userId',
        decode: (s) => int.tryParse(s) ?? 0,
      ),
      AppCache.peek<int>(
        key: 'workouts_week:$userId',
        decode: (s) => int.tryParse(s) ?? 0,
      ),
      AppCache.peek<double>(
        key: 'volume_week:$userId',
        decode: (s) => double.tryParse(s) ?? 0.0,
      ),
      AppCache.peek<List<Map<String, dynamic>>>(
        key: 'tracked_exercises:$userId',
        decode: (s) => (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
      ),
      AppCache.peek<List<Map<String, dynamic>>>(
        key: 'body_metrics:$userId',
        decode: (s) => (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
      ),
      AppCache.peek<List<Map<String, dynamic>>>(
        key: 'weekly_volume:$userId:26',
        decode: (s) => (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
      ),
      AppCache.peek<Map<String, dynamic>>(
        key: 'muscle_balance:$userId',
        decode: (s) => jsonDecode(s) as Map<String, dynamic>,
      ),
      AppCache.peek<Map<String, dynamic>>(
        key: 'muscle_freq:$userId',
        decode: (s) => jsonDecode(s) as Map<String, dynamic>,
      ),
      AppCache.peek<List<Map<String, dynamic>>>(
        key: 'calories_sessions:$userId:60',
        decode: (s) => (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
      ),
      AppCache.peek<double>(
        key: 'community_avg_vol',
        decode: (s) => double.tryParse(s) ?? 0.0,
      ),
      AppCache.peek<Map<String, dynamic>>(
        key: 'week_comparison:$userId',
        decode: (s) => jsonDecode(s) as Map<String, dynamic>,
      ),
      AppCache.peek<Map<String, dynamic>>(
        key: 'workout_heatmap:$userId',
        decode: (s) => jsonDecode(s) as Map<String, dynamic>,
      ),
      AppCache.peek<List<Map<String, dynamic>>>(
        key: 'session_durations:$userId:60',
        decode: (s) => (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
      ),
      AppCache.peek<List<Map<String, dynamic>>>(
        key: 'session_rpe:$userId:60',
        decode: (s) => (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
      ),
      AppCache.peek<List<Map<String, dynamic>>>(
        key: 'exercise_progress:$userId:12',
        decode: (s) => (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
      ),
    ]);

    // Check if ANY value was found in cache
    final anyFound = results.any((r) => r != null);
    if (!anyFound || !mounted) return;

    final muscleBalanceRaw = results[7] as Map<String, dynamic>?;
    final muscleFreqRaw = results[8] as Map<String, dynamic>?;
    final weekCmpRaw = results[11] as Map<String, dynamic>?;
    final heatmapRaw = results[12] as Map<String, dynamic>?;

    setState(() {
      _totalWorkouts = (results[0] as int?) ?? _totalWorkouts;
      _bestStreak = (results[1] as int?) ?? _bestStreak;
      _workoutsThisWeek = (results[2] as int?) ?? _workoutsThisWeek;
      _volumeThisWeek = (results[3] as double?) ?? _volumeThisWeek;
      _trackedExercises = (results[4] as List<Map<String, dynamic>>?) ?? _trackedExercises;
      _bodyHistory = (results[5] as List<Map<String, dynamic>>?) ?? _bodyHistory;
      _weeklyVolume = (results[6] as List<Map<String, dynamic>>?) ?? _weeklyVolume;
      if (muscleBalanceRaw != null) {
        _muscleBalance = muscleBalanceRaw.map((k, v) => MapEntry(k, (v as num).toInt()));
      }
      if (muscleFreqRaw != null) {
        _muscleFrequency = muscleFreqRaw.map((k, v) => MapEntry(k, (v as num).toDouble()));
      }
      _caloriesPerSession = (results[9] as List<Map<String, dynamic>>?) ?? _caloriesPerSession;
      _communityAvgWeeklyVolume = (results[10] as double?) ?? _communityAvgWeeklyVolume;
      if (weekCmpRaw != null) {
        _weekComparison = (
          volumeThisWeek: (weekCmpRaw['volumeThisWeek'] as num).toDouble(),
          volumeLastWeek: (weekCmpRaw['volumeLastWeek'] as num).toDouble(),
          sessionsThisWeek: (weekCmpRaw['sessionsThisWeek'] as num).toInt(),
          sessionsLastWeek: (weekCmpRaw['sessionsLastWeek'] as num).toInt(),
        );
      }
      if (heatmapRaw != null) {
        _heatmapData = heatmapRaw.map(
          (k, v) => MapEntry(DateTime.parse(k), (v as num).toDouble()),
        );
      }
      _sessionDurations = (results[13] as List<Map<String, dynamic>>?) ?? _sessionDurations;
      _sessionRpes = (results[14] as List<Map<String, dynamic>>?) ?? _sessionRpes;
      _exerciseProgressList = (results[15] as List<Map<String, dynamic>>?) ?? _exerciseProgressList;
      _loading = false;
    });
  }

  Future<void> _refreshFresh() async {
    if (!mounted) return;
    try {
      await Future(() async {
        final profile = await ProfileService.getProfile();
        final total = await AnalyticsService.getTotalWorkouts();
        final streak = await AnalyticsService.getBestStreak();
        final weekCount = await AnalyticsService.getWorkoutsThisWeek();
        final volume = await AnalyticsService.getVolumeThisWeek();
        final tracked = await AnalyticsService.getTrackedExercises();
        final bodyHistory = await BodyMetricsService.getHistory();
        final achievements = await AchievementService.getAchievements();
        final weeklyVol = await AnalyticsService.getWeeklyVolumeHistory();
        final muscleBalance = await AnalyticsService.getMuscleGroupBalance();
        final muscleFreq = await AnalyticsService.getMuscleGroupFrequency();
        final caloriesPerSession = await AnalyticsService.getCaloriesPerSession();
        final communityAvgVol = await AnalyticsService.getCommunityAvgWeeklyVolume();
        final weekCmp = await AnalyticsService.getWeekComparison();
        final heatmap = await AnalyticsService.getWorkoutHeatmap();
        final topExercises = await AnalyticsService.getTopExercisesByVolume();
        final wellnessHistory = await AnalyticsService.getWellnessHistory();
        final sessionDurations = await AnalyticsService.getSessionDurationHistory();
        final sessionRpes = await AnalyticsService.getSessionRpeHistory();
        final exerciseProgressList = await AnalyticsService.getTopExercisesByProgress();

        if (mounted) {
          setState(() {
            _profile = profile;
            _totalWorkouts = total;
            _bestStreak = streak;
            _workoutsThisWeek = weekCount;
            _volumeThisWeek = volume;
            _trackedExercises = tracked;
            _bodyHistory = bodyHistory;
            _achievements = achievements;
            _weeklyVolume = weeklyVol;
            _muscleBalance = muscleBalance;
            _muscleFrequency = muscleFreq;
            _caloriesPerSession = caloriesPerSession;
            _communityAvgWeeklyVolume = communityAvgVol;
            _weekComparison = weekCmp;
            _heatmapData = heatmap;
            _topExercises = topExercises;
            _wellnessHistory = wellnessHistory;
            _sessionDurations = sessionDurations;
            _sessionRpes = sessionRpes;
            _exerciseProgressList = exerciseProgressList;
            _loading = false;
          });
        }
      }).timeout(const Duration(seconds: 15));
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Не удалось загрузить статистику'),
            action: SnackBarAction(label: 'Повторить', onPressed: _load),
          ),
        );
      }
    }
  }

  Future<void> _loadExerciseProgress(String exerciseId) async {
    if (!mounted) return;
    setState(() => _loadingChart = true);
    final results = await Future.wait([
      AnalyticsService.getExerciseMaxWeight(exerciseId),
      AnalyticsService.getCommunityAvgExerciseWeight(exerciseId),
    ]);
    if (mounted) {
      setState(() {
        _exerciseProgress = results[0] as Map<String, double>;
        _communityAvgExerciseWeight = results[1] as double?;
        _loadingChart = false;
      });
    }
  }

  Future<void> _shareAsImage() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sportify_progress.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Мой прогресс в Sportify',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  static const _goalOptions = <String, String>{
    'strength': 'Сила',
    'weight_loss': 'Похудение',
    'mass_gain': 'Набор массы',
    'endurance': 'Выносливость',
  };

  static String _goalDisplay(String? goal) =>
      _goalOptions[goal ?? ''] ?? (goal ?? '—');

  Future<void> _changeGoal() async {
    final current = _profile?.goal;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                'Твоя цель',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (final entry in _goalOptions.entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(
                  entry.value,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: entry.key == current
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                trailing: entry.key == current
                    ? const Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(context, entry.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    try {
      await ProfileService.updateProfile({'goal': picked});
      setState(() => _profile = _profile?.copyWith(goal: picked));
      EventLogger.log('training_goal_set', props: {'goal': picked});
    } catch (e) {
      debugPrint('[AnalyticsScreen] _changeGoal error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SingleChildScrollView(child: AnalyticsSkeleton()),
      );
    }

    final name = _profile?.fullName?.split(' ').first ?? 'Атлет';
    final goal = _profile?.goal;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
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
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _changeGoal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Твоя цель: ${_goalDisplay(goal)}',
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit_rounded,
                            size: 13, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── Tab bar ─────────────────────────────────────────────────────
            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.accent,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textSecondary,
              dividerColor: AppColors.separator,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: const [
                Tab(text: 'Обзор'),
                Tab(text: 'Тренировки'),
                Tab(text: 'Тело'),
                Tab(text: 'Инсайты'),
              ],
            ),
            // ── Tab views ───────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Обзор
                  _OverviewTab(
                    onRefresh: _load,
                    profile: _profile,
                    bestStreak: _bestStreak,
                    totalWorkouts: _totalWorkouts,
                    workoutsThisWeek: _workoutsThisWeek,
                    volumeThisWeek: _volumeThisWeek,
                    weekComparison: _weekComparison,
                    heatmapData: _heatmapData,
                    achievements: _achievements,
                  ),
                  // Tab 2: Тренировки
                  _WorkoutsTab(
                    onRefresh: _load,
                    weeklyVolume: _weeklyVolume,
                    communityAvgWeeklyVolume: _communityAvgWeeklyVolume,
                    topExercises: _topExercises,
                    trackedExercises: _trackedExercises,
                    selectedExercise: _selectedExercise,
                    exerciseProgress: _exerciseProgress,
                    communityAvgExerciseWeight: _communityAvgExerciseWeight,
                    loadingChart: _loadingChart,
                    muscleBalance: _muscleBalance,
                    muscleFrequency: _muscleFrequency,
                    caloriesPerSession: _caloriesPerSession,
                    heatmapData: _heatmapData,
                    sessionDurations: _sessionDurations,
                    sessionRpes: _sessionRpes,
                    exerciseProgressList: _exerciseProgressList,
                    onExerciseChanged: (ex) {
                      setState(() {
                        _selectedExercise = ex;
                        _exerciseProgress = {};
                      });
                      if (ex != null) {
                        _loadExerciseProgress(ex['id'] as String);
                      }
                    },
                  ),
                  // Tab 3: Тело
                  _BodyTab(
                    onRefresh: _load,
                    bodyHistory: _bodyHistory,
                    bodyMetricOptions: _bodyMetricOptions,
                    availableBodyMetrics: _availableBodyMetrics,
                    selectedBodyMetric: _selectedBodyMetric,
                    bodyMetricData: _bodyMetricData,
                    wellnessHistory: _wellnessHistory,
                    onMetricChanged: (k) {
                      if (k != null) setState(() => _selectedBodyMetric = k);
                    },
                  ),
                  // Tab 4: Инсайты
                  _InsightsTab(
                    onRefresh: _load,
                    shareKey: _shareKey,
                    profile: _profile,
                    bestStreak: _bestStreak,
                    totalWorkouts: _totalWorkouts,
                    workoutsThisWeek: _workoutsThisWeek,
                    volumeThisWeek: _volumeThisWeek,
                    heatmapData: _heatmapData,
                    weeklyVolume: _weeklyVolume,
                    muscleBalance: _muscleBalance,
                    wellnessHistory: _wellnessHistory,
                    sharing: _sharing,
                    onShare: _shareAsImage,
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

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 1: Обзор
// ═══════════════════════════════════════════════════════════════════════════════

class _OverviewTab extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Profile? profile;
  final int bestStreak;
  final int totalWorkouts;
  final int workoutsThisWeek;
  final double volumeThisWeek;
  final ({double volumeThisWeek, double volumeLastWeek, int sessionsThisWeek, int sessionsLastWeek})? weekComparison;
  final Map<DateTime, double> heatmapData;
  final List<Achievement> achievements;

  const _OverviewTab({
    required this.onRefresh,
    required this.profile,
    required this.bestStreak,
    required this.totalWorkouts,
    required this.workoutsThisWeek,
    required this.volumeThisWeek,
    required this.weekComparison,
    required this.heatmapData,
    required this.achievements,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(context).padding.bottom + 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StreakCard(
              streak: bestStreak,
              totalWorkouts: totalWorkouts,
              freezeActive: StreakFreezeService.freezeIsActive,
              hasFreeze: StreakFreezeService.hasFreeze,
            ),
            const SizedBox(height: 20),
            // Monthly calendar heatmap
            const Text(
              'Активность в этом месяце',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _MonthCalendar(heatmapData: heatmapData),
            const SizedBox(height: 20),
            const Text(
              'Статистика за неделю',
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
                  child: _StatBox(
                    label: 'Тренировок',
                    value: workoutsThisWeek.toDouble(),
                    format: (v) => v.round().toString(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatBox(
                    label: 'Объём (кг)',
                    value: volumeThisWeek,
                    format: (v) => v.toStringAsFixed(0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (weekComparison != null)
              _WeekComparisonCard(cmp: weekComparison!),
            const SizedBox(height: 20),
            _NavCard(
              icon: Icons.history_rounded,
              label: 'История тренировок',
              onTap: () => context.push('/history'),
            ),
            const SizedBox(height: 8),
            _NavCard(
              icon: Icons.emoji_events_rounded,
              label: 'Личные рекорды',
              onTap: () => context.push('/records'),
            ),
            const SizedBox(height: 24),
            const Text(
              'Достижения',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _AchievementsGrid(achievements: achievements),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared: date range filter
// ═══════════════════════════════════════════════════════════════════════════════

enum _DateRange { month1, month3, month6, all }

extension _DateRangeX on _DateRange {
  String get label => switch (this) {
        _DateRange.month1 => '1М',
        _DateRange.month3 => '3М',
        _DateRange.month6 => '6М',
        _DateRange.all => 'Всё',
      };

  DateTime? get cutoff => switch (this) {
        _DateRange.month1 => DateTime.now().subtract(const Duration(days: 31)),
        _DateRange.month3 => DateTime.now().subtract(const Duration(days: 92)),
        _DateRange.month6 => DateTime.now().subtract(const Duration(days: 183)),
        _DateRange.all => null,
      };
}

class _RangeChips extends StatelessWidget {
  final _DateRange selected;
  final void Function(_DateRange) onChanged;

  const _RangeChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _DateRange.values.map((r) {
        final active = r == selected;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(r),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.accent : AppColors.card,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                r.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

bool _afterCutoff(String dateStr, DateTime? cutoff) {
  if (cutoff == null) return true;
  try {
    return DateTime.parse(dateStr).isAfter(cutoff);
  } catch (_) {
    return true;
  }
}

/// Computes average volume per weekday (1=Mon…7=Sun) from a map of
/// [DateTime → volume] entries. Only positive-volume days are counted.
Map<int, double> weekdayVolumeFrom(Map<DateTime, double> data) {
  final sums = <int, double>{};
  final counts = <int, int>{};
  for (final entry in data.entries) {
    if (entry.value <= 0) continue;
    final wd = entry.key.weekday;
    sums[wd] = (sums[wd] ?? 0) + entry.value;
    counts[wd] = (counts[wd] ?? 0) + 1;
  }
  return {
    for (final wd in sums.keys) wd: sums[wd]! / counts[wd]!,
  };
}

/// Computes the delta of [metricData] between the current period (after
/// [cutoff]) and the previous same-length window before [cutoff].
/// Returns null if there is not enough data or [cutoff] is null.
({double delta, String unit})? bodyPeriodDelta({
  required Map<String, double> metricData,
  required DateTime? cutoff,
  required String unit,
}) {
  if (cutoff == null) return null;
  final all = Map.fromEntries(
    metricData.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
  final curEntries = all.entries.where((e) => _afterCutoff(e.key, cutoff)).toList();
  if (curEntries.length < 2) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final windowDays = today.difference(cutoff).inDays;
  final prevStart = cutoff.subtract(Duration(days: windowDays));
  final prevEntries = all.entries
      .where((e) {
        final d = DateTime.tryParse(e.key);
        if (d == null) return false;
        return !d.isBefore(prevStart) && d.isBefore(cutoff);
      })
      .toList();
  if (prevEntries.isEmpty) return null;
  final curVal = curEntries.last.value;
  final prevVal = prevEntries.last.value;
  return (delta: curVal - prevVal, unit: unit);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 2: Тренировки
// ═══════════════════════════════════════════════════════════════════════════════

class _WorkoutsTab extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final List<Map<String, dynamic>> weeklyVolume;
  final double? communityAvgWeeklyVolume;
  final List<Map<String, dynamic>> topExercises;
  final List<Map<String, dynamic>> trackedExercises;
  final Map<String, dynamic>? selectedExercise;
  final Map<String, double> exerciseProgress;
  final double? communityAvgExerciseWeight;
  final bool loadingChart;
  final Map<String, int> muscleBalance;
  final Map<String, double> muscleFrequency;
  final List<Map<String, dynamic>> caloriesPerSession;
  final void Function(Map<String, dynamic>?) onExerciseChanged;
  final Map<DateTime, double> heatmapData;
  final List<Map<String, dynamic>> sessionDurations;
  final List<Map<String, dynamic>> sessionRpes;
  final List<Map<String, dynamic>> exerciseProgressList;

  const _WorkoutsTab({
    required this.onRefresh,
    required this.weeklyVolume,
    required this.communityAvgWeeklyVolume,
    required this.topExercises,
    required this.trackedExercises,
    required this.selectedExercise,
    required this.exerciseProgress,
    required this.communityAvgExerciseWeight,
    required this.loadingChart,
    required this.muscleBalance,
    required this.muscleFrequency,
    required this.caloriesPerSession,
    required this.onExerciseChanged,
    required this.heatmapData,
    required this.sessionDurations,
    required this.sessionRpes,
    required this.exerciseProgressList,
  });

  @override
  State<_WorkoutsTab> createState() => _WorkoutsTabState();
}

class _WorkoutsTabState extends State<_WorkoutsTab> {
  _DateRange _range = _DateRange.month3;

  List<Map<String, dynamic>> get _filteredVolume {
    final cutoff = _range.cutoff;
    return widget.weeklyVolume
        .where((w) => _afterCutoff(w['week_start'] as String? ?? '', cutoff))
        .toList();
  }

  Map<String, double> get _filteredExerciseProgress {
    final cutoff = _range.cutoff;
    return Map.fromEntries(
      widget.exerciseProgress.entries
          .where((e) => _afterCutoff(e.key, cutoff)),
    );
  }

  List<Map<String, dynamic>> get _filteredCalories {
    final cutoff = _range.cutoff;
    return widget.caloriesPerSession
        .where((s) => _afterCutoff(s['date'] as String? ?? '', cutoff))
        .toList();
  }

  List<Map<String, dynamic>> get _filteredDurations {
    final cutoff = _range.cutoff;
    return widget.sessionDurations
        .where((s) => _afterCutoff(s['date'] as String? ?? '', cutoff))
        .toList();
  }

  List<Map<String, dynamic>> get _filteredRpes {
    final cutoff = _range.cutoff;
    return widget.sessionRpes
        .where((s) => _afterCutoff(s['date'] as String? ?? '', cutoff))
        .toList();
  }

  /// Average volume per weekday (1=Mon…7=Sun) from heatmap data.
  Map<int, double> get _weekdayVolume => weekdayVolumeFrom(widget.heatmapData);

  /// Previous period: same number of weeks immediately before _filteredVolume.
  ({double volume, int sessions})? get _periodComparison {
    final cur = _filteredVolume;
    final all = widget.weeklyVolume;
    if (cur.isEmpty || all.length < cur.length * 2) return null;
    final prevEnd = all.length - cur.length;
    final prevStart = (prevEnd - cur.length).clamp(0, all.length);
    final prev = all.sublist(prevStart, prevEnd);
    if (prev.isEmpty) return null;
    double curVol = 0, prevVol = 0;
    int curSess = 0, prevSess = 0;
    for (final w in cur) {
      curVol += (w['volume'] as num).toDouble();
      if ((w['volume'] as num) > 0) curSess++;
    }
    for (final w in prev) {
      prevVol += (w['volume'] as num).toDouble();
      if ((w['volume'] as num) > 0) prevSess++;
    }
    return (volume: curVol - prevVol, sessions: curSess - prevSess);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(context).padding.bottom + 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RangeChips(selected: _range, onChanged: (r) => setState(() => _range = r)),
            const SizedBox(height: 20),
            const Text(
              'Активность',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Последние 26 недель',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _WeeklyHeatmap(data: widget.heatmapData),
            ),
            const SizedBox(height: 28),
            const Text(
              'Тренд объёма нагрузки',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'кг × повт. · ${_range.label == 'Всё' ? 'всё время' : 'последние ${_range.label}'}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            _VolumeBarChart(weeks: _filteredVolume, communityAvg: widget.communityAvgWeeklyVolume),
            if (_range != _DateRange.all) ...[
              const SizedBox(height: 10),
              () {
                final cmp = _periodComparison;
                if (cmp == null) return const SizedBox.shrink();
                final vDiff = cmp.volume;
                final sDiff = cmp.sessions;
                final vColor = vDiff >= 0 ? const Color(0xFF30D158) : AppColors.error;
                final sColor = sDiff >= 0 ? const Color(0xFF30D158) : AppColors.error;
                final vSign = vDiff >= 0 ? '+' : '';
                final sSign = sDiff >= 0 ? '+' : '';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'vs предыдущий период',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      Row(
                        children: [
                          Text(
                            '$sSign$sDiff тр.',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: sColor),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$vSign${vDiff.toStringAsFixed(0)} кг',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: vColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }(),
            ],
            const SizedBox(height: 28),
            const Text(
              'Топ-5 упражнений за месяц',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'По общему объёму (кг × повт.)',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            _TopExercisesCard(exercises: widget.topExercises),
            if (widget.exerciseProgressList.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Text(
                'Наибольший прогресс за 12 нед.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Рост максимального веса по ЛР',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              _ExerciseProgressCard(exercises: widget.exerciseProgressList),
            ],
            const SizedBox(height: 28),
            const Text(
              'Прогресс по упражнению',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.trackedExercises.isEmpty)
              _emptyCard('Завершите тренировку с весом,\nчтобы увидеть прогресс')
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<Map<String, dynamic>>(
                  value: widget.selectedExercise,
                  hint: const Text('Выберите упражнение',
                      style: TextStyle(color: AppColors.textSecondary)),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppColors.card,
                  style: const TextStyle(color: AppColors.textPrimary),
                  items: widget.trackedExercises
                      .map((ex) => DropdownMenuItem(
                            value: ex,
                            child: Text(ex['name'] as String),
                          ))
                      .toList(),
                  onChanged: widget.onExerciseChanged,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.selectedExercise != null)
                widget.loadingChart
                    ? const SizedBox(
                        height: 180,
                        child: Center(child: CircularProgressIndicator()))
                    : _filteredExerciseProgress.isEmpty
                        ? Container(
                            height: 80,
                            alignment: Alignment.center,
                            child: const Text('Нет данных',
                                style: TextStyle(color: AppColors.textSecondary)),
                          )
                        : _ProgressChart(
                            data: _filteredExerciseProgress,
                            communityAvg: widget.communityAvgExerciseWeight,
                          ),
            ],
            const SizedBox(height: 28),
            const Text(
              'Баланс мышечных групп',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Подходы за последние 30 дней',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            _MuscleBalanceChart(balance: widget.muscleBalance),
            if (widget.muscleFrequency.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Частота по группам мышц',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Среднее тренировок в неделю за 4 недели',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              _MuscleFrequencyChart(frequency: widget.muscleFrequency),
            ],
            const SizedBox(height: 28),
            const Text(
              'Калории',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Оценка затрат по тренировкам',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            if (_filteredCalories.isEmpty)
              _emptyCard('Завершите тренировку,\nчтобы увидеть данные о калориях')
            else
              _CaloriesChart(sessions: _filteredCalories),
            if (_weekdayVolume.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Text(
                'Объём по дням недели',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Средний объём за 26 недель (кг × повт.)',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              _WeekdayVolumeChart(weekdayVolume: _weekdayVolume),
            ],
            if (_filteredDurations.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Text(
                'Длительность тренировок',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Минуты за сессию',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              _SessionLineChart(
                sessions: _filteredDurations,
                field: 'duration_minutes',
                color: const Color(0xFF30D158),
                unit: 'мин',
              ),
            ],
            if (_filteredRpes.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Text(
                'Сложность тренировок (RPE)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Субъективная нагрузка 1–10 по сессиям',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              _SessionLineChart(
                sessions: _filteredRpes,
                field: 'rpe',
                color: const Color(0xFFFF9F0A),
                unit: 'RPE',
                minY: 1,
                maxY: 10,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String msg) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 3: Тело
// ═══════════════════════════════════════════════════════════════════════════════

class _BodyTab extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final List<Map<String, dynamic>> bodyHistory;
  final Map<String, String> bodyMetricOptions;
  final List<String> availableBodyMetrics;
  final String selectedBodyMetric;
  final Map<String, double> bodyMetricData;
  final List<Map<String, dynamic>> wellnessHistory;
  final void Function(String?) onMetricChanged;

  const _BodyTab({
    required this.onRefresh,
    required this.bodyHistory,
    required this.bodyMetricOptions,
    required this.availableBodyMetrics,
    required this.selectedBodyMetric,
    required this.bodyMetricData,
    required this.wellnessHistory,
    required this.onMetricChanged,
  });

  @override
  State<_BodyTab> createState() => _BodyTabState();
}

class _BodyTabState extends State<_BodyTab> {
  _DateRange _range = _DateRange.month3;
  final _chartKey = GlobalKey();
  bool _sharing = false;

  Future<void> _shareChart() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary =
          _chartKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sportwai_body_chart.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], subject: 'Мой прогресс');
      EventLogger.exportTriggered(format: 'body_chart');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Map<String, double> get _filteredBodyData {
    final cutoff = _range.cutoff;
    return Map.fromEntries(
      widget.bodyMetricData.entries.where((e) => _afterCutoff(e.key, cutoff)),
    );
  }

  /// Change in the selected metric over the current period vs the previous same-length window.
  /// Returns (delta, unit) or null if not enough data.
  ({double delta, String unit})? get _bodyPeriodDelta {
    if (_range == _DateRange.all) return null;
    final isBodyFat = widget.selectedBodyMetric == 'body_fat_pct';
    return bodyPeriodDelta(
      metricData: widget.bodyMetricData,
      cutoff: _range.cutoff,
      unit: isBodyFat ? '%' : ' кг',
    );
  }

  /// Linear extrapolation on the HP trend: returns forecast value [stepsAhead]
  /// data-points into the future, or null if not enough data.
  double? _forecast(Map<String, double> data, {int stepsAhead = 4}) {
    final sorted = data.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (sorted.length < 5) return null;
    final hp = _ProgressChart._hpFilter(sorted.map((e) => e.value).toList());
    final lookback = hp.length.clamp(4, 10);
    final recent = hp.sublist(hp.length - lookback);
    // Least-squares slope
    final n = recent.length.toDouble();
    double sx = 0, sy = 0, sxy = 0, sx2 = 0;
    for (int i = 0; i < recent.length; i++) {
      sx += i; sy += recent[i]; sxy += i * recent[i]; sx2 += i * i;
    }
    final denom = n * sx2 - sx * sx;
    if (denom.abs() < 1e-9) return null;
    final slope = (n * sxy - sx * sy) / denom;
    // Estimate how many data-steps ≈ stepsAhead weeks
    if (sorted.length < 2) return null;
    final daySpan = DateTime.parse(sorted.last.key)
        .difference(DateTime.parse(sorted.first.key))
        .inDays;
    final daysPerPoint = daySpan / (sorted.length - 1);
    if (daysPerPoint <= 0) return null;
    final pointsAhead = (stepsAhead * 7 / daysPerPoint).roundToDouble();
    return hp.last + slope * pointsAhead;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(context).padding.bottom + 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Динамика параметров тела',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (widget.bodyHistory.isNotEmpty)
                  IconButton(
                    onPressed: _sharing ? null : _shareChart,
                    icon: _sharing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded,
                            size: 20, color: AppColors.textSecondary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Поделиться графиком',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.bodyHistory.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text(
                    'Добавьте замеры в разделе\n«Параметры тела» в профиле',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else ...[
              _RangeChips(selected: _range, onChanged: (r) => setState(() => _range = r)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<String>(
                  value: widget.availableBodyMetrics.contains(widget.selectedBodyMetric)
                      ? widget.selectedBodyMetric
                      : widget.availableBodyMetrics.first,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppColors.card,
                  style: const TextStyle(color: AppColors.textPrimary),
                  items: widget.availableBodyMetrics.map((key) {
                    return DropdownMenuItem<String>(
                      value: key,
                      child: Text(widget.bodyMetricOptions[key] ?? key),
                    );
                  }).toList(),
                  onChanged: widget.onMetricChanged,
                ),
              ),
              const SizedBox(height: 12),
              if (_filteredBodyData.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      'Нет данных по этому параметру',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else ...[
                RepaintBoundary(
                  key: _chartKey,
                  child: _ProgressChart(data: _filteredBodyData),
                ),
                () {
                  final delta = _bodyPeriodDelta;
                  if (delta == null) return const SizedBox.shrink();
                  final d = delta.delta;
                  final sign = d >= 0 ? '+' : '';
                  final isWeight = widget.selectedBodyMetric == 'weight_kg';
                  final isBodyFat = widget.selectedBodyMetric == 'body_fat_pct';
                  final Color color;
                  if (d.abs() < 0.1) {
                    color = AppColors.textSecondary;
                  } else if (isWeight || isBodyFat) {
                    color = d < 0 ? AppColors.success : AppColors.error;
                  } else {
                    color = d > 0 ? AppColors.success : AppColors.error;
                  }
                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'vs предыдущий период',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        Text(
                          '$sign${d.toStringAsFixed(1)}${delta.unit}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  );
                }(),
                () {
                  final fc = _forecast(_filteredBodyData);
                  if (fc == null) return const SizedBox.shrink();
                  final current = _filteredBodyData.values.last;
                  final diff = fc - current;
                  final isWeight = widget.selectedBodyMetric == 'weight_kg' ||
                      widget.selectedBodyMetric == 'body_fat_pct';
                  if (!isWeight) return const SizedBox.shrink();
                  final sign = diff >= 0 ? '+' : '';
                  final unit = widget.selectedBodyMetric == 'body_fat_pct' ? '%' : ' кг';
                  final color = diff.abs() < 0.3
                      ? AppColors.textSecondary
                      : (widget.selectedBodyMetric == 'weight_kg'
                          ? (diff < 0 ? AppColors.success : AppColors.error)
                          : (diff < 0 ? AppColors.success : AppColors.error));
                  return Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: color.withValues(alpha: 0.3), width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.trending_flat_rounded, size: 16, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Прогноз через ~4 нед: ${fc.toStringAsFixed(1)}$unit  ($sign${diff.toStringAsFixed(1)}$unit по тренду)',
                            style: TextStyle(fontSize: 12, color: color),
                          ),
                        ),
                      ],
                    ),
                  );
                }(),
              ],
            ],
            const SizedBox(height: 28),
            const Text(
              'Самочувствие',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Последние 30 дней',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            _WellnessTrendChart(history: widget.wellnessHistory),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 4: Инсайты
// ═══════════════════════════════════════════════════════════════════════════════

class _InsightsTab extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final GlobalKey shareKey;
  final Profile? profile;
  final int bestStreak;
  final int totalWorkouts;
  final int workoutsThisWeek;
  final double volumeThisWeek;
  final Map<DateTime, double> heatmapData;
  final List<Map<String, dynamic>> weeklyVolume;
  final Map<String, int> muscleBalance;
  final List<Map<String, dynamic>> wellnessHistory;
  final bool sharing;
  final VoidCallback onShare;

  const _InsightsTab({
    required this.onRefresh,
    required this.shareKey,
    required this.profile,
    required this.bestStreak,
    required this.totalWorkouts,
    required this.workoutsThisWeek,
    required this.volumeThisWeek,
    required this.heatmapData,
    required this.weeklyVolume,
    required this.muscleBalance,
    required this.wellnessHistory,
    required this.sharing,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(context).padding.bottom + 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Умные инсайты',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Основано на ваших данных',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            _InsightsSection(
              heatmapData: heatmapData,
              weeklyVolume: weeklyVolume,
              muscleBalance: muscleBalance,
              wellnessHistory: wellnessHistory,
              bestStreak: bestStreak,
              totalWorkouts: totalWorkouts,
            ),
            const SizedBox(height: 28),
            const Text(
              'Поделиться прогрессом',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            RepaintBoundary(
              key: shareKey,
              child: _ShareCard(
                name: profile?.fullName?.split(' ').first ?? 'Атлет',
                streak: bestStreak,
                totalWorkouts: totalWorkouts,
                workoutsThisWeek: workoutsThisWeek,
                volumeThisWeek: volumeThisWeek,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: sharing ? null : onShare,
                icon: sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: const Text('Поделиться картинкой'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEW: Monthly calendar heatmap
// ═══════════════════════════════════════════════════════════════════════════════

class _MonthCalendar extends StatelessWidget {
  final Map<DateTime, double> heatmapData;

  const _MonthCalendar({required this.heatmapData});

  static const _months = [
    '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];

  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDay = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    // weekday: Mon=1 … Sun=7; offset = 0-based index on grid
    final startOffset = firstDay.weekday - 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _months[now.month],
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          // Weekday header
          Row(
            children: _weekdays.map((d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 6),
          // Calendar grid — up to 6 rows of 7
          Builder(builder: (context) {
            final totalCells = startOffset + daysInMonth;
            final rows = (totalCells / 7).ceil();
            return Column(
              children: List.generate(rows, (row) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: List.generate(7, (col) {
                      final cellIndex = row * 7 + col;
                      final day = cellIndex - startOffset + 1;
                      if (day < 1 || day > daysInMonth) {
                        return const Expanded(child: SizedBox());
                      }
                      final date = DateTime(now.year, now.month, day);
                      final isFuture = date.isAfter(today);
                      final volume = isFuture ? 0.0 : (heatmapData[date] ?? 0.0);
                      final worked = volume > 0;
                      final isToday = date == today;

                      return Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: isFuture
                                  ? Colors.transparent
                                  : worked
                                      ? AppColors.accent
                                      : AppColors.surface,
                              shape: BoxShape.circle,
                              border: isToday
                                  ? Border.all(color: AppColors.accent, width: 1.5)
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                '$day',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: worked
                                      ? Colors.white
                                      : isFuture
                                          ? AppColors.textSecondary.withValues(alpha: 0.3)
                                          : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEW: Top exercises card
// ═══════════════════════════════════════════════════════════════════════════════

class _TopExercisesCard extends StatelessWidget {
  final List<Map<String, dynamic>> exercises;

  const _TopExercisesCard({required this.exercises});

  String _formatVolume(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)} т';
    }
    return '${v.toStringAsFixed(0)} кг';
  }

  @override
  Widget build(BuildContext context) {
    if (exercises.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'Завершите тренировки с весами,\nчтобы увидеть статистику',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final maxVol = (exercises.first['total_volume'] as num).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: exercises.asMap().entries.map((entry) {
          final i = entry.key;
          final ex = entry.value;
          final name = ex['name'] as String? ?? '—';
          final vol = (ex['total_volume'] as num).toDouble();
          final frac = maxVol > 0 ? vol / maxVol : 0.0;

          return Padding(
            padding: EdgeInsets.only(bottom: i < exercises.length - 1 ? 14 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}.',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatVolume(vol),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 22),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: frac.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: AppColors.surface,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEW: Weekly activity heatmap (GitHub-style, 26 weeks)
// ═══════════════════════════════════════════════════════════════════════════════

class _WeeklyHeatmap extends StatelessWidget {
  final Map<DateTime, double> data;

  const _WeeklyHeatmap({required this.data});

  static const _dayLabels = ['', 'Пн', '', 'Ср', '', 'Пт', ''];
  static const _monthNames = [
    '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  Color _cellColor(double vol, double maxVol, bool isFuture) {
    if (isFuture) return Colors.transparent;
    if (vol == 0) return AppColors.surface;
    if (maxVol == 0) return AppColors.accent.withValues(alpha: 0.5);
    final t = vol / maxVol;
    if (t < 0.25) return AppColors.accent.withValues(alpha: 0.28);
    if (t < 0.5)  return AppColors.accent.withValues(alpha: 0.52);
    if (t < 0.75) return AppColors.accent.withValues(alpha: 0.76);
    return AppColors.accent;
  }

  @override
  Widget build(BuildContext context) {
    const weeks = 26;
    const dayLabelW = 22.0;
    const gap = 2.0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final latestMon = today.subtract(Duration(days: today.weekday - 1));

    final weekStarts = List.generate(
      weeks,
      (i) => latestMon.subtract(Duration(days: 7 * (weeks - 1 - i))),
    );

    final maxVol = data.values.fold<double>(0, (a, b) => a > b ? a : b);

    return LayoutBuilder(builder: (context, constraints) {
      final cellSize = ((constraints.maxWidth - dayLabelW - gap * (weeks + 1)) / weeks)
          .clamp(8.0, 18.0);

      // Build month label positions
      final monthLabels = <Widget>[];
      int? lastMonth;
      for (int wi = 0; wi < weekStarts.length; wi++) {
        final m = weekStarts[wi].month;
        if (m != lastMonth) {
          lastMonth = m;
          monthLabels.add(Positioned(
            left: dayLabelW + wi * (cellSize + gap),
            top: 0,
            child: Text(
              _monthNames[m],
              style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
            ),
          ));
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month labels
          SizedBox(
            height: 14,
            child: Stack(children: monthLabels),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day-of-week labels
              SizedBox(
                width: dayLabelW,
                child: Column(
                  children: List.generate(7, (d) => SizedBox(
                    height: cellSize + gap,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          _dayLabels[d],
                          style: const TextStyle(
                            fontSize: 8,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  )),
                ),
              ),
              // Week columns
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: weekStarts.map((weekStart) {
                    return Column(
                      children: List.generate(7, (dayIdx) {
                        final date = weekStart.add(Duration(days: dayIdx));
                        final isFuture = date.isAfter(today);
                        final vol = isFuture ? 0.0 : (data[date] ?? 0.0);
                        return Container(
                          width: cellSize,
                          height: cellSize,
                          margin: const EdgeInsets.only(bottom: gap, right: gap),
                          decoration: BoxDecoration(
                            color: _cellColor(vol, maxVol, isFuture),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEW: Top exercises by progress card
// ═══════════════════════════════════════════════════════════════════════════════

class _ExerciseProgressCard extends StatelessWidget {
  final List<Map<String, dynamic>> exercises;

  const _ExerciseProgressCard({required this.exercises});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: exercises.asMap().entries.map((entry) {
          final i = entry.key;
          final ex = entry.value;
          final name = ex['name'] as String? ?? '—';
          final start = (ex['start_weight'] as num).toDouble();
          final end = (ex['end_weight'] as num).toDouble();
          final pct = (ex['pct_change'] as num).toDouble();
          final isLast = i == exercises.length - 1;

          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${start.toStringAsFixed(1)} → ${end.toStringAsFixed(1)} кг',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF30D158).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '+${pct.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF30D158),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEW: Volume by weekday bar chart
// ═══════════════════════════════════════════════════════════════════════════════

class _WeekdayVolumeChart extends StatelessWidget {
  final Map<int, double> weekdayVolume; // 1=Mon … 7=Sun

  const _WeekdayVolumeChart({required this.weekdayVolume});

  static const _labels = ['', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  String _fmt(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}т' : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final maxVal = weekdayVolume.values.fold<double>(0, (a, b) => a > b ? a : b);
    final barGroups = List.generate(7, (i) {
      final wd = i + 1;
      final val = weekdayVolume[wd] ?? 0.0;
      return BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          toY: val,
          color: val == maxVal && val > 0
              ? AppColors.accent
              : AppColors.accent.withValues(alpha: 0.45),
          width: 20,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ]);
    });

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        height: 140,
        child: BarChart(
          BarChartData(
            maxY: maxVal * 1.2,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (v, _) {
                    final wd = v.toInt() + 1;
                    final val = weekdayVolume[wd] ?? 0.0;
                    if (val == 0) return const SizedBox.shrink();
                    return Text(
                      _fmt(val),
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondary,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 20,
                  getTitlesWidget: (v, _) => Text(
                    _labels[v.toInt() + 1],
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            barGroups: barGroups,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEW: Reusable session line chart (duration & RPE)
// ═══════════════════════════════════════════════════════════════════════════════

class _SessionLineChart extends StatelessWidget {
  final List<Map<String, dynamic>> sessions; // [{date, <field>}]
  final String field;
  final Color color;
  final String unit;
  final double? minY;
  final double? maxY;

  const _SessionLineChart({
    required this.sessions,
    required this.field,
    required this.color,
    required this.unit,
    this.minY,
    this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (int i = 0; i < sessions.length; i++) {
      final v = sessions[i][field];
      if (v == null) continue;
      spots.add(FlSpot(i.toDouble(), (v as num).toDouble()));
    }
    if (spots.isEmpty) return const SizedBox.shrink();

    final vals = spots.map((s) => s.y);
    final dataMin = vals.reduce((a, b) => a < b ? a : b);
    final dataMax = vals.reduce((a, b) => a > b ? a : b);
    final pad = dataMax == dataMin ? 2.0 : (dataMax - dataMin) * 0.2;
    final chartMin = minY ?? (dataMin - pad).clamp(0, double.infinity);
    final chartMax = maxY ?? (dataMax + pad);

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 12, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        height: 140,
        child: LineChart(
          LineChartData(
            minY: chartMin,
            maxY: chartMax,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppColors.surface, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (v, _) => Text(
                    v.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textSecondary),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: sessions.length <= 6
                      ? 1
                      : (sessions.length / 4).ceilToDouble(),
                  getTitlesWidget: (value, _) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= sessions.length) {
                      return const SizedBox.shrink();
                    }
                    final parts = (sessions[idx]['date'] as String).split('-');
                    final label = parts.length >= 3
                        ? '${parts[2]}.${parts[1]}'
                        : sessions[idx]['date'] as String;
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        label,
                        style: const TextStyle(
                            fontSize: 9, color: AppColors.textSecondary),
                      ),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: color,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: spots.length <= 20,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: 3,
                    color: color,
                    strokeWidth: 0,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEW: Wellness trend chart
// ═══════════════════════════════════════════════════════════════════════════════

class _WellnessTrendChart extends StatefulWidget {
  final List<Map<String, dynamic>> history;

  const _WellnessTrendChart({required this.history});

  @override
  State<_WellnessTrendChart> createState() => _WellnessTrendChartState();
}

class _WellnessTrendChartState extends State<_WellnessTrendChart> {
  // 0 = Сон, 1 = Энергия, 2 = Стресс
  int _selected = 0;

  static const _tabs = ['Сон', 'Энергия', 'Стресс'];
  static const _fields = ['sleep_hours', 'energy', 'stress'];
  static const _colors = [
    Color(0xFF30D158), // green for sleep
    Color(0xFFFF9F0A), // orange for energy
    Color(0xFFFF453A), // red for stress
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.history.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'Добавьте данные о самочувствии на главном экране',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final field = _fields[_selected];
    final color = _colors[_selected];

    // Build data points — skip rows where the field is null
    final points = <MapEntry<String, double>>[];
    for (final row in widget.history) {
      final v = row[field];
      if (v == null) continue;
      final date = row['date'] as String?;
      if (date == null) continue;
      points.add(MapEntry(date, (v as num).toDouble()));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final active = _selected == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? AppColors.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          _tabs[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: active ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
          if (points.isEmpty)
            const SizedBox(
              height: 80,
              child: Center(
                child: Text(
                  'Нет данных по этому показателю',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            SizedBox(
              height: 160,
              child: _WellnessLineChart(points: points, color: color),
            ),
        ],
      ),
    );
  }
}

class _WellnessLineChart extends StatelessWidget {
  final List<MapEntry<String, double>> points;
  final Color color;

  const _WellnessLineChart({required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    final spots = List.generate(
      points.length,
      (i) => FlSpot(i.toDouble(), points[i].value),
    );
    final values = points.map((e) => e.value);
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = maxY == minY ? 1.0 : (maxY - minY) * 0.2;

    return LineChart(
      LineChartData(
        minY: (minY - pad).clamp(0, double.infinity),
        maxY: maxY + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: AppColors.surface,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(0),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: points.length <= 6
                  ? 1
                  : (points.length / 4).ceilToDouble(),
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                final parts = points[idx].key.split('-');
                final label = parts.length >= 3 ? '${parts[2]}.${parts[1]}' : points[idx].key;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: color,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEW: Insights section + card
// ═══════════════════════════════════════════════════════════════════════════════

class _InsightCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _InsightCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
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

class _InsightsSection extends StatelessWidget {
  final Map<DateTime, double> heatmapData;
  final List<Map<String, dynamic>> weeklyVolume;
  final Map<String, int> muscleBalance;
  final List<Map<String, dynamic>> wellnessHistory;
  final int bestStreak;
  final int totalWorkouts;

  const _InsightsSection({
    required this.heatmapData,
    required this.weeklyVolume,
    required this.muscleBalance,
    required this.wellnessHistory,
    required this.bestStreak,
    required this.totalWorkouts,
  });

  static const _weekdayNames = ['', 'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
  static const _muscleLabels = {
    'chest': 'Грудь',
    'back': 'Спина',
    'shoulders': 'Плечи',
    'arms': 'Руки',
    'legs': 'Ноги',
    'core': 'Пресс',
    'cardio': 'Кардио',
  };

  List<_InsightCard> _buildInsights() {
    final cards = <_InsightCard>[];

    // 1. Best day of week
    if (heatmapData.isNotEmpty) {
      final weekdayCount = <int, int>{};
      for (final entry in heatmapData.entries) {
        if (entry.value > 0) {
          final wd = entry.key.weekday; // 1=Mon, 7=Sun
          weekdayCount[wd] = (weekdayCount[wd] ?? 0) + 1;
        }
      }
      if (weekdayCount.isNotEmpty) {
        final bestWd = weekdayCount.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
        final count = weekdayCount[bestWd]!;
        cards.add(_InsightCard(
          icon: Icons.calendar_today_rounded,
          color: AppColors.accent,
          title: 'Лучший день для тренировок',
          body: '${_weekdayNames[bestWd]} — вы тренируетесь в этот день чаще всего ($count раз за последние 6 месяцев).',
        ));
      }
    }

    // 2. Volume trend: last 4 weeks vs previous 4 weeks
    if (weeklyVolume.length >= 8) {
      final recent = weeklyVolume.sublist(weeklyVolume.length - 4);
      final older = weeklyVolume.sublist(weeklyVolume.length - 8, weeklyVolume.length - 4);
      final recentAvg = recent.fold(0.0, (s, w) => s + (w['volume'] as double)) / 4;
      final olderAvg = older.fold(0.0, (s, w) => s + (w['volume'] as double)) / 4;
      if (olderAvg > 0) {
        final pct = ((recentAvg - olderAvg) / olderAvg * 100).round();
        final up = pct >= 0;
        cards.add(_InsightCard(
          icon: up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          color: up ? AppColors.success : AppColors.error,
          title: 'Тренд объёма нагрузки',
          body: up
              ? 'За последние 4 недели ваш объём вырос на $pct% по сравнению с предыдущим периодом. Отлично!'
              : 'За последние 4 недели объём снизился на ${pct.abs()}%. Попробуйте добавить нагрузку.',
        ));
      }
    }

    // 3. Most trained muscle group
    if (muscleBalance.isNotEmpty) {
      final top = muscleBalance.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final label = _muscleLabels[top.key] ?? top.key;
      cards.add(_InsightCard(
        icon: Icons.fitness_center_rounded,
        color: const Color(0xFFBF5AF2),
        title: 'Самая тренируемая группа',
        body: '$label лидирует по объёму подходов за последние 30 дней (${top.value} подходов). Следите за балансом.',
      ));
    }

    // 4. Consistency: % weeks with 2+ workouts over last 12 weeks
    if (heatmapData.isNotEmpty) {
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final weekWorkouts = <String, int>{};
      for (int i = 0; i < 12; i++) {
        final weekStart = monday.subtract(Duration(days: 7 * i));
        final key = '${weekStart.year}-${weekStart.month}-${weekStart.day}';
        weekWorkouts[key] = 0;
      }
      for (final entry in heatmapData.entries) {
        if (entry.value <= 0) continue;
        final d = entry.key;
        final mon = d.subtract(Duration(days: d.weekday - 1));
        final key = '${mon.year}-${mon.month}-${mon.day}';
        if (weekWorkouts.containsKey(key)) {
          weekWorkouts[key] = weekWorkouts[key]! + 1;
        }
      }
      final activeWeeks = weekWorkouts.values.where((c) => c >= 2).length;
      final totalWeeks = weekWorkouts.length;
      if (totalWeeks >= 4) {
        final pct = (activeWeeks / totalWeeks * 100).round();
        final emoji = pct >= 75 ? '🔥' : pct >= 50 ? '✅' : '📈';
        cards.add(_InsightCard(
          icon: Icons.repeat_rounded,
          color: AppColors.warning,
          title: 'Регулярность за 12 недель',
          body: '$emoji В $activeWeeks из $totalWeeks недель вы тренировались 2 раза и более — это $pct% активных недель.',
        ));
      }
    }

    // 5. Wellness correlation — sleep and workouts
    if (wellnessHistory.isNotEmpty) {
      final goodSleepDays = <String>{};
      final allLoggedDays = <String>{};
      for (final row in wellnessHistory) {
        final date = row['date'] as String?;
        if (date == null) continue;
        final sleep = row['sleep_hours'];
        if (sleep == null) continue;
        allLoggedDays.add(date);
        if ((sleep as num).toDouble() >= 7.0) {
          goodSleepDays.add(date);
        }
      }
      if (goodSleepDays.length >= 5 && allLoggedDays.isNotEmpty) {
        // Count workout days that had good sleep logged
        int workedWithGoodSleep = 0;
        int workedWithPoorSleep = 0;
        for (final entry in heatmapData.entries) {
          if (entry.value <= 0) continue;
          final dateStr = '${entry.key.year}-${entry.key.month.toString().padLeft(2, '0')}-${entry.key.day.toString().padLeft(2, '0')}';
          if (!allLoggedDays.contains(dateStr)) continue;
          if (goodSleepDays.contains(dateStr)) {
            workedWithGoodSleep++;
          } else {
            workedWithPoorSleep++;
          }
        }
        final total = workedWithGoodSleep + workedWithPoorSleep;
        if (total >= 5) {
          final pct = (workedWithGoodSleep / total * 100).round();
          cards.add(_InsightCard(
            icon: Icons.bedtime_rounded,
            color: const Color(0xFF34C759),
            title: 'Сон и тренировки',
            body: '$pct% ваших тренировок приходится на дни с 7+ часами сна. Хороший сон помогает тренироваться стабильнее.',
          ));
        }
      }
    }

    // 6. Wellness–volume correlations
    if (wellnessHistory.isNotEmpty && weeklyVolume.isNotEmpty) {
      // Build week_start → volume map
      final weekVolMap = <String, double>{};
      for (final w in weeklyVolume) {
        final ws = w['week_start'] as String?;
        if (ws != null) weekVolMap[ws] = (w['volume'] as num).toDouble();
      }

      // Helper: ISO Monday for any date string
      String toMonday(String d) {
        try {
          final dt = DateTime.parse(d);
          final mon = dt.subtract(Duration(days: dt.weekday - 1));
          return '${mon.year}-${mon.month.toString().padLeft(2, '0')}-${mon.day.toString().padLeft(2, '0')}';
        } catch (_) {
          return d;
        }
      }

      // Aggregate wellness metrics by week
      final weekStress = <String, List<double>>{};
      final weekEnergy = <String, List<double>>{};
      for (final row in wellnessHistory) {
        final date = row['date'] as String?;
        if (date == null) continue;
        final ws = toMonday(date);
        final stress = row['stress'];
        final energy = row['energy'];
        if (stress != null) weekStress.putIfAbsent(ws, () => []).add((stress as num).toDouble());
        if (energy != null) weekEnergy.putIfAbsent(ws, () => []).add((energy as num).toDouble());
      }

      double avg(List<double> l) => l.reduce((a, b) => a + b) / l.length;

      // Stress vs volume
      final stressWeeks = weekStress.entries
          .where((e) => weekVolMap.containsKey(e.key))
          .toList();
      if (stressWeeks.length >= 6) {
        final hi = stressWeeks.where((e) => avg(e.value) > 6).map((e) => weekVolMap[e.key]!).toList();
        final lo = stressWeeks.where((e) => avg(e.value) <= 4).map((e) => weekVolMap[e.key]!).toList();
        if (hi.length >= 2 && lo.length >= 2) {
          final avgHi = avg(hi);
          final avgLo = avg(lo);
          if (avgLo > 0) {
            final diff = ((avgLo - avgHi) / avgLo * 100).round();
            if (diff.abs() >= 5) {
              final less = diff > 0;
              cards.add(_InsightCard(
                icon: Icons.psychology_rounded,
                color: const Color(0xFFFF9F0A),
                title: 'Стресс и нагрузка',
                body: less
                    ? 'В недели с высоким стрессом (>6/10) ваш объём в среднем на $diff% ниже, чем при низком стрессе.'
                    : 'Высокий стресс практически не снижает ваш объём — вы тренируетесь стабильно в любом состоянии.',
              ));
            }
          }
        }
      }

      // Energy vs volume
      final energyWeeks = weekEnergy.entries
          .where((e) => weekVolMap.containsKey(e.key))
          .toList();
      if (energyWeeks.length >= 6) {
        final hi = energyWeeks.where((e) => avg(e.value) >= 7).map((e) => weekVolMap[e.key]!).toList();
        final lo = energyWeeks.where((e) => avg(e.value) <= 4).map((e) => weekVolMap[e.key]!).toList();
        if (hi.length >= 2 && lo.length >= 2) {
          final avgHi = avg(hi);
          final avgLo = avg(lo);
          if (avgHi > 0) {
            final diff = ((avgHi - avgLo) / avgHi * 100).round();
            if (diff.abs() >= 5) {
              cards.add(_InsightCard(
                icon: Icons.bolt_rounded,
                color: const Color(0xFF30D158),
                title: 'Энергия и нагрузка',
                body: diff > 0
                    ? 'В недели с высокой энергией (7+/10) ваш объём на $diff% выше, чем в «тяжёлые» недели. Прислушивайтесь к себе.'
                    : 'Уровень энергии слабо влияет на ваши результаты — отличный показатель дисциплины!',
              ));
            }
          }
        }
      }
    }

    // 7. Streak insight
    if (bestStreak > 0) {
      cards.add(_InsightCard(
        icon: Icons.local_fire_department_rounded,
        color: AppColors.error,
        title: 'Ваш рекорд стрика',
        body: bestStreak >= 7
            ? 'Ваш лучший стрик — $bestStreak дней подряд. Продолжайте в том же духе!'
            : 'Лучший стрик пока $bestStreak дней. Попробуйте не пропускать тренировки несколько недель подряд!',
      ));
    }

    return cards;
  }

  @override
  Widget build(BuildContext context) {
    final insights = _buildInsights();
    if (insights.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'Завершите несколько тренировок,\nчтобы получить персональные инсайты',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return Column(
      children: insights
          .map((card) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: card,
              ))
          .toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Existing widgets (unchanged)
// ═══════════════════════════════════════════════════════════════════════════════

class _AnimatedCounter extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle style;
  const _AnimatedCounter({
    required this.value,
    required this.format,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOut,
      builder: (_, v, __) => Text(format(v), style: style),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final int streak;
  final int totalWorkouts;
  final bool freezeActive;
  final bool hasFreeze;

  const _StreakCard({
    required this.streak,
    required this.totalWorkouts,
    this.freezeActive = false,
    this.hasFreeze = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                freezeActive ? '🛡️' : '🔥',
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'Стрик: ',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    _AnimatedCounter(
                      value: streak.toDouble(),
                      format: (v) => '${v.round()} дней',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: freezeActive ? const Color(0xFF4FC3F7) : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasFreeze && !freezeActive)
                Tooltip(
                  message: 'Заморозка стрика доступна',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🛡️', style: TextStyle(fontSize: 13)),
                        SizedBox(width: 4),
                        Text('×1', style: TextStyle(fontSize: 12, color: Color(0xFF4FC3F7), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (freezeActive) ...[
            const SizedBox(height: 6),
            const Text(
              '🧊 Пропущенный день покрыт заморозкой',
              style: TextStyle(fontSize: 12, color: Color(0xFF4FC3F7)),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Тренировок всего: ',
                style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
              ),
              _AnimatedCounter(
                value: totalWorkouts.toDouble(),
                format: (v) => v.round().toString(),
                style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final double value;
  final String Function(double) format;

  const _StatBox({
    required this.label,
    required this.value,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _AnimatedCounter(
            value: value,
            format: format,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressChart extends StatelessWidget {
  final Map<String, double> data;
  final double? communityAvg;

  const _ProgressChart({required this.data, this.communityAvg});

  /// Hodrick-Prescott filter: returns smoothed trend τ for a series y.
  /// Solves (I + λ·D₂'D₂)·τ = y via Gaussian elimination.
  /// λ=100 works well for irregularly logged body metrics.
  static List<double> _hpFilter(List<double> y, {double lambda = 100}) {
    final n = y.length;
    if (n < 3) return List.of(y);

    // Build full n×n matrix A = I + λ·D₂'D₂
    final a = List.generate(n, (_) => List<double>.filled(n, 0.0));
    for (int i = 0; i < n; i++) {
      a[i][i] = 1.0;
    }
    for (int k = 0; k < n - 2; k++) {
      const idx = [0, 1, 2];
      const coeff = [1.0, -2.0, 1.0];
      for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 3; c++) {
          a[k + idx[r]][k + idx[c]] += lambda * coeff[r] * coeff[c];
        }
      }
    }

    // Gaussian elimination with partial pivoting
    final b = List<double>.of(y);
    for (int col = 0; col < n; col++) {
      int maxRow = col;
      for (int row = col + 1; row < n; row++) {
        if (a[row][col].abs() > a[maxRow][col].abs()) maxRow = row;
      }
      final tmpRow = a[col]; a[col] = a[maxRow]; a[maxRow] = tmpRow;
      final tmpB = b[col]; b[col] = b[maxRow]; b[maxRow] = tmpB;
      if (a[col][col].abs() < 1e-12) continue;
      for (int row = col + 1; row < n; row++) {
        final f = a[row][col] / a[col][col];
        b[row] -= f * b[col];
        for (int c = col; c < n; c++) {
          a[row][c] -= f * a[col][c];
        }
      }
    }

    // Back substitution
    final tau = List<double>.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      tau[i] = b[i];
      for (int j = i + 1; j < n; j++) {
        tau[i] -= a[i][j] * tau[j];
      }
      tau[i] /= a[i][i];
    }
    return tau;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final spots = List.generate(
      sorted.length,
      (i) => FlSpot(i.toDouble(), sorted[i].value),
    );

    final communitySpots = communityAvg == null || sorted.length < 2
        ? <FlSpot>[]
        : [
            FlSpot(0, communityAvg!),
            FlSpot((sorted.length - 1).toDouble(), communityAvg!),
          ];

    // HP trend line (needs ≥3 points to be meaningful)
    final hpSpots = sorted.length >= 3
        ? () {
            final tau = _hpFilter(sorted.map((e) => e.value).toList());
            return List.generate(tau.length, (i) => FlSpot(i.toDouble(), tau[i]));
          }()
        : <FlSpot>[];

    final dataMin = sorted.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    final dataMax = sorted.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final allValues = [dataMin, dataMax, if (communityAvg != null) communityAvg!];
    final minY = allValues.reduce((a, b) => a < b ? a : b);
    final maxY = allValues.reduce((a, b) => a > b ? a : b);
    final yPad = maxY == minY ? 5.0 : (maxY - minY) * 0.2;

    const hpColor = Color(0xFFFFA040);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 200,
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: LineChart(
            LineChartData(
              minY: minY - yPad,
              maxY: maxY + yPad,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: Color(0xFF2C2C2E),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) => Text(
                      value.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: sorted.length <= 6 ? 1 : (sorted.length / 4).ceilToDouble(),
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= sorted.length) return const SizedBox.shrink();
                      final parts = sorted[idx].key.split('-');
                      final label = parts.length >= 3 ? '${parts[2]}.${parts[1]}' : sorted[idx].key;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                if (communitySpots.length >= 2)
                  LineChartBarData(
                    spots: communitySpots,
                    isCurved: false,
                    color: Colors.white.withValues(alpha: 0.28),
                    barWidth: 1.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: AppColors.accent,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                      radius: 4,
                      color: AppColors.accent,
                      strokeWidth: 0,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.accent.withValues(alpha: 0.15),
                  ),
                ),
                if (hpSpots.length >= 3)
                  LineChartBarData(
                    spots: hpSpots,
                    isCurved: true,
                    color: hpColor,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    dashArray: [6, 4],
                    belowBarData: BarAreaData(show: false),
                  ),
              ],
            ),
          ),
        ),
        if (hpSpots.length >= 3) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Container(width: 18, height: 2, color: AppColors.accent),
              const SizedBox(width: 6),
              const Text('Факт', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(width: 16),
              const _DashedLine(color: hpColor),
              const SizedBox(width: 6),
              const Text('Тренд (HP)', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ],
    );
  }
}

class _DashedLine extends StatelessWidget {
  final Color color;
  const _DashedLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 2,
      child: CustomPaint(painter: _DashedPainter(color)),
    );
  }
}

class _DashedPainter extends CustomPainter {
  final Color color;
  _DashedPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 2;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2), Offset((x + 4).clamp(0, size.width), size.height / 2), paint);
      x += 8;
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color;
}

class _CaloriesChart extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;

  const _CaloriesChart({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final spots = List.generate(sessions.length, (i) {
      final kcal = (sessions[i]['kcal_total'] as num?)?.toDouble() ?? 0.0;
      return FlSpot(i.toDouble(), kcal);
    });

    final values = spots.map((s) => s.y);
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final yPad = maxY == minY ? 20.0 : (maxY - minY) * 0.2;

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY + yPad,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: Color(0xFF2C2C2E),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: sessions.length <= 6
                    ? 1
                    : (sessions.length / 4).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= sessions.length) {
                    return const SizedBox.shrink();
                  }
                  final date = sessions[idx]['date'] as String? ?? '';
                  final parts = date.split('-');
                  final label = parts.length >= 3
                      ? '${parts[2]}.${parts[1]}'
                      : date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: List.generate(
            sessions.length,
            (i) => BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (sessions[i]['kcal_total'] as num?)?.toDouble() ?? 0.0,
                  color: AppColors.accent,
                  width: sessions.length > 10 ? 8 : 14,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AchievementsGrid extends StatelessWidget {
  final List<Achievement> achievements;

  const _AchievementsGrid({required this.achievements});

  @override
  Widget build(BuildContext context) {
    if (achievements.isEmpty) return const SizedBox.shrink();

    final categoryOrder = <String>[];
    final grouped = <String, List<Achievement>>{};
    for (final a in achievements) {
      if (!grouped.containsKey(a.category)) {
        categoryOrder.add(a.category);
        grouped[a.category] = [];
      }
      grouped[a.category]!.add(a);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cat in categoryOrder) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              cat,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: grouped[cat]!.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, i) {
              final a = grouped[cat]![i];
              return _AchievementCell(achievement: a);
            },
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _AchievementCell extends StatelessWidget {
  final Achievement achievement;
  const _AchievementCell({required this.achievement});

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    final locked = !a.unlocked;
    final frac = a.progressFraction;

    return Tooltip(
      message: locked
          ? '${a.description}\n${_progressLabel(a)} / ${_thresholdLabel(a)}'
          : a.description,
      child: Container(
        decoration: BoxDecoration(
          color: locked ? AppColors.surface : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: a.unlocked
              ? Border.all(color: AppColors.accent.withValues(alpha: 0.5), width: 1.5)
              : Border.all(color: AppColors.surface, width: 1),
        ),
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ColorFiltered(
              colorFilter: locked
                  ? const ColorFilter.matrix([
                      0.25, 0, 0, 0, 0,
                      0, 0.25, 0, 0, 0,
                      0, 0, 0.25, 0, 0,
                      0, 0, 0, 0.6, 0,
                    ])
                  : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
              child: Text(a.emoji, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(height: 5),
            Text(
              a.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: locked
                    ? AppColors.textSecondary.withValues(alpha: 0.5)
                    : AppColors.textPrimary,
              ),
            ),
            if (locked) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 3,
                  backgroundColor: AppColors.card,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.accent.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_progressLabel(a)} / ${_thresholdLabel(a)}',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _progressLabel(Achievement a) {
    if (a.category == 'Объём') return _kgShort(a.progress);
    return a.progress.toInt().toString();
  }

  String _thresholdLabel(Achievement a) {
    if (a.category == 'Объём') return _kgShort(a.threshold);
    return a.threshold.toInt().toString();
  }

  String _kgShort(double kg) {
    if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(0)}к кг';
    return '${kg.toInt()} кг';
  }
}

class _ShareCard extends StatelessWidget {
  final String name;
  final int streak;
  final int totalWorkouts;
  final int workoutsThisWeek;
  final double volumeThisWeek;

  const _ShareCard({
    required this.name,
    required this.streak,
    required this.totalWorkouts,
    required this.workoutsThisWeek,
    required this.volumeThisWeek,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C1C1E), Color(0xFF2C2C2E)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fitness_center, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sportify',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Прогресс $name',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text('🔥', style: TextStyle(fontSize: 36)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$streak дней',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Стрик',
                    style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: '💪',
                  value: '$totalWorkouts',
                  label: 'Тренировок',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  icon: '📅',
                  value: '$workoutsThisWeek',
                  label: 'За неделю',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  icon: '🏋',
                  value: '${volumeThisWeek.toStringAsFixed(0)} кг',
                  label: 'Объём',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String icon;
  final String value;
  final String label;

  const _MiniStat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A3C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8E8E93)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accent),
              const SizedBox(width: 12),
              Text(label,
                  style: const TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              const Spacer(),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Volume bar chart ─────────────────────────────────────────────────────────

class _VolumeBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> weeks;
  final double? communityAvg;

  const _VolumeBarChart({required this.weeks, this.communityAvg});

  @override
  Widget build(BuildContext context) {
    final maxVol = weeks.fold<double>(
        0, (m, w) => (w['volume'] as double) > m ? (w['volume'] as double) : m);

    if (maxVol == 0) {
      return _emptyCard('Завершите тренировку, чтобы увидеть тренд');
    }

    final chartMaxY = communityAvg != null && communityAvg! > maxVol
        ? communityAvg! * 1.15
        : maxVol * 1.15;
    final n = weeks.length;

    final communitySpots = communityAvg == null || n < 2
        ? <FlSpot>[]
        : [FlSpot(0, communityAvg!), FlSpot((n - 1).toDouble(), communityAvg!)];

    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: BarChart(
              BarChartData(
                maxY: chartMaxY,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.surface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final vol = rod.toY.round();
                      return BarTooltipItem(
                        '${weeks[groupIndex]['label']}\n$vol кг',
                        const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= weeks.length || i % 2 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            weeks[i]['label'] as String,
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textSecondary),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.surface,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: weeks.asMap().entries.map((e) {
                  final vol = (e.value['volume'] as double);
                  final isLast = e.key == weeks.length - 1;
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: vol,
                        color: isLast
                            ? AppColors.accent
                            : AppColors.accent.withValues(alpha: 0.45),
                        width: 14,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          if (communitySpots.length >= 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: IgnorePointer(
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: (n - 1).toDouble(),
                    minY: 0,
                    maxY: chartMaxY,
                    backgroundColor: Colors.transparent,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: const FlTitlesData(
                      leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false, reservedSize: 0)),
                      rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false, reservedSize: 0)),
                      topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false, reservedSize: 0)),
                      bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false, reservedSize: 24)),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: communitySpots,
                        isCurved: false,
                        color: Colors.white.withValues(alpha: 0.30),
                        barWidth: 1.5,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyCard(String msg) => Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: Text(msg, style: const TextStyle(color: AppColors.textSecondary)),
      );
}

// ─── Muscle balance chart ─────────────────────────────────────────────────────

class _MuscleBalanceChart extends StatefulWidget {
  final Map<String, int> balance;

  const _MuscleBalanceChart({required this.balance});

  @override
  State<_MuscleBalanceChart> createState() => _MuscleBalanceChartState();
}

class _MuscleBalanceChartState extends State<_MuscleBalanceChart> {
  static const _labels = {
    'chest': 'Грудь',
    'back': 'Спина',
    'shoulders': 'Плечи',
    'arms': 'Руки',
    'legs': 'Ноги',
    'cardio': 'Кардио',
    'core': 'Пресс',
  };

  static const _colors = [
    Color(0xFF007AFF),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFBF5AF2),
    Color(0xFFFF453A),
    Color(0xFF30D158),
  ];

  String? _selectedCategory;
  Map<String, List<Map<String, dynamic>>>? _breakdown;
  bool _loadingBreakdown = false;

  Future<void> _loadBreakdown() async {
    if (_breakdown != null || _loadingBreakdown) return;
    setState(() => _loadingBreakdown = true);
    final data = await AnalyticsService.getMuscleGroupExerciseBreakdown();
    if (mounted) setState(() { _breakdown = data; _loadingBreakdown = false; });
  }

  void _tapCategory(String cat) {
    if (_selectedCategory == cat) {
      setState(() => _selectedCategory = null);
      return;
    }
    setState(() => _selectedCategory = cat);
    _loadBreakdown();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.balance.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: const Text('Нет данных за последние 30 дней',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final total = widget.balance.values.fold(0, (s, v) => s + v);
    final entries = widget.balance.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sections = entries.asMap().entries.map((e) {
      final colorIndex = e.key % _colors.length;
      final count = e.value.value;
      final pct = count / total;
      final color = _colors[colorIndex];
      final isSelected = _selectedCategory == e.value.key;
      return PieChartSectionData(
        value: count.toDouble(),
        color: color,
        title: '${(pct * 100).round()}%',
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
        radius: isSelected ? 28 : 21,
        titlePositionPercentageOffset: 0.65,
      );
    }).toList();

    final exercises = _selectedCategory != null
        ? (_breakdown?[_selectedCategory] ?? [])
        : <Map<String, dynamic>>[];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: PieChart(
                    PieChartData(
                      sections: sections,
                      centerSpaceRadius: 52,
                      sectionsSpace: 2,
                      startDegreeOffset: -90,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          if (!event.isInterestedForInteractions) return;
                          final idx = response?.touchedSection?.touchedSectionIndex;
                          if (idx != null && idx >= 0 && idx < entries.length) {
                            _tapCategory(entries[idx].key);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: 160,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: entries.asMap().entries.map((e) {
                      final colorIndex = e.key % _colors.length;
                      final cat = e.value.key;
                      final count = e.value.value;
                      final pct = count / total;
                      final label = _labels[cat] ?? cat;
                      final color = _colors[colorIndex];
                      final isSelected = _selectedCategory == cat;
                      return GestureDetector(
                        onTap: () => _tapCategory(cat),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              Text(
                                '${(pct * 100).round()}%',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _selectedCategory == null
                ? const SizedBox.shrink()
                : _loadingBreakdown
                    ? const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: SizedBox(
                          height: 32,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      )
                    : exercises.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Нет данных по упражнениям',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(color: AppColors.separator, height: 1),
                                const SizedBox(height: 12),
                                Text(
                                  _labels[_selectedCategory] ?? _selectedCategory!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...exercises.map((ex) {
                                  final name = ex['name'] as String;
                                  final sets = ex['sets'] as int;
                                  final maxSets = (exercises.first['sets'] as int).toDouble();
                                  final frac = maxSets > 0 ? sets / maxSets : 0.0;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      name,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: AppColors.textPrimary,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Text(
                                                    '$sets пд.',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: AppColors.textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(3),
                                                child: LinearProgressIndicator(
                                                  value: frac.clamp(0.0, 1.0),
                                                  minHeight: 3,
                                                  backgroundColor: AppColors.surface,
                                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                                      AppColors.accent),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// ─── Week comparison ──────────────────────────────────────────────────────────

class _WeekComparisonCard extends StatelessWidget {
  final ({double volumeThisWeek, double volumeLastWeek, int sessionsThisWeek, int sessionsLastWeek}) cmp;

  const _WeekComparisonCard({required this.cmp});

  @override
  Widget build(BuildContext context) {
    final volDiff = cmp.volumeThisWeek - cmp.volumeLastWeek;
    final sessDiff = cmp.sessionsThisWeek - cmp.sessionsLastWeek;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Эта неделя vs прошлая',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CmpColumn(
                  label: 'Тренировок',
                  thisWeek: '${cmp.sessionsThisWeek}',
                  lastWeek: '${cmp.sessionsLastWeek}',
                  diff: sessDiff,
                ),
              ),
              Container(width: 1, height: 48, color: AppColors.surface),
              Expanded(
                child: _CmpColumn(
                  label: 'Объём',
                  thisWeek: '${cmp.volumeThisWeek.toStringAsFixed(0)} кг',
                  lastWeek: '${cmp.volumeLastWeek.toStringAsFixed(0)} кг',
                  diff: volDiff,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CmpColumn extends StatelessWidget {
  final String label;
  final String thisWeek;
  final String lastWeek;
  final num diff;

  const _CmpColumn({
    required this.label,
    required this.thisWeek,
    required this.lastWeek,
    required this.diff,
  });

  @override
  Widget build(BuildContext context) {
    final isUp = diff > 0;
    final isDown = diff < 0;
    final arrowIcon = isUp
        ? Icons.arrow_upward_rounded
        : isDown
            ? Icons.arrow_downward_rounded
            : Icons.remove_rounded;
    final arrowColor = isUp
        ? const Color(0xFF30D158)
        : isDown
            ? AppColors.error
            : AppColors.textSecondary;

    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          thisWeek,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(arrowIcon, size: 14, color: arrowColor),
            const SizedBox(width: 2),
            Text(
              lastWeek,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Muscle frequency chart ───────────────────────────────────────────────────

class _MuscleFrequencyChart extends StatelessWidget {
  final Map<String, double> frequency;

  const _MuscleFrequencyChart({required this.frequency});

  static const _categoryOrder = [
    'chest', 'back', 'shoulders', 'arms', 'legs', 'core', 'cardio',
  ];

  @override
  Widget build(BuildContext context) {
    final entries = _categoryOrder
        .where((c) => frequency.containsKey(c))
        .map((c) => MapEntry(c, frequency[c]!))
        .toList();

    if (entries.isEmpty) return const SizedBox();

    final maxVal = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: (maxVal * 1.3).ceilToDouble().clamp(1, double.infinity),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppColors.surface, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= entries.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _short(entries[i].key),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: entries.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value.value,
                  color: AppColors.accent,
                  width: 18,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  String _short(String cat) {
    const map = {
      'chest': 'Грудь',
      'back': 'Спина',
      'shoulders': 'Плечи',
      'arms': 'Руки',
      'legs': 'Ноги',
      'core': 'Пресс',
      'cardio': 'Кардио',
    };
    return map[cat] ?? cat;
  }
}

