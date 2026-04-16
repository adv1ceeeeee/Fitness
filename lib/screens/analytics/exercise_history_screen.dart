import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/screens/shared/feedback_sheets.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/image_cache_manager.dart';

class ExerciseHistoryScreen extends StatefulWidget {
  final Exercise exercise;
  const ExerciseHistoryScreen({super.key, required this.exercise});

  @override
  State<ExerciseHistoryScreen> createState() => _ExerciseHistoryScreenState();
}

class _ExerciseHistoryScreenState extends State<ExerciseHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  List<Map<String, dynamic>>? _history;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final h = await AnalyticsService.getExerciseHistory(widget.exercise.id);
    if (mounted) setState(() => _history = h);
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;
    final ex = widget.exercise;

    double? pb;
    String? pbDate;
    double? pbOrm;
    if (history != null) {
      for (final e in history) {
        final w = e['maxWeight'] as double;
        final orm = e['oneRepMax'] as double;
        if (w > 0 && (pb == null || w > pb)) {
          pb = w;
          pbDate = e['date'] as String;
        }
        if (orm > 0 && (pbOrm == null || orm > pbOrm)) {
          pbOrm = orm;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(ex.displayName, overflow: TextOverflow.ellipsis),
        actions: const [ScreenThumbsWidget(screen: 'exercise_history')],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'Вес'),
            Tab(text: 'Объём'),
            Tab(text: '1RM'),
          ],
        ),
      ),
      body: history == null
          ? const Center(child: CircularProgressIndicator())
          : history.isEmpty
              ? const Center(
                  child: Text(
                    'Ещё нет тренировок по этому упражнению',
                    style: TextStyle(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                )
              : Column(
                  children: [
                    if (ex.gifUrl != null)
                      CachedNetworkImage(
                        cacheManager: AppImageCacheManager.instance,
                        imageUrl: ex.gifUrl!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const SizedBox(height: 160),
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    if (pb != null && pbDate != null)
                      _PbBanner(weight: pb, date: pbDate, oneRepMax: pbOrm),
                    Expanded(
                      child: TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _ChartTab(
                            history: history,
                            valueKey: 'maxWeight',
                            label: 'Макс. вес (кг)',
                          ),
                          _ChartTab(
                            history: history,
                            valueKey: 'volume',
                            label: 'Объём (кг·повт.)',
                          ),
                          _ChartTab(
                            history: history,
                            valueKey: 'oneRepMax',
                            label: '1RM — Эпли (кг)',
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    _SessionList(history: history),
                  ],
                ),
    );
  }
}

// ─── Personal best banner ─────────────────────────────────────────────────────

class _PbBanner extends StatelessWidget {
  final double weight;
  final String date;
  final double? oneRepMax;
  const _PbBanner({required this.weight, required this.date, this.oneRepMax});

  @override
  Widget build(BuildContext context) {
    final w = weight % 1 == 0 ? weight.toInt().toString() : weight.toStringAsFixed(1);
    final d = _fmtDate(date);
    final ormStr = oneRepMax != null && oneRepMax! > 0
        ? oneRepMax! % 1 == 0
            ? oneRepMax!.toInt().toString()
            : oneRepMax!.toStringAsFixed(1)
        : null;
    return Container(
      width: double.infinity,
      color: AppColors.accent.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFB800), size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Личный рекорд: $w кг  ($d)',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (ormStr != null)
                Text(
                  '1RM (Эпли): ~$ormStr кг',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Chart tab ────────────────────────────────────────────────────────────────

class _ChartTab extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final String valueKey;
  final String label;
  const _ChartTab({required this.history, required this.valueKey, required this.label});

  @override
  Widget build(BuildContext context) {
    final points = history
        .asMap()
        .entries
        .where((e) => (e.value[valueKey] as double) > 0)
        .map((e) => FlSpot(e.key.toDouble(), (e.value[valueKey] as double)))
        .toList();

    if (points.isEmpty) {
      return const Center(
        child: Text('Нет данных', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final maxY = points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final minY = points.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final yRange = (maxY - minY).clamp(10.0, double.infinity);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: (minY - yRange * 0.1).clamp(0, double.infinity),
                maxY: maxY + yRange * 0.15,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.textSecondary.withValues(alpha: 0.1),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (v, _) => Text(
                        v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 10),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: (points.length / 5).ceilToDouble().clamp(1, double.infinity),
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= history.length) return const SizedBox.shrink();
                        final date = history[idx]['date'] as String;
                        return Text(
                          _shortDate(date),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 9),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: points,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: AppColors.accent,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                        radius: 3,
                        color: AppColors.accent,
                        strokeWidth: 0,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accent.withValues(alpha: 0.25),
                          AppColors.accent.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Session list ─────────────────────────────────────────────────────────────

class _SessionList extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _SessionList({required this.history});

  @override
  Widget build(BuildContext context) {
    final reversed = history.reversed.take(20).toList();
    return SizedBox(
      height: 200,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: reversed.length,
        itemBuilder: (_, i) {
          final e = reversed[i];
          final w = e['maxWeight'] as double;
          final orm = e['oneRepMax'] as double;
          final reps = e['reps'] as int;
          final date = _fmtDate(e['date'] as String);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(date,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ),
                Expanded(
                  child: Text(
                    w > 0 ? '${w % 1 == 0 ? w.toInt() : w.toStringAsFixed(1)} кг' : '—',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                Expanded(
                  child: Text(
                    '$reps повт.',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    orm > 0
                        ? '~${orm % 1 == 0 ? orm.toInt() : orm.toStringAsFixed(1)} 1RM'
                        : '—',
                    style: const TextStyle(
                        color: AppColors.accent, fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _fmtDate(String iso) {
  try {
    final d = DateTime.parse(iso);
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  } catch (_) {
    return iso;
  }
}

String _shortDate(String iso) {
  try {
    final d = DateTime.parse(iso);
    return '${d.day}.${d.month.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}
