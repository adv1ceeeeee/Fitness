import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/body_metrics_service.dart';
import 'package:sportwai/services/profile_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Profile? _profile;
  int _totalWorkouts = 0;
  int _bestStreak = 0;
  int _workoutsThisWeek = 0;
  double _volumeThisWeek = 0;
  bool _loading = true;

  List<Map<String, dynamic>> _trackedExercises = [];
  Map<String, dynamic>? _selectedExercise;
  Map<String, double> _exerciseProgress = {};
  bool _loadingChart = false;

  Map<String, double> _bodyWeightData = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await ProfileService.getProfile();
    final total = await AnalyticsService.getTotalWorkouts();
    final streak = await AnalyticsService.getBestStreak();
    final weekCount = await AnalyticsService.getWorkoutsThisWeek();
    final volume = await AnalyticsService.getVolumeThisWeek();
    final tracked = await AnalyticsService.getTrackedExercises();
    final bodyHistory = await BodyMetricsService.getHistory();

    final bodyWeightData = <String, double>{};
    for (final row in bodyHistory) {
      final date = row['date'] as String?;
      final w = row['weight_kg'];
      if (date != null && w != null) {
        bodyWeightData[date] = (w as num).toDouble();
      }
    }

    if (mounted) {
      setState(() {
        _profile = profile;
        _totalWorkouts = total;
        _bestStreak = streak;
        _workoutsThisWeek = weekCount;
        _volumeThisWeek = volume;
        _trackedExercises = tracked;
        _bodyWeightData = bodyWeightData;
        _loading = false;
      });
    }
  }

  Future<void> _loadExerciseProgress(String exerciseId) async {
    if (!mounted) return;
    setState(() => _loadingChart = true);
    final data = await AnalyticsService.getExerciseMaxWeight(exerciseId);
    if (mounted) setState(() { _exerciseProgress = data; _loadingChart = false; });
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
        body: Center(child: CircularProgressIndicator()),
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
            padding: const EdgeInsets.all(24),
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
                  'Динамика веса тела',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (_bodyWeightData.isEmpty)
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
                else
                  _ProgressChart(data: _bodyWeightData),
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
                            : _ProgressChart(data: _exerciseProgress),
                ],
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
                Material(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () {
                      final name = _profile?.fullName?.split(' ').first ?? 'Атлет';
                      final text =
                          'Мои достижения в Sportify:\n'
                          '🔥 Стрик: $_bestStreak дней\n'
                          '💪 Тренировок всего: $_totalWorkouts\n'
                          '📅 За неделю: $_workoutsThisWeek тренировок\n'
                          '🏋 Объём за неделю: ${_volumeThisWeek.toStringAsFixed(0)} кг\n'
                          '\nПрисоединяйся, $name тренируется в Sportify!';
                      Share.share(text);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: const Padding(
                      padding: EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Icon(Icons.share, color: AppColors.accent, size: 32),
                          SizedBox(width: 16),
                          Text(
                            'Создать картинку с достижениями',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
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

  const _ProgressChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final sorted = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final spots = List.generate(
      sorted.length,
      (i) => FlSpot(i.toDouble(), sorted[i].value),
    );

    final minY = sorted.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    final maxY = sorted.map((e) => e.value).reduce((a, b) => a > b ? a : b);
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
