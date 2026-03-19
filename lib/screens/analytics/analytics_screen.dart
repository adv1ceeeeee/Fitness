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

class _AnalyticsScreenState extends State<AnalyticsScreen> {
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
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
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(context).padding.bottom + 80),
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
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _changeGoal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Твоя цель: ${_goalDisplay(goal)}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_rounded,
                          size: 14, color: AppColors.textSecondary),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _StreakCard(
                  streak: _bestStreak,
                  totalWorkouts: _totalWorkouts,
                  freezeActive: StreakFreezeService.freezeIsActive,
                  hasFreeze: StreakFreezeService.hasFreeze,
                ),
                const SizedBox(height: 12),
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
                _WorkoutHeatmap(data: _heatmapData),
                const SizedBox(height: 24),
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
                        value: _workoutsThisWeek.toDouble(),
                        format: (v) => v.round().toString(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatBox(
                        label: 'Объём (кг)',
                        value: _volumeThisWeek,
                        format: (v) => v.toStringAsFixed(0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_weekComparison != null)
                  _WeekComparisonCard(cmp: _weekComparison!),
                const SizedBox(height: 32),
                const Text(
                  'Тренд объёма нагрузки',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Последние 8 недель (кг × повт.)',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                _VolumeBarChart(weeks: _weeklyVolume, communityAvg: _communityAvgWeeklyVolume),
                const SizedBox(height: 32),
                const Text(
                  'Динамика параметров тела',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (_bodyHistory.isEmpty)
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<String>(
                      value: _availableBodyMetrics.contains(_selectedBodyMetric)
                          ? _selectedBodyMetric
                          : _availableBodyMetrics.first,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: AppColors.card,
                      style: const TextStyle(color: AppColors.textPrimary),
                      items: _availableBodyMetrics.map((key) {
                        return DropdownMenuItem<String>(
                          value: key,
                          child: Text(_bodyMetricOptions[key] ?? key),
                        );
                      }).toList(),
                      onChanged: (key) {
                        if (key != null) {
                          setState(() => _selectedBodyMetric = key);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_bodyMetricData.isEmpty)
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
                  else
                    _ProgressChart(data: _bodyMetricData),
                  // No community avg for body metrics — it's personal data
                ],
                const SizedBox(height: 32),
                const Text(
                  'Прогресс по упражнению',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (_trackedExercises.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'Завершите тренировку с весом,\nчтобы увидеть прогресс',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<Map<String, dynamic>>(
                      value: _selectedExercise,
                      hint: const Text('Выберите упражнение',
                          style: TextStyle(color: AppColors.textSecondary)),
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: AppColors.card,
                      style: const TextStyle(color: AppColors.textPrimary),
                      items: _trackedExercises
                          .map((ex) => DropdownMenuItem(
                                value: ex,
                                child: Text(ex['name'] as String),
                              ))
                          .toList(),
                      onChanged: (ex) {
                        setState(() {
                          _selectedExercise = ex;
                          _exerciseProgress = {};
                        });
                        if (ex != null) {
                          _loadExerciseProgress(ex['id'] as String);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_selectedExercise != null)
                    _loadingChart
                        ? const SizedBox(
                            height: 180,
                            child: Center(
                                child: CircularProgressIndicator()))
                        : _exerciseProgress.isEmpty
                            ? Container(
                                height: 80,
                                alignment: Alignment.center,
                                child: const Text('Нет данных',
                                    style: TextStyle(
                                        color: AppColors.textSecondary)),
                              )
                            : _ProgressChart(
                                data: _exerciseProgress,
                                communityAvg: _communityAvgExerciseWeight,
                              ),
                ],
                const SizedBox(height: 32),
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
                if (_caloriesPerSession.isEmpty)
                  Container(
                    height: 80,
                    alignment: Alignment.center,
                    child: const Text(
                      'Завершите тренировку,\nчтобы увидеть данные о калориях',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  _CaloriesChart(sessions: _caloriesPerSession),
                const SizedBox(height: 32),
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
                _MuscleBalanceChart(balance: _muscleBalance),
                if (_muscleFrequency.isNotEmpty) ...[
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
                  _MuscleFrequencyChart(frequency: _muscleFrequency),
                ],
                const SizedBox(height: 32),
                const Text(
                  'Достижения',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _AchievementsGrid(achievements: _achievements),
                const SizedBox(height: 32),
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
                  key: _shareKey,
                  child: _ShareCard(
                    name: _profile?.fullName?.split(' ').first ?? 'Атлет',
                    streak: _bestStreak,
                    totalWorkouts: _totalWorkouts,
                    workoutsThisWeek: _workoutsThisWeek,
                    volumeThisWeek: _volumeThisWeek,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sharing ? null : _shareAsImage,
                    icon: _sharing
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
        ),
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final sorted = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final spots = List.generate(
      sorted.length,
      (i) => FlSpot(i.toDouble(), sorted[i].value),
    );

    // Community average as flat second line across the x range
    final communitySpots = communityAvg == null || sorted.length < 2
        ? <FlSpot>[]
        : [
            FlSpot(0, communityAvg!),
            FlSpot((sorted.length - 1).toDouble(), communityAvg!),
          ];

    final dataMin = sorted.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    final dataMax = sorted.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final allValues = [dataMin, dataMax, if (communityAvg != null) communityAvg!];
    final minY = allValues.reduce((a, b) => a < b ? a : b);
    final maxY = allValues.reduce((a, b) => a > b ? a : b);
    final yPad = maxY == minY ? 5.0 : (maxY - minY) * 0.2;

    return Container(
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
            // Community average line (behind main line)
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
            // Main user data line
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
          ],
        ),
      ),
    );
  }
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

    // Group by category preserving order of first appearance
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
          color: locked
              ? AppColors.surface
              : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: a.unlocked
              ? Border.all(
                  color: AppColors.accent.withValues(alpha: 0.5), width: 1.5)
              : Border.all(
                  color: AppColors.surface, width: 1),
        ),
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Emoji (greyscale if locked)
            ColorFiltered(
              colorFilter: locked
                  ? const ColorFilter.matrix([
                      0.25, 0, 0, 0, 0,
                      0, 0.25, 0, 0, 0,
                      0, 0, 0.25, 0, 0,
                      0, 0, 0, 0.6, 0,
                    ])
                  : const ColorFilter.mode(
                      Colors.transparent, BlendMode.dst),
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
              // Progress bar
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
    if (a.category == 'Объём') {
      return _kgShort(a.progress);
    }
    return a.progress.toInt().toString();
  }

  String _thresholdLabel(Achievement a) {
    if (a.category == 'Объём') {
      return _kgShort(a.threshold);
    }
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
                  style: const TextStyle(
                      fontSize: 15, color: AppColors.textPrimary)),
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

    // Community average as flat line across all weeks
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
          // ── Bars ────────────────────────────────────────────────────────
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
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          // ── Community average overlay line ────────────────────────────────
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
        child: Text(msg,
            style: const TextStyle(color: AppColors.textSecondary)),
      );
}

// ─── Muscle balance chart ─────────────────────────────────────────────────────

class _MuscleBalanceChart extends StatelessWidget {
  final Map<String, int> balance;

  const _MuscleBalanceChart({required this.balance});

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

  @override
  Widget build(BuildContext context) {
    if (balance.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: const Text('Нет данных за последние 30 дней',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final total = balance.values.fold(0, (s, v) => s + v);
    final entries = balance.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sections = entries.asMap().entries.map((e) {
      final colorIndex = e.key % _colors.length;
      final count = e.value.value;
      final pct = count / total;
      final color = _colors[colorIndex];
      return PieChartSectionData(
        value: count.toDouble(),
        color: color,
        title: '${(pct * 100).round()}%',
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
        radius: 21,
        titlePositionPercentageOffset: 0.65,
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
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
                  return Padding(
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
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
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
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Сравнение недель ────────────────────────────────────────────────────────

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
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Частота по группам мышц ────────────────────────────────────────────────

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
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10),
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

// ─── Workout heatmap ─────────────────────────────────────────────────────────

class _WorkoutHeatmap extends StatelessWidget {
  final Map<DateTime, double> data;

  const _WorkoutHeatmap({required this.data});

  static const _cellSize = 11.0;
  static const _cellGap = 2.0;
  static const _weeks = 26;

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  Color _cellColor(double value, BuildContext context) {
    if (value <= 0) return AppColors.surface;
    // Max opacity cap — anything above 5000 kg·reps = full colour
    final t = (value / 5000).clamp(0.15, 1.0);
    return AppColors.accent.withValues(alpha: t);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Find the Sunday that ends the current week
    // weekday: Mon=1 … Sun=7
    final daysToSunday = 7 - today.weekday; // 0 on Sunday, 6 on Monday
    final lastSunday = today.add(Duration(days: daysToSunday));

    // Build columns from oldest (left) to newest (right)
    // Each column = one week Mon…Sun
    final columns = <List<DateTime>>[];
    for (int w = _weeks - 1; w >= 0; w--) {
      final weekSunday = lastSunday.subtract(Duration(days: w * 7));
      final weekDays = List.generate(
        7,
        (d) => weekSunday.subtract(Duration(days: 6 - d)), // Mon…Sun
      );
      columns.add(weekDays);
    }

    // Month label positions (first column where a new month starts)
    final monthLabels = <int, String>{};
    for (int i = 0; i < columns.length; i++) {
      final monday = columns[i].first;
      if (i == 0 || monday.month != columns[i - 1].first.month) {
        const months = [
          '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
          'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
        ];
        monthLabels[i] = months[monday.month];
      }
    }

    const totalWidth =
        _weeks * (_cellSize + _cellGap) - _cellGap + 28; // 28 for day labels

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // If the grid fits without scrolling, center it; otherwise allow scroll.
          final fits = totalWidth <= constraints.maxWidth;
          Widget grid = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildGridChildren(context, columns, monthLabels, totalWidth),
          );
          if (fits) return Center(child: grid);
          // Scale down to fit the available width and center it
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: grid,
          );
        },
      ),
    );
  }

  List<Widget> _buildGridChildren(
    BuildContext context,
    List<List<DateTime>> columns,
    Map<int, String> monthLabels,
    double totalWidth,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
            // Month labels row
            SizedBox(
              width: totalWidth,
              height: 14,
              child: Stack(
                children: monthLabels.entries.map((e) {
                  final x = 28.0 + e.key * (_cellSize + _cellGap);
                  return Positioned(
                    left: x,
                    child: Text(
                      e.value,
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
            // Day rows + cells
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Day-of-week labels (Mon, Wed, Fri only to save space)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (d) {
                    final show = d == 0 || d == 2 || d == 4 || d == 6;
                    return SizedBox(
                      height: _cellSize + _cellGap,
                      child: show
                          ? Text(
                              _dayLabels[d],
                              style: const TextStyle(
                                fontSize: 8,
                                color: AppColors.textSecondary,
                                height: 1.3,
                              ),
                            )
                          : null,
                    );
                  }),
                ),
                const SizedBox(width: 4),
                // Columns of cells
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: columns.map((weekDays) {
                    return Padding(
                      padding: const EdgeInsets.only(right: _cellGap),
                      child: Column(
                        children: weekDays.map((day) {
                          final isFuture = day.isAfter(today);
                          final volume = isFuture ? 0.0 : (data[day] ?? 0.0);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: _cellGap),
                            child: Tooltip(
                              message: isFuture
                                  ? ''
                                  : volume > 0
                                      ? '${day.day}.${day.month}: ${volume.toStringAsFixed(0)} кг·повт.'
                                      : '${day.day}.${day.month}: нет тренировки',
                              child: Container(
                                width: _cellSize,
                                height: _cellSize,
                                decoration: BoxDecoration(
                                  color: isFuture
                                      ? Colors.transparent
                                      : _cellColor(volume, context),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Legend
            Row(
              children: [
                const Text(
                  'Меньше',
                  style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 4),
                ...List.generate(5, (i) {
                  final t = i == 0 ? 0.0 : 0.15 + (i - 1) * 0.2125;
                  return Container(
                    width: _cellSize,
                    height: _cellSize,
                    margin: const EdgeInsets.only(right: _cellGap),
                    decoration: BoxDecoration(
                      color: i == 0
                          ? AppColors.surface
                          : AppColors.accent.withValues(alpha: t),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
                const Text(
                  'Больше',
                  style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
                ),
              ],
            ),
        ];
  }
}

