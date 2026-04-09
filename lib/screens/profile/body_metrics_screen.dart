import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/providers/settings_provider.dart';
import 'package:sportwai/screens/profile/body_model_widget.dart';
import 'package:sportwai/services/body_metrics_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/gamification_service.dart';
import 'package:sportwai/services/profile_service.dart';

class BodyMetricsScreen extends ConsumerStatefulWidget {
  const BodyMetricsScreen({super.key});

  @override
  ConsumerState<BodyMetricsScreen> createState() => _BodyMetricsScreenState();
}

class _BodyMetricsScreenState extends ConsumerState<BodyMetricsScreen> {
  List<Map<String, dynamic>> _history = [];
  double? _profileHeight;
  bool _loading = true;

  // Which history row is currently shown in the silhouette (null = latest)
  Map<String, dynamic>? _displayedRow;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      BodyMetricsService.getHistory(),
      ProfileService.getProfile(),
    ]);
    if (mounted) {
      setState(() {
        _history = results[0] as List<Map<String, dynamic>>;
        _profileHeight = (results[1] as dynamic)?.heightCm as double?;
        // Keep displayed row in sync — if it was the latest, update to new latest
        _displayedRow = _history.isNotEmpty ? _history.last : null;
        _loading = false;
      });
    }
  }

  // ─── Open "add new" sheet ──────────────────────────────────────────────────

  void _openAddSheet() {
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

  // ─── Open "edit existing" sheet ────────────────────────────────────────────

  void _openEditSheet(Map<String, dynamic> row) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LogMetricsSheet(
        existingRow: row,
        onSaved: () {
          setState(() => _loading = true);
          _load();
        },
      ),
    );
  }

  // ─── Open "choose date to edit" sheet ─────────────────────────────────────

  void _openSelectDateSheet() {
    if (_history.isEmpty) return;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SelectDateSheet(
        history: _history,
        onSelect: (row) {
          Navigator.of(ctx).pop();
          _openEditSheet(row);
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
          // Edit existing measurement
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              onPressed: _history.isEmpty ? null : _openSelectDateSheet,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Изменить'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
          ),
          // Add new measurement
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _openAddSheet,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Новый замер'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
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
                  // 3D body model (falls back to SVG if model not added yet)
                  Body3DWidget(measurements: _displayedRow),

                  // Label when viewing a past date
                  if (_displayedRow != null &&
                      _displayedRow != _history.lastOrNull)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.history,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Замер от ${_formatDate(_displayedRow!['date'] as String)}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(
                                () => _displayedRow = _history.lastOrNull),
                            child: const Text('← последний',
                                style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 12,
                                    decoration: TextDecoration.underline)),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  const Text(
                    'История',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_profileHeight != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.height_rounded,
                              size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            'Рост: ${_profileHeight!.toInt()} см',
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 14),
                          ),
                          const Spacer(),
                          const Text('из профиля',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],

                  if (_history.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16)),
                      child: const Center(
                          child: Text(
                              'Нет записей.\nНажмите + чтобы добавить первую.',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: AppColors.textSecondary))),
                    )
                  else
                    ..._history.reversed.take(30).map((row) {
                      final date = row['date'] as String? ?? '';
                      final isSelected = _displayedRow == row;

                      final chips = <_ChipItem>[
                        if (row['weight_kg'] != null)
                          _ChipItem(Icons.monitor_weight_outlined,
                              '${_fmtKg(row['weight_kg'], useKg)} $wLabel'),
                        if (row['body_fat_pct'] != null)
                          _ChipItem(Icons.percent,
                              '${(row['body_fat_pct'] as num).toStringAsFixed(1)}% жира'),
                        if (row['neck_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Шея: ${_fmtCm(row['neck_cm'], useCm)} $lenLabel'),
                        if (row['shoulders_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Плечи: ${_fmtCm(row['shoulders_cm'], useCm)} $lenLabel'),
                        if (row['chest_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Грудь: ${_fmtCm(row['chest_cm'], useCm)} $lenLabel'),
                        if (row['waist_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Талия: ${_fmtCm(row['waist_cm'], useCm)} $lenLabel'),
                        if (row['hips_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Таз: ${_fmtCm(row['hips_cm'], useCm)} $lenLabel'),
                        if (row['right_arm_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Пр.плечо: ${_fmtCm(row['right_arm_cm'], useCm)} $lenLabel'),
                        if (row['left_arm_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Лев.плечо: ${_fmtCm(row['left_arm_cm'], useCm)} $lenLabel'),
                        if (row['right_forearm_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Пр.предпл.: ${_fmtCm(row['right_forearm_cm'], useCm)} $lenLabel'),
                        if (row['left_forearm_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Лев.предпл.: ${_fmtCm(row['left_forearm_cm'], useCm)} $lenLabel'),
                        if (row['right_thigh_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Пр.бедро: ${_fmtCm(row['right_thigh_cm'], useCm)} $lenLabel'),
                        if (row['left_thigh_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Лев.бедро: ${_fmtCm(row['left_thigh_cm'], useCm)} $lenLabel'),
                        if (row['right_calf_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Пр.голень: ${_fmtCm(row['right_calf_cm'], useCm)} $lenLabel'),
                        if (row['left_calf_cm'] != null)
                          _ChipItem(Icons.straighten,
                              'Лев.голень: ${_fmtCm(row['left_calf_cm'], useCm)} $lenLabel'),
                      ];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          // Tap card → view this date's measurements in silhouette
                          onTap: () => setState(() => _displayedRow = row),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(12),
                              border: isSelected
                                  ? Border.all(
                                      color: AppColors.accent, width: 1.5)
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _formatDate(date),
                                      style: TextStyle(
                                        color: isSelected
                                            ? AppColors.accent
                                            : AppColors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const Spacer(),
                                    // Edit button for this entry
                                    GestureDetector(
                                      onTap: () => _openEditSheet(row),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.edit_outlined,
                                          size: 14,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  children: chips
                                      .map((c) =>
                                          _Chip(label: c.label, icon: c.icon))
                                      .toList(),
                                ),
                              ],
                            ),
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
}

// ─── Select date sheet (for editing) ──────────────────────────────────────────

class _SelectDateSheet extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final void Function(Map<String, dynamic> row) onSelect;

  const _SelectDateSheet({required this.history, required this.onSelect});

  String _fmt(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length < 3) return dateStr;
    return '${parts[2]}.${parts[1]}.${parts[0]}';
  }

  String _summary(Map<String, dynamic> row) {
    final parts = <String>[];
    if (row['weight_kg'] != null) {
      parts.add('${(row['weight_kg'] as num).toStringAsFixed(1)} кг');
    }
    if (row['waist_cm'] != null) {
      parts.add('талия ${(row['waist_cm'] as num).toStringAsFixed(0)} см');
    }
    if (row['chest_cm'] != null) {
      parts.add('грудь ${(row['chest_cm'] as num).toStringAsFixed(0)} см');
    }
    return parts.isEmpty ? 'нет ключевых данных' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (_, scrollCtrl) => Column(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                const Text('Выберите замер для изменения',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: history.length,
              itemBuilder: (ctx, i) {
                // Newest first
                final row = history[history.length - 1 - i];
                final date = row['date'] as String? ?? '';
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  tileColor: AppColors.surface,
                  title: Text(_fmt(date),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(_summary(row),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.textSecondary),
                  onTap: () => onSelect(row),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Log / Edit metrics sheet ──────────────────────────────────────────────────

class _LogMetricsSheet extends ConsumerStatefulWidget {
  final VoidCallback onSaved;
  final Map<String, dynamic>? existingRow; // non-null when editing

  const _LogMetricsSheet({required this.onSaved, this.existingRow});

  @override
  ConsumerState<_LogMetricsSheet> createState() => _LogMetricsSheetState();
}

class _LogMetricsSheetState extends ConsumerState<_LogMetricsSheet> {
  late final TextEditingController _heightCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _neckCtrl;
  late final TextEditingController _shouldersCtrl;
  late final TextEditingController _chestCtrl;
  late final TextEditingController _waistCtrl;
  late final TextEditingController _hipsCtrl;
  late final TextEditingController _rightArmCtrl;
  late final TextEditingController _leftArmCtrl;
  late final TextEditingController _rightForearmCtrl;
  late final TextEditingController _leftForearmCtrl;
  late final TextEditingController _rightThighCtrl;
  late final TextEditingController _leftThighCtrl;
  late final TextEditingController _rightCalfCtrl;
  late final TextEditingController _leftCalfCtrl;

  bool _saving = false;

  bool get _isEditing => widget.existingRow != null;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRow;
    String s(String key) =>
        r != null && r[key] != null ? (r[key] as num).toStringAsFixed(1) : '';

    _heightCtrl = TextEditingController();
    _weightCtrl = TextEditingController(text: s('weight_kg'));
    _fatCtrl = TextEditingController(text: s('body_fat_pct'));
    _neckCtrl = TextEditingController(text: s('neck_cm'));
    _shouldersCtrl = TextEditingController(text: s('shoulders_cm'));
    _chestCtrl = TextEditingController(text: s('chest_cm'));
    _waistCtrl = TextEditingController(text: s('waist_cm'));
    _hipsCtrl = TextEditingController(text: s('hips_cm'));
    _rightArmCtrl = TextEditingController(text: s('right_arm_cm'));
    _leftArmCtrl = TextEditingController(text: s('left_arm_cm'));
    _rightForearmCtrl = TextEditingController(text: s('right_forearm_cm'));
    _leftForearmCtrl = TextEditingController(text: s('left_forearm_cm'));
    _rightThighCtrl = TextEditingController(text: s('right_thigh_cm'));
    _leftThighCtrl = TextEditingController(text: s('left_thigh_cm'));
    _rightCalfCtrl = TextEditingController(text: s('right_calf_cm'));
    _leftCalfCtrl = TextEditingController(text: s('left_calf_cm'));
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
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

    final weight = _parseKg(_weightCtrl, useKg);
    final fat = _parse(_fatCtrl);
    final neck = _parseCm(_neckCtrl, useCm);
    final shoulders = _parseCm(_shouldersCtrl, useCm);
    final chest = _parseCm(_chestCtrl, useCm);
    final waist = _parseCm(_waistCtrl, useCm);
    final hips = _parseCm(_hipsCtrl, useCm);
    final rArm = _parseCm(_rightArmCtrl, useCm);
    final lArm = _parseCm(_leftArmCtrl, useCm);
    final rForearm = _parseCm(_rightForearmCtrl, useCm);
    final lForearm = _parseCm(_leftForearmCtrl, useCm);
    final rThigh = _parseCm(_rightThighCtrl, useCm);
    final lThigh = _parseCm(_leftThighCtrl, useCm);
    final rCalf = _parseCm(_rightCalfCtrl, useCm);
    final lCalf = _parseCm(_leftCalfCtrl, useCm);

    final height = _parse(_heightCtrl);
    if (height != null) {
      await ProfileService.updateProfile({'height_cm': height});
    }

    if ([
      weight, fat, neck, shoulders, chest, waist, hips,
      rArm, lArm, rForearm, lForearm, rThigh, lThigh, rCalf, lCalf,
    ].every((v) => v == null)) {
      return;
    }

    setState(() => _saving = true);
    try {
      // When editing, pass the existing date so upsert updates the right record
      DateTime? editDate;
      if (_isEditing) {
        final dateStr = widget.existingRow!['date'] as String?;
        if (dateStr != null) editDate = DateTime.tryParse(dateStr);
      }

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
        date: editDate,
      );

      if (mounted) {
        if (!_isEditing) {
          final filled = [
            weight, fat, neck, shoulders, chest, waist, hips,
            rArm, lArm, rForearm, lForearm, rThigh, lThigh, rCalf, lCalf,
          ].where((v) => v != null).length;
          EventLogger.bodyMetricsSaved(fieldsCount: filled);
          GamificationService.award('body_measurement');
        }
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

    String? editDateLabel;
    if (_isEditing) {
      final d = widget.existingRow!['date'] as String? ?? '';
      final parts = d.split('-');
      if (parts.length == 3) editDateLabel = '${parts[2]}.${parts[1]}.${parts[0]}';
    }

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
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditing ? 'Изменить замер' : 'Добавить замер',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (editDateLabel != null)
                            Text(
                              editDateLabel,
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Основные ──
                  const _SectionHeader('Основные'),
                  if (!_isEditing)
                    _Field(ctrl: _heightCtrl, label: 'Рост', suffix: 'см', hint: '175'),
                  _Field(ctrl: _weightCtrl, label: 'Вес', suffix: wLabel, hint: useKg ? '75.5' : '166.4'),
                  _Field(ctrl: _fatCtrl, label: '% жира', suffix: '%', hint: '18.5'),

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
                          : Text(_isEditing ? 'Сохранить изменения' : 'Сохранить'),
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

// ─── Section header ────────────────────────────────────────────────────────────

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

// ─── Single field ──────────────────────────────────────────────────────────────

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
