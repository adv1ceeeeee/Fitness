import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/workout_service.dart';

// ─── Section data model ───────────────────────────────────────────────────────

class _SectionData {
  final TextEditingController nameController;
  final Set<int> selectedDays;

  _SectionData() : nameController = TextEditingController(), selectedDays = {};

  void dispose() => nameController.dispose();
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class CreateWorkoutScreen extends StatefulWidget {
  const CreateWorkoutScreen({super.key});

  @override
  State<CreateWorkoutScreen> createState() => _CreateWorkoutScreenState();
}

class _CreateWorkoutScreenState extends State<CreateWorkoutScreen> {
  final List<_SectionData> _sections = [_SectionData()];
  int _cycleWeeks = 8;
  bool _isLoading = false;
  String? _error;

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  void dispose() {
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  void _addSection() {
    if (_sections.length >= 7) return;
    setState(() {
      _sections.add(_SectionData());
      _error = null;
    });
  }

  void _removeSection(int index) {
    setState(() {
      _sections[index].dispose();
      _sections.removeAt(index);
      _error = null;
    });
  }

  void _toggleDay(int sectionIndex, int day) {
    setState(() {
      final days = _sections[sectionIndex].selectedDays;
      if (days.contains(day)) {
        days.remove(day);
      } else {
        days.add(day);
      }
      _error = null;
    });
  }

  /// Returns days already used in other sections (to disable them in this one).
  Set<int> _usedDaysExcept(int sectionIndex) {
    final used = <int>{};
    for (int i = 0; i < _sections.length; i++) {
      if (i != sectionIndex) used.addAll(_sections[i].selectedDays);
    }
    return used;
  }

  Future<void> _editCycleManually() async {
    final controller = TextEditingController(text: '$_cycleWeeks');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Длительность цикла'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            suffixText: 'нед.',
            hintText: 'Например: 20',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null && v >= 1) Navigator.pop(ctx, v);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) setState(() => _cycleWeeks = result);
  }

  Future<void> _createAndNext() async {
    // Validate each section
    for (int i = 0; i < _sections.length; i++) {
      final s = _sections[i];
      final label = _sections.length > 1 ? ' раздела ${i + 1}' : '';
      if (s.nameController.text.trim().isEmpty) {
        setState(() => _error = 'Введите название$label');
        return;
      }
      if (s.selectedDays.isEmpty) {
        setState(() => _error = 'Выберите дни тренировок$label');
        return;
      }
    }

    // Check for day overlaps across sections
    final seen = <int>{};
    for (final s in _sections) {
      for (final d in s.selectedDays) {
        if (!seen.add(d)) {
          setState(() => _error = 'Один день не может быть в двух разделах');
          return;
        }
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final workouts = await WorkoutService.createWorkoutGroup(
        _sections
            .map((s) => (
                  name: s.nameController.text.trim(),
                  days: s.selectedDays.toList()..sort(),
                  cycleWeeks: _cycleWeeks,
                ))
            .toList(),
      );

      if (mounted) {
        for (final w in workouts) {
          EventLogger.workoutCreated(workoutName: w.name);
        }
        final ids = workouts.map((w) => w.id).toList();
        context.pushReplacement(
          '/workouts/${ids.first}/exercises',
          extra: ids.length > 1
              ? {
                  'pendingIds': ids.skip(1).toList(),
                  'sectionIndex': 0,
                  'totalSections': ids.length,
                }
              : null,
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Что-то пошло не так. Попробуйте позже.';
        _isLoading = false;
      });
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMulti = _sections.length > 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая программа'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(context).padding.bottom + 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sections
            for (int i = 0; i < _sections.length; i++) ...[
              _buildSection(i, isMulti: isMulti),
              if (i < _sections.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: AppColors.surface, thickness: 1),
                ),
            ],

            // Shared cycle duration slider
            const SizedBox(height: 24),
            _buildCycleSlider(),

            // Add section button (hidden when all 7 days are covered)
            if (_sections.length < 7) ...[
              const SizedBox(height: 24),
              _buildAddSectionButton(),
            ],

            // Error
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createAndNext,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Далее'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(int index, {required bool isMulti}) {
    final section = _sections[index];
    final usedDays = _usedDaysExcept(index);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header (only in multi-section mode)
        if (isMulti) ...[
          Row(
            children: [
              Text(
                'Раздел ${index + 1}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (index > 0)
                GestureDetector(
                  onTap: () => _removeSection(index),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.close,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        const Text(
          'Название',
          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: section.nameController,
          decoration: InputDecoration(
            hintText: _sectionHint(index, isMulti),
          ),
        ),

        const SizedBox(height: 24),
        const Text(
          'Дни тренировок',
          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(7, (i) {
            final selected = section.selectedDays.contains(i);
            final disabled = usedDays.contains(i);
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 6 ? 8 : 0),
                child: Material(
                  color: selected
                      ? AppColors.accent
                      : disabled
                          ? AppColors.surface.withValues(alpha: 0.5)
                          : AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: disabled ? null : () => _toggleDay(index, i),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      child: Text(
                        _dayLabels[i],
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.black
                              : disabled
                                  ? AppColors.textSecondary
                                      .withValues(alpha: 0.35)
                                  : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  String _sectionHint(int index, bool isMulti) {
    if (!isMulti) return 'Например: Ноги, Грудь+бицепс';
    const hints = ['Например: Ноги', 'Например: Плечи', 'Например: Спина'];
    return index < hints.length ? hints[index] : 'Название раздела';
  }

  Widget _buildAddSectionButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _addSection,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, color: AppColors.accent, size: 20),
              SizedBox(width: 8),
              Text(
                'Добавить раздел',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCycleSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Длительность цикла',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
            if (_cycleWeeks > 16)
              Text(
                '$_cycleWeeks нед.',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onDoubleTap: _editCycleManually,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const sliderPadding = 24.0;
              const min = 4.0;
              const max = 16.0;
              final sliderVal = _cycleWeeks.clamp(4, 16).toDouble();
              final trackWidth =
                  constraints.maxWidth - sliderPadding * 2;
              final thumbX = sliderPadding +
                  (sliderVal - min) / (max - min) * trackWidth;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: AppColors.surface,
                        thumbColor: AppColors.accent,
                        overlayColor:
                            AppColors.accent.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        value: sliderVal,
                        min: min,
                        max: max,
                        divisions: 12,
                        onChanged: (v) =>
                            setState(() => _cycleWeeks = v.round()),
                      ),
                    ),
                  ),
                  Positioned(
                    left: thumbX - 24,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_cycleWeeks нед.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('4 нед.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              Text('16 нед.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Дважды нажмите для ручного ввода',
            style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }
}
