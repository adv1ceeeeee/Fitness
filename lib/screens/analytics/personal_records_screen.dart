import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/app_cache.dart';
import 'package:sportwai/services/auth_service.dart';

class PersonalRecordsScreen extends StatefulWidget {
  const PersonalRecordsScreen({super.key});

  @override
  State<PersonalRecordsScreen> createState() => _PersonalRecordsScreenState();
}

class _PersonalRecordsScreenState extends State<PersonalRecordsScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = AuthService.currentUser?.id;
    if (userId != null) {
      final cached = await AppCache.peek<List<Map<String, dynamic>>>(
        key: 'personal_records:$userId',
        decode: (s) => (jsonDecode(s) as List).cast<Map<String, dynamic>>(),
      );
      if (cached != null && mounted) {
        setState(() { _records = cached; _loading = false; });
      }
    }
    _refreshRecords();
  }

  Future<void> _refreshRecords() async {
    final records = await AnalyticsService.getPersonalRecords();
    if (mounted) setState(() { _records = records; _loading = false; });
  }

  String _fmtDate(String raw) {
    if (raw.length < 10) return raw;
    return '${raw.substring(8, 10)}.${raw.substring(5, 7)}.${raw.substring(0, 4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Личные рекорды')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.emoji_events_rounded,
                            size: 48, color: AppColors.accent),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Рекордов пока нет',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Завершите тренировку с весом,\nчтобы появились рекорды',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshRecords,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _records.length,
                    itemBuilder: (_, i) {
                      final r = _records[i];
                      return _PrCard(
                        record: r,
                        fmtDate: _fmtDate,
                      );
                    },
                  ),
                ),
    );
  }
}

class _PrCard extends StatefulWidget {
  final Map<String, dynamic> record;
  final String Function(String) fmtDate;

  const _PrCard({required this.record, required this.fmtDate});

  @override
  State<_PrCard> createState() => _PrCardState();
}

class _PrCardState extends State<_PrCard> {
  bool _expanded = false;
  bool _loadingHistory = false;
  List<Map<String, dynamic>>? _history;

  Future<void> _loadHistory() async {
    if (_history != null) return;
    setState(() => _loadingHistory = true);
    final exerciseId = widget.record['exerciseId'] as String;
    final history = await AnalyticsService.getExercisePrHistory(exerciseId);
    if (mounted) setState(() { _history = history; _loadingHistory = false; });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final w = r['weightKg'] as double;
    final wStr = w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(1);

    return GestureDetector(
      onTap: () {
        setState(() => _expanded = !_expanded);
        if (!_expanded) _loadHistory();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.emoji_events_rounded,
                        color: AppColors.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      r['exerciseName'] as String,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$wStr кг',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accent,
                        ),
                      ),
                      Text(
                        widget.fmtDate(r['date'] as String),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _loadingHistory
                          ? const SizedBox(
                              height: 80,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _history == null || _history!.length < 2
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    'Недостаточно данных для графика',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary),
                                  ),
                                )
                              : _PrHistoryChart(history: _history!),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrHistoryChart extends StatelessWidget {
  final List<Map<String, dynamic>> history;

  const _PrHistoryChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final spots = List.generate(
      history.length,
      (i) => FlSpot(i.toDouble(), (history[i]['weight_kg'] as double)),
    );
    final values = spots.map((s) => s.y);
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = maxY == minY ? 5.0 : (maxY - minY) * 0.25;

    return SizedBox(
      height: 120,
      child: LineChart(
        LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(0),
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: history.length <= 5
                    ? 1
                    : (history.length / 4).ceilToDouble(),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= history.length) {
                    return const SizedBox.shrink();
                  }
                  final date = history[idx]['achieved_at'] as String;
                  final label = date.length >= 10
                      ? '${date.substring(8, 10)}.${date.substring(5, 7)}'
                      : date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textSecondary)),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                  radius: 3.5,
                  color: AppColors.accent,
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.accent.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
