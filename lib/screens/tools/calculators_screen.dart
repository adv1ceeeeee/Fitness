import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/body_metrics_service.dart';

class CalculatorsScreen extends StatefulWidget {
  const CalculatorsScreen({super.key});

  @override
  State<CalculatorsScreen> createState() => _CalculatorsScreenState();
}

class _CalculatorsScreenState extends State<CalculatorsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Калькуляторы'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '1ПМ'),
            Tab(text: 'Блины'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _OneRepMaxTab(),
          _PlateCalculatorTab(),
        ],
      ),
    );
  }
}

// ─── 1ПМ (one-rep max) ────────────────────────────────────────────────────────

// Formula: (name, source, fn)
typedef _Orm = double Function(double w, int r);

class _OrmFormula {
  final String name;
  final String source;
  final _Orm fn;
  const _OrmFormula(this.name, this.source, this.fn);
}

// ── Formulas ──────────────────────────────────────────────────────────────────

double _epley(double w, int r) => r == 1 ? w : w * (1 + r / 30);
double _brzycki(double w, int r) => r >= 37 ? w : w * 36 / (37 - r);
double _lander(double w, int r) => (100 * w) / (101.3 - 2.67123 * r);
double _lombardi(double w, int r) => w * math.pow(r, 0.10).toDouble();
double _mayhew(double w, int r) =>
    (100 * w) / (52.2 + 41.9 * math.exp(-0.055 * r));
double _oconner(double w, int r) => w * (1 + 0.025 * r);
double _wathen(double w, int r) =>
    (100 * w) / (48.8 + 53.8 * math.exp(-0.075 * r));

// ── Per-exercise formula sets ─────────────────────────────────────────────────

const _benchFormulas = [
  _OrmFormula('Эпли', 'NSCA, 1985', _epley),
  _OrmFormula('Бжицки', 'NSCA, 1993', _brzycki),
  _OrmFormula('О\'Коннер', 'J. Strength Cond. Res., 1989', _oconner),
  _OrmFormula('Ландер', 'JSCR, 1985', _lander),
];

const _squatFormulas = [
  _OrmFormula('Эпли', 'NSCA, 1985', _epley),
  _OrmFormula('Бжицки', 'NSCA, 1993', _brzycki),
  _OrmFormula('Мэйхью', 'J. Sports Med., 1992', _mayhew),
  _OrmFormula('Ватен', 'NSCA J., 1994', _wathen),
];

const _deadliftFormulas = [
  _OrmFormula('Эпли', 'NSCA, 1985', _epley),
  _OrmFormula('Бжицки', 'NSCA, 1993', _brzycki),
  _OrmFormula('Ломбарди', 'NSCA J., 1989', _lombardi),
  _OrmFormula('Ландер', 'JSCR, 1985', _lander),
];

// ── Widget ────────────────────────────────────────────────────────────────────

class _Exercise {
  final String name;
  final List<_OrmFormula> formulas;
  const _Exercise(this.name, this.formulas);
}

const _exercises = [
  _Exercise('Жим штанги лёжа', _benchFormulas),
  _Exercise('Присед со штангой', _squatFormulas),
  _Exercise('Становая тяга', _deadliftFormulas),
];

class _OneRepMaxTab extends StatefulWidget {
  const _OneRepMaxTab();

  @override
  State<_OneRepMaxTab> createState() => _OneRepMaxTabState();
}

class _OneRepMaxTabState extends State<_OneRepMaxTab> {
  final _weightCtrl = TextEditingController();
  final _bodyWeightCtrl = TextEditingController();
  int _reps = 5;
  int _exerciseIndex = 0;
  double? _result;
  List<({String name, String source, double value})> _breakdown = [];

  @override
  void initState() {
    super.initState();
    _prefillBodyWeight();
  }

  Future<void> _prefillBodyWeight() async {
    final metrics = await BodyMetricsService.getLatest();
    final w = (metrics?['weight_kg'] as num?)?.toDouble();
    if (w != null && w > 0 && mounted) {
      setState(() => _bodyWeightCtrl.text =
          w == w.truncateToDouble() ? w.toInt().toString() : w.toString());
    }
  }

