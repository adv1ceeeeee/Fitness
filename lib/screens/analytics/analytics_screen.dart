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
import 'package:sportwai/services/profile_service.dart';
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

  List<Achievement> _achievements = [];
  List<Map<String, dynamic>> _weeklyVolume = [];
  Map<String, int> _muscleBalance = {};
  List<Map<String, dynamic>> _caloriesPerSession = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
        final caloriesPerSession = await AnalyticsService.getCaloriesPerSession();
        final communityAvgVol = await AnalyticsService.getCommunityAvgWeeklyVolume();

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
            _caloriesPerSession = caloriesPerSession;
            _communityAvgWeeklyVolume = communityAvgVol;
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

  static String _goalDisplay(String? goal) {
    const map = {
      'strength': 'Сила',
      'weight_loss': 'Похудение',
      'mass_gain': 'Набор массы',
      'endurance': 'Выносливость',
    };
    return map[goal ?? ''] ?? (goal ?? '—');
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
                Text(
                  'Твоя цель: ${_goalDisplay(goal)}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                _StreakCard(
                  streak: _bestStreak,
                  totalWorkouts: _totalWorkouts,
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
                        value: '$_workoutsThisWeek',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatBox(
                        label: 'Объём (кг)',
                        value: _volumeThisWeek.toStringAsFixed(0),
                      ),
                    ),
                  ],
                ),
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

class _StreakCard extends StatelessWidget {
  final int streak;
  final int totalWorkouts;

  const _StreakCard({
    required this.streak,
    required this.totalWorkouts,
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
              const Text('🔥', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Text(
                'Стрик: $streak дней',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Тренировок всего: $totalWorkouts',
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

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
          Text(
            value,
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
          extraLinesData: communityAvg == null
              ? null
              : ExtraLinesData(horizontalLines: [
                  HorizontalLine(
                    y: communityAvg!,
                    color: Colors.grey.withValues(alpha: 0.55),
                    strokeWidth: 1.5,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      labelResolver: (_) =>
                          'avg ${communityAvg!.toStringAsFixed(1)}',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 10),
                    ),
                  ),
                ]),
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
      final kcal = (sessions[i]['kcal_total'] as num).toDouble();
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
                  toY: (sessions[i]['kcal_total'] as num).toDouble(),
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: achievements.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.88,
      ),
      itemBuilder: (context, i) {
        final a = achievements[i];
        final locked = !a.unlocked;
        return Tooltip(
          message: a.description,
          child: Container(
            decoration: BoxDecoration(
              color: locked
                  ? AppColors.card.withValues(alpha: 0.5)
                  : AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: a.unlocked
                  ? Border.all(color: AppColors.accent.withValues(alpha: 0.4), width: 1.5)
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ColorFiltered(
                  colorFilter: locked
                      ? const ColorFilter.matrix([
                          0.2, 0, 0, 0, 0,
                          0, 0.2, 0, 0, 0,
                          0, 0, 0.2, 0, 0,
                          0, 0, 0, 1, 0,
                        ])
                      : const ColorFilter.mode(
                          Colors.transparent, BlendMode.dst),
                  child: Text(a.emoji,
                      style: const TextStyle(fontSize: 28)),
                ),
                const SizedBox(height: 6),
                Text(
                  a.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: locked
                        ? AppColors.textSecondary.withValues(alpha: 0.5)
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          maxY: communityAvg != null && communityAvg! > maxVol
              ? communityAvg! * 1.15
              : maxVol * 1.15,
          extraLinesData: communityAvg == null
              ? null
              : ExtraLinesData(horizontalLines: [
                  HorizontalLine(
                    y: communityAvg!,
                    color: Colors.grey.withValues(alpha: 0.55),
                    strokeWidth: 1.5,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      labelResolver: (_) =>
                          'avg ${(communityAvg! / 1000).toStringAsFixed(1)}к',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 10),
                    ),
                  ),
                ]),
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
                reservedSize: 24,
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
