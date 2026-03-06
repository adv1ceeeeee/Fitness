import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/body_metrics_service.dart';

class BodyMetricsScreen extends StatefulWidget {
  const BodyMetricsScreen({super.key});

  @override
  State<BodyMetricsScreen> createState() => _BodyMetricsScreenState();
}

class _BodyMetricsScreenState extends State<BodyMetricsScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = await BodyMetricsService.getHistory();
    if (mounted) setState(() { _history = h; _loading = false; });
  }

  void _openLogSheet() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LogMetricsSheet(
        onSaved: () {
          setState(() => _loading = true);
          _load();
        },
      ),
    );
  }

  String _formatDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length < 3) return dateStr;
    return '${parts[2]}.${parts[1]}.${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Параметры тела')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openLogSheet,
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Weight chart
                  if (_history.isNotEmpty) ...[
                    const Text(
                      'Динамика веса',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildWeightChart(),
                    const SizedBox(height: 32),
                  ],

                  // History list
                  const Text(
                    'История',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_history.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text(
                          'Нет записей.\nНажмите + чтобы добавить первую.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    ..._history.reversed.take(30).map((row) {
                      final date = row['date'] as String? ?? '';
                      final weight = row['weight_kg'];
                      final fat = row['body_fat_pct'];
                      final waist = row['waist_cm'];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Text(
                                _formatDate(date),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Wrap(
                                  spacing: 16,
                                  children: [
                                    if (weight != null)
                                      _Chip(
                                        label:
                                            '${(weight as num).toStringAsFixed(1)} кг',
                                        icon: Icons.monitor_weight_outlined,
                                      ),
                                    if (fat != null)
                                      _Chip(
                                        label:
                                            '${(fat as num).toStringAsFixed(1)}% жира',
                                        icon: Icons.percent,
                                      ),
                                    if (waist != null)
                                      _Chip(
                                        label:
                                            '${(waist as num).toStringAsFixed(1)} см',
                                        icon: Icons.straighten,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildWeightChart() {
    final weightData = _history
        .where((r) => r['weight_kg'] != null)
        .toList();

    if (weightData.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('Нет данных о весе',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final spots = List.generate(
      weightData.length,
      (i) => FlSpot(i.toDouble(),
          (weightData[i]['weight_kg'] as num).toDouble()),
    );

    final values = spots.map((s) => s.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final yPad = maxY == minY ? 2.0 : (maxY - minY) * 0.2;

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
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: weightData.length <= 6
                    ? 1
                    : (weightData.length / 4).ceilToDouble(),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= weightData.length) {
                    return const SizedBox.shrink();
                  }
                  final parts =
                      (weightData[idx]['date'] as String).split('-');
                  final label = parts.length >= 3
                      ? '${parts[2]}.${parts[1]}'
                      : weightData[idx]['date'] as String;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary)),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
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

// ─── Log sheet ────────────────────────────────────────────────────────────────

class _LogMetricsSheet extends StatefulWidget {
  final VoidCallback onSaved;

  const _LogMetricsSheet({required this.onSaved});

  @override
  State<_LogMetricsSheet> createState() => _LogMetricsSheetState();
}

class _LogMetricsSheetState extends State<_LogMetricsSheet> {
  final _weightCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _fatCtrl.dispose();
    _waistCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    final fat = double.tryParse(_fatCtrl.text.replaceAll(',', '.'));
    final waist = double.tryParse(_waistCtrl.text.replaceAll(',', '.'));

    if (weight == null && fat == null && waist == null) return;

    setState(() => _saving = true);
    await BodyMetricsService.upsert(
      weightKg: weight,
      bodyFatPct: fat,
      waistCm: waist,
    );
    if (mounted) {
      Navigator.pop(context);
      widget.onSaved();
    }
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
          const Text(
            'Добавить замер',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _weightCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Вес (кг)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fatCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '% жира'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _waistCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Талия (см)'),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
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

// ─── Helper chip ──────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Chip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.accent),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14)),
      ],
    );
  }
}