  void _calculate() {
    final w = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    if (w == null || w <= 0) {
      setState(() {
        _result = null;
        _breakdown = [];
      });
      return;
    }
    final formulas = _exercises[_exerciseIndex].formulas;
    final results = formulas
        .map((f) => (name: f.name, source: f.source, value: f.fn(w, _reps)))
        .toList();
    final avg = results.fold(0.0, (s, r) => s + r.value) / results.length;
    // Round to nearest 2.5 kg plate increment
    final rounded = (avg / 2.5).round() * 2.5;
    setState(() {
      _result = rounded;
      _breakdown = results;
    });
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _bodyWeightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const percentages = [100, 95, 90, 85, 80, 75, 70, 65, 60];

    return ListView(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 80),
      children: [
        // Exercise selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _exerciseIndex,
              isExpanded: true,
              dropdownColor: AppColors.card,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500),
              items: List.generate(
                _exercises.length,
                (i) => DropdownMenuItem(
                  value: i,
                  child: Text(_exercises[i].name),
                ),
              ),
              onChanged: (i) {
                if (i == null) return;
                setState(() => _exerciseIndex = i);
                _calculate();
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Введите вес и количество повторений, которые вы выполнили.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Вес (кг)',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _weightCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _calculate(),
                    decoration: const InputDecoration(hintText: '100'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Повторения: $_reps',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  Slider(
                    value: _reps.toDouble(),
                    min: 1,
                    max: 20,
                    divisions: 19,
                    activeColor: AppColors.accent,
                    inactiveColor: AppColors.surface,
                    onChanged: (v) {
                      setState(() => _reps = v.round());
                      _calculate();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Optional bodyweight field
        Row(
          children: [
            const Icon(Icons.person_outline,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            const Text('Вес тела (кг):',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(width: 10),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _bodyWeightCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '80',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_result != null) ...[
          // Average result
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3), width: 1),
            ),
            child: Column(
              children: [
                const Text('Расчётный 1ПМ (среднее)',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  '${_result! % 1 == 0 ? _result!.toInt() : _result!.toStringAsFixed(1)} кг',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Среднее по ${_breakdown.length} формулам',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
                Builder(builder: (context) {
                  final bw = double.tryParse(
                      _bodyWeightCtrl.text.replaceAll(',', '.'));
                  if (bw == null || bw <= 0) return const SizedBox.shrink();
                  final ratio = _result! / bw;
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '×${ratio.toStringAsFixed(2)} веса тела',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Per-formula breakdown
          const Text('По формулам',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const SizedBox(height: 8),
          ..._breakdown.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13)),
                            Text(r.source,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      Text(
                        '${r.value.toStringAsFixed(1)} кг',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 20),

          // Percentage table
          const Text('Проценты от 1ПМ',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const SizedBox(height: 8),
          ...percentages.map((pct) {
            final weight = _result! * pct / 100;
            final reps = _repsForPercent(pct);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        '$pct%',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${weight.toStringAsFixed(1)} кг',
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                    ),
                    Text(
                      reps,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  String _repsForPercent(int pct) {
    const map = {
      100: '1 повт.',
      95: '2 повт.',
      90: '3–4 повт.',
      85: '5–6 повт.',
      80: '7–8 повт.',
      75: '9–10 повт.',
      70: '11–12 повт.',
      65: '14–16 повт.',
      60: '18–20 повт.',
    };
    return map[pct] ?? '';
  }
}

// ─── Plate calculator ─────────────────────────────────────────────────────────

enum WarmupSetType { joint, general, specific, leadIn }

class WarmupSet {
  final double weight;
  final int reps;
  final WarmupSetType type;
  const WarmupSet(this.weight, this.reps, this.type);
}

// ── Pure top-level functions (extracted for testability) ──────────────────────

const plateWeightsKg = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
const plateWeightsLb = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];

/// Greedy plate calculation — largest plates first, one side of the bar.
List<double> calculatePlates(
    double target, double barWeight, List<double> availablePlates) {
  final perSide = (target - barWeight) / 2;
  if (perSide <= 0) return [];
  var remaining = perSide;
  final result = <double>[];
  for (final plate in availablePlates) {
    while (remaining >= plate - 0.001) {
      result.add(plate);
      remaining -= plate;
    }
  }
  return result;
}

/// Plate calculation with [primary] as dominant plate, remainder filled with
/// smaller plates. Returns plates for one side of the bar.
List<double> calculatePlatesWithPrimary(double target, double barWeight,
    double primary, List<double> availablePlates) {
  final perSide = (target - barWeight) / 2;
  if (perSide <= 0) return [];
  var remaining = perSide;
  final result = <double>[];
  while (remaining >= primary - 0.001) {
    result.add(primary);
    remaining -= primary;
  }
  for (final plate in availablePlates) {
    if (plate >= primary) continue;
    while (remaining >= plate - 0.001) {
      result.add(plate);
      remaining -= plate;
    }
  }
  return result;
}

/// Groups a flat list of plates into {plate: count}.
Map<double, int> groupPlates(List<double> plates) {
  final map = <double, int>{};
  for (final p in plates) {
    map[p] = (map[p] ?? 0) + 1;
  }
  return map;
}

/// Builds a progressive warmup scheme from bar to [target].
/// [barWeight] and [useKg] determine step rounding.
List<WarmupSet> buildWarmupSets(
    double target, double barWeight, bool useKg) {
  final step = useKg ? 2.5 : 5.0;
  double snap(double w) => (w / step).round() * step;

  final sets = <WarmupSet>[
    const WarmupSet(0, 0, WarmupSetType.joint),
    WarmupSet(barWeight, 10, WarmupSetType.general),
  ];

  final ratio = target / barWeight;
  if (ratio < 1.5) return sets;

  final List<double> pcts;
  final List<int> reps;
  final List<WarmupSetType> types;

  if (ratio < 2.5) {
    pcts  = [0.60];
    reps  = [5];
    types = [WarmupSetType.leadIn];
  } else if (ratio < 4.0) {
    pcts  = [0.45, 0.75];
    reps  = [5, 3];
    types = [WarmupSetType.specific, WarmupSetType.leadIn];
  } else if (ratio < 6.0) {
    pcts  = [0.40, 0.60, 0.80];
    reps  = [8, 5, 2];
    types = [WarmupSetType.specific, WarmupSetType.specific, WarmupSetType.leadIn];
  } else {
    pcts  = [0.35, 0.52, 0.67, 0.83];
    reps  = [8, 5, 3, 1];
    types = [WarmupSetType.specific, WarmupSetType.specific,
             WarmupSetType.specific, WarmupSetType.leadIn];
  }

  for (var i = 0; i < pcts.length; i++) {
    final w = snap(target * pcts[i]).clamp(barWeight, target - step);
    if (sets.any((s) => (s.weight - w).abs() < 0.01)) continue;
    sets.add(WarmupSet(w, reps[i], types[i]));
  }

  return sets;
}

class _PlateCalculatorTab extends StatefulWidget {
  const _PlateCalculatorTab();

  @override
  State<_PlateCalculatorTab> createState() => _PlateCalculatorTabState();
}

class _PlateCalculatorTabState extends State<_PlateCalculatorTab> {
  final _targetCtrl = TextEditingController();
  double _barWeight = 20;
  bool _useKg = true;

  static const _plateWeightsKg = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
  static const _plateWeightsLb = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];
  static const _barWeightsKg = [20.0, 15.0, 10.0, 7.5];
  static const _barWeightsLb = [45.0, 35.0, 25.0, 15.0];

  List<double> get _plates =>
      _useKg ? _plateWeightsKg : _plateWeightsLb;
  List<double> get _bars => _useKg ? _barWeightsKg : _barWeightsLb;
  String get _unit => _useKg ? 'кг' : 'lb';

  List<WarmupSet> _buildWarmup(double target) =>
      buildWarmupSets(target, _barWeight, _useKg);

  List<double> _calculate(double target) =>
      calculatePlates(target, _barWeight, _plates);

  List<double> _calculateWithPrimary(double target, double primary) =>
      calculatePlatesWithPrimary(target, _barWeight, primary, _plates);

  List<double> get _primaryPlates =>
      _useKg ? [25.0, 20.0, 15.0, 10.0] : [45.0, 35.0, 25.0, 10.0];

  @override
  void dispose() {
    _targetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetText = _targetCtrl.text.replaceAll(',', '.');
    final target = double.tryParse(targetText);
    final plates = target != null && target > _barWeight
        ? _calculate(target)
        : <double>[];
    final loadedWeight =
        target != null ? _barWeight + plates.fold(0.0, (s, p) => s + p) * 2 : 0.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 80),
      children: [
        const Text(
          'Введите целевой вес на штанге, чтобы узнать какие блины нужно повесить с каждой стороны.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 20),

        // Unit toggle
        Row(
          children: [
            const Text('Единицы:',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(width: 12),
            _ToggleChip(
              label: 'кг',
              selected: _useKg,
              onTap: () => setState(() {
                _useKg = true;
                _barWeight = 20;
              }),
            ),
            const SizedBox(width: 8),
            _ToggleChip(
              label: 'lb',
              selected: !_useKg,
              onTap: () => setState(() {
                _useKg = false;
                _barWeight = 45;
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Bar weight
        Row(
          children: [
            const Text('Гриф:',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(width: 12),
            ..._bars.map((b) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ToggleChip(
                    label: '${b.toStringAsFixed(b == b.truncate() ? 0 : 1)} $_unit',
                    selected: _barWeight == b,
                    onTap: () => setState(() => _barWeight = b),
                  ),
                )),
          ],
        ),
        const SizedBox(height: 20),

        // Target weight input
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Целевой вес ($_unit)',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: _targetCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration:
                  InputDecoration(hintText: _useKg ? '100' : '225'),
            ),
          ],
        ),

        if (target != null) ...[
          const SizedBox(height: 24),
          if (target <= _barWeight)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Целевой вес меньше или равен весу грифа ($_barWeight $_unit). Блины не нужны.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      const Text('Фактический вес',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '${loadedWeight.toStringAsFixed(loadedWeight == loadedWeight.truncate() ? 0 : 2)} $_unit',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Блинов на сторону',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '${plates.length}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('На каждую сторону:',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            const SizedBox(height: 8),
            if (plates.isEmpty)
              const Text('Без блинов',
                  style: TextStyle(color: AppColors.textSecondary))
            else
              Column(
                children: _primaryPlates.map((primary) {
                  final variant = _calculateWithPrimary(target, primary);
                  final hasPrimary =
                      variant.any((p) => (p - primary).abs() < 0.001);
                  if (!hasPrimary) return const SizedBox.shrink();
                  final grouped = _groupPlates(variant);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 52,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: _plateColor(primary)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${primary.toStringAsFixed(primary == primary.truncate() ? 0 : 1)} $_unit',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _plateColor(primary),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: grouped.entries.map((e) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _plateColor(e.key),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${e.value}×${e.key.toStringAsFixed(e.key == e.key.truncate() ? 0 : 2)} $_unit',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

            // ── Warmup scheme ────────────────────────────────────────────
            const SizedBox(height: 24),
            const Text('Схема разминки',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              'Прогрессивная нагрузка до рабочего веса — по стандарту NSCA/IPF',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  children: [
                    ..._buildWarmup(target).asMap().entries.map((e) {
                      final i = e.key;
                      final s = e.value;
                      const jointColor = Color(0xFF30D158);
                      final (color, label) = switch (s.type) {
                        WarmupSetType.joint    => (jointColor, 'Суставная разминка'),
                        WarmupSetType.general  => (const Color(0xFF636366), 'Общая разминка'),
                        WarmupSetType.specific => (const Color(0xFF007AFF), 'Специфическая'),
                        WarmupSetType.leadIn   => (const Color(0xFFFF9500), 'Подводящий'),
                      };
                      if (s.type == WarmupSetType.joint) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 26, height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        color: jointColor, fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text('Резинки / гантели / гриф без блинов',
                                    style: TextStyle(
                                        color: AppColors.textSecondary, fontSize: 13)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(label,
                                    style: const TextStyle(
                                        color: jointColor, fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        );
                      }
                      final wStr = s.weight.toStringAsFixed(
                          s.weight == s.weight.truncate() ? 0 : 1);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 26, height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      color: color, fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 80,
                              child: Text('$wStr $_unit',
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                            ),
                            Expanded(
                              child: Text('× ${s.reps} повт.',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary, fontSize: 13)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(label,
                                  style: TextStyle(
                                      color: color, fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      );
                    }),
                    // Working set indicator
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 26, height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.fitness_center,
                                size: 14, color: AppColors.accent),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 80,
                            child: Text(
                              '${target.toStringAsFixed(target == target.truncate() ? 0 : 1)} $_unit',
                              style: const TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14),
                            ),
                          ),
                          const Expanded(child: SizedBox()),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Рабочий подход',
                                style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Map<double, int> _groupPlates(List<double> plates) => groupPlates(plates);

  Color _plateColor(double weight) {
    if (_useKg) {
      if (weight >= 25) return const Color(0xFFFF3B30);
      if (weight >= 20) return const Color(0xFF007AFF);
      if (weight >= 15) return const Color(0xFFFFCC00);
      if (weight >= 10) return const Color(0xFF34C759);
      if (weight >= 5) return const Color(0xFFFF9500);
      return const Color(0xFF636366);
    } else {
      if (weight >= 45) return const Color(0xFFFF3B30);
      if (weight >= 35) return const Color(0xFF007AFF);
      if (weight >= 25) return const Color(0xFFFFCC00);
      if (weight >= 10) return const Color(0xFF34C759);
      return const Color(0xFF636366);
    }
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.2)
              : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accent : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
