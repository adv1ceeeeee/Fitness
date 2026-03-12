import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/providers/settings_provider.dart';
import 'package:sportwai/screens/profile/body_silhouette_widget.dart';
import 'package:sportwai/services/body_metrics_service.dart';
import 'package:sportwai/services/event_logger.dart';

class BodyMetricsScreen extends ConsumerStatefulWidget {
  const BodyMetricsScreen({super.key});

  @override
  ConsumerState<BodyMetricsScreen> createState() => _BodyMetricsScreenState();
}

class _BodyMetricsScreenState extends ConsumerState<BodyMetricsScreen> {
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

  String _fmtCm(dynamic v, bool useCm) {
    if (v == null) return '—';
    final d = cmToDisplay((v as num).toDouble(), useCm);
    return d % 1 == 0 ? '${d.toInt()}' : d.toStringAsFixed(1);
  }

  String _fmtKg(dynamic v, bool useKg) {
    if (v == null) return '—';
    final d = kgToDisplay((v as num).toDouble(), useKg);
    return d % 1 == 0 ? '${d.toInt()}' : d.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final useKg = ref.watch(useKgProvider);
    final useCm = ref.watch(useCmProvider);
    final lenLabel = lengthLabel(useCm);
    final wLabel = weightLabel(useKg);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Параметры тела'),
        actions: [
          IconButton(
            onPressed: _openLogSheet,
            icon: const Icon(Icons.add),
            color: AppColors.accent,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Body silhouette — always shown, uses latest measurement row
                  BodySilhouetteWidget(
                    measurements: _history.isNotEmpty ? _history.last : null,
                  ),
                  const SizedBox(height: 24),

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
                    _buildWeightChart(useKg),
                    const SizedBox(height: 32),
                  ],
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

                      final chips = <_ChipItem>[
                        if (row['weight_kg'] != null)
                          _ChipItem(Icons.monitor_weight_outlined, '${_fmtKg(row['weight_kg'], useKg)} $wLabel'),
                        if (row['body_fat_pct'] != null)
                          _ChipItem(Icons.percent, '${(row['body_fat_pct'] as num).toStringAsFixed(1)}% жира'),
                        if (row['neck_cm'] != null)
                          _ChipItem(Icons.straighten, 'Шея: ${_fmtCm(row['neck_cm'], useCm)} $lenLabel'),
                        if (row['shoulders_cm'] != null)
                          _ChipItem(Icons.straighten, 'Плечи: ${_fmtCm(row['shoulders_cm'], useCm)} $lenLabel'),
                        if (row['chest_cm'] != null)
                          _ChipItem(Icons.straighten, 'Грудь: ${_fmtCm(row['chest_cm'], useCm)} $lenLabel'),
                        if (row['waist_cm'] != null)
                          _ChipItem(Icons.straighten, 'Талия: ${_fmtCm(row['waist_cm'], useCm)} $lenLabel'),
                        if (row['hips_cm'] != null)
                          _ChipItem(Icons.straighten, 'Таз: ${_fmtCm(row['hips_cm'], useCm)} $lenLabel'),
                        if (row['right_arm_cm'] != null)
                          _ChipItem(Icons.straighten, 'Пр.плечо: ${_fmtCm(row['right_arm_cm'], useCm)} $lenLabel'),
                        if (row['left_arm_cm'] != null)
                          _ChipItem(Icons.straighten, 'Лев.плечо: ${_fmtCm(row['left_arm_cm'], useCm)} $lenLabel'),
                        if (row['right_forearm_cm'] != null)
                          _ChipItem(Icons.straighten, 'Пр.предпл.: ${_fmtCm(row['right_forearm_cm'], useCm)} $lenLabel'),
                        if (row['left_forearm_cm'] != null)
                          _ChipItem(Icons.straighten, 'Лев.предпл.: ${_fmtCm(row['left_forearm_cm'], useCm)} $lenLabel'),
                        if (row['right_thigh_cm'] != null)
                          _ChipItem(Icons.straighten, 'Пр.бедро: ${_fmtCm(row['right_thigh_cm'], useCm)} $lenLabel'),
                        if (row['left_thigh_cm'] != null)
                          _ChipItem(Icons.straighten, 'Лев.бедро: ${_fmtCm(row['left_thigh_cm'], useCm)} $lenLabel'),
                        if (row['right_calf_cm'] != null)
                          _ChipItem(Icons.straighten, 'Пр.голень: ${_fmtCm(row['right_calf_cm'], useCm)} $lenLabel'),
                        if (row['left_calf_cm'] != null)
                          _ChipItem(Icons.straighten, 'Лев.голень: ${_fmtCm(row['left_calf_cm'], useCm)} $lenLabel'),
                      ];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatDate(date),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 12,
                                runSpacing: 6,
                                children: chips
                                    .map((c) => _Chip(label: c.label, icon: c.icon))
                                    .toList(),
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

  Widget _buildWeightChart(bool useKg) {
    final weightData = _history.where((r) => r['weight_kg'] != null).toList();

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
      (i) => FlSpot(
        i.toDouble(),
        kgToDisplay((weightData[i]['weight_kg'] as num).toDouble(), useKg),
      ),
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
                            fontSize: 10, color: AppColors.textSecondary)),
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

class _LogMetricsSheet extends ConsumerStatefulWidget {
  final VoidCallback onSaved;

  const _LogMetricsSheet({required this.onSaved});

  @override
  ConsumerState<_LogMetricsSheet> createState() => _LogMetricsSheetState();
}

class _LogMetricsSheetState extends ConsumerState<_LogMetricsSheet> {
  final _weightCtrl     = TextEditingController();
  final _fatCtrl        = TextEditingController();
  final _neckCtrl       = TextEditingController();
  final _shouldersCtrl  = TextEditingController();
  final _chestCtrl      = TextEditingController();
  final _waistCtrl      = TextEditingController();
  final _hipsCtrl       = TextEditingController();
  final _rightArmCtrl   = TextEditingController();
  final _leftArmCtrl    = TextEditingController();
  final _rightForearmCtrl = TextEditingController();
  final _leftForearmCtrl  = TextEditingController();
  final _rightThighCtrl = TextEditingController();
  final _leftThighCtrl  = TextEditingController();
  final _rightCalfCtrl  = TextEditingController();
  final _leftCalfCtrl   = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _fatCtrl.dispose();
    _neckCtrl.dispose();
    _shouldersCtrl.dispose();
    _chestCtrl.dispose();
    _waistCtrl.dispose();
    _hipsCtrl.dispose();
    _rightArmCtrl.dispose();
    _leftArmCtrl.dispose();
    _rightForearmCtrl.dispose();
    _leftForearmCtrl.dispose();
    _rightThighCtrl.dispose();
    _leftThighCtrl.dispose();
    _rightCalfCtrl.dispose();
    _leftCalfCtrl.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController ctrl) =>
      double.tryParse(ctrl.text.trim().replaceAll(',', '.'));

  double? _parseCm(TextEditingController ctrl, bool useCm) {
    final v = _parse(ctrl);
    if (v == null) return null;
    return displayToCm(v, useCm);
  }

  double? _parseKg(TextEditingController ctrl, bool useKg) {
    final v = _parse(ctrl);
    if (v == null) return null;
    return useKg ? v : v / 2.20462;
  }

  Future<void> _save() async {
    final useKg = ref.read(useKgProvider);
    final useCm = ref.read(useCmProvider);

    final weight  = _parseKg(_weightCtrl, useKg);
    final fat     = _parse(_fatCtrl);
    final neck    = _parseCm(_neckCtrl, useCm);
    final shoulders = _parseCm(_shouldersCtrl, useCm);
    final chest   = _parseCm(_chestCtrl, useCm);
    final waist   = _parseCm(_waistCtrl, useCm);
    final hips    = _parseCm(_hipsCtrl, useCm);
    final rArm    = _parseCm(_rightArmCtrl, useCm);
    final lArm    = _parseCm(_leftArmCtrl, useCm);
    final rForearm = _parseCm(_rightForearmCtrl, useCm);
    final lForearm = _parseCm(_leftForearmCtrl, useCm);
    final rThigh  = _parseCm(_rightThighCtrl, useCm);
    final lThigh  = _parseCm(_leftThighCtrl, useCm);
    final rCalf   = _parseCm(_rightCalfCtrl, useCm);
    final lCalf   = _parseCm(_leftCalfCtrl, useCm);

    if ([weight, fat, neck, shoulders, chest, waist, hips,
         rArm, lArm, rForearm, lForearm, rThigh, lThigh, rCalf, lCalf]
        .every((v) => v == null)) {
      return;
    }

    setState(() => _saving = true);
    try {
      await BodyMetricsService.upsert(
        weightKg: weight,
        bodyFatPct: fat,
        neckCm: neck,
        shouldersCm: shoulders,
        chestCm: chest,
        waistCm: waist,
        hipsCm: hips,
        rightArmCm: rArm,
        leftArmCm: lArm,
        rightForearmCm: rForearm,
        leftForearmCm: lForearm,
        rightThighCm: rThigh,
        leftThighCm: lThigh,
        rightCalfCm: rCalf,
        leftCalfCm: lCalf,
      );
      if (mounted) {
        final filled = [weight, fat, neck, shoulders, chest, waist, hips,
            rArm, lArm, rForearm, lForearm, rThigh, lThigh, rCalf, lCalf]
            .where((v) => v != null)
            .length;
        EventLogger.bodyMetricsSaved(fieldsCount: filled);
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final useKg = ref.watch(useKgProvider);
    final useCm = ref.watch(useCmProvider);
    final wLabel = weightLabel(useKg);
    final lenLabel = lengthLabel(useCm);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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

                  // ── Основные ──
                  const _SectionHeader('Основные'),
                  _Field(
                    ctrl: _weightCtrl,
                    label: 'Вес',
                    suffix: wLabel,
                    hint: useKg ? '75.5' : '166.4',
                  ),
                  _Field(
                    ctrl: _fatCtrl,
                    label: '% жира',
                    suffix: '%',
                    hint: '18.5',
                  ),

                  // ── Туловище ──
                  const _SectionHeader('Туловище'),
                  _Field(ctrl: _neckCtrl,      label: 'Обхват шеи',   suffix: lenLabel, hint: useCm ? '37.5' : '14.8'),
                  _Field(ctrl: _shouldersCtrl, label: 'Обхват плеч',  suffix: lenLabel, hint: useCm ? '114.0' : '44.9'),
                  _Field(ctrl: _chestCtrl,     label: 'Обхват груди', suffix: lenLabel, hint: useCm ? '95.0' : '37.4'),
                  _Field(ctrl: _waistCtrl,     label: 'Обхват талии', suffix: lenLabel, hint: useCm ? '75.0' : '29.5'),
                  _Field(ctrl: _hipsCtrl,      label: 'Обхват таза',  suffix: lenLabel, hint: useCm ? '95.0' : '37.4'),

                  // ── Руки ──
                  const _SectionHeader('Руки'),
                  _Field(ctrl: _rightArmCtrl,    label: 'Обхват правого плеча',      suffix: lenLabel, hint: useCm ? '34.0' : '13.4'),
                  _Field(ctrl: _leftArmCtrl,     label: 'Обхват левого плеча',       suffix: lenLabel, hint: useCm ? '34.0' : '13.4'),
                  _Field(ctrl: _rightForearmCtrl, label: 'Обхват правого предплечья', suffix: lenLabel, hint: useCm ? '28.0' : '11.0'),
                  _Field(ctrl: _leftForearmCtrl,  label: 'Обхват левого предплечья',  suffix: lenLabel, hint: useCm ? '28.0' : '11.0'),

                  // ── Ноги ──
                  const _SectionHeader('Ноги'),
                  _Field(ctrl: _rightThighCtrl, label: 'Обхват правого бедра',  suffix: lenLabel, hint: useCm ? '56.0' : '22.0'),
                  _Field(ctrl: _leftThighCtrl,  label: 'Обхват левого бедра',   suffix: lenLabel, hint: useCm ? '56.0' : '22.0'),
                  _Field(ctrl: _rightCalfCtrl,  label: 'Обхват правой голени',  suffix: lenLabel, hint: useCm ? '36.0' : '14.2'),
                  _Field(ctrl: _leftCalfCtrl,   label: 'Обхват левой голени',   suffix: lenLabel, hint: useCm ? '36.0' : '14.2'),

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
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Single field ─────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String suffix;
  final String hint;

  const _Field({
    required this.ctrl,
    required this.label,
    required this.suffix,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffix,
          suffixStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ─── Helper chip ──────────────────────────────────────────────────────────────

class _ChipItem {
  final IconData icon;
  final String label;
  const _ChipItem(this.icon, this.label);
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Chip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.accent),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        ),
      ],
    );
  }
}
