import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/workout_service.dart';

// ─── Section data model ───────────────────────────────────────────────────────

class _SectionData {
  final TextEditingController nameController;
  final Set<int> selectedDays; // workout days
  final Set<int> restDays;     // rest days

  _SectionData()
      : nameController = TextEditingController(),
        selectedDays = {},
        restDays = {};

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

  /// Cycles a day through: unselected → workout → rest → unselected.
  void _toggleDay(int sectionIndex, int day) {
    setState(() {
      final s = _sections[sectionIndex];
      if (s.restDays.contains(day)) {
        s.restDays.remove(day);
      } else if (s.selectedDays.contains(day)) {
        s.selectedDays.remove(day);
        s.restDays.add(day);
      } else {
        s.selectedDays.add(day);
      }
      _error = null;
    });
  }

  /// Moves all currently selected workout days to rest days for a section.
  void _markSelectedAsRest(int sectionIndex) {
    setState(() {
      final s = _sections[sectionIndex];
      s.restDays.addAll(s.selectedDays);
      s.selectedDays.clear();
      _error = null;
    });
  }

  /// Returns days already used in other sections (workout OR rest).
  Set<int> _usedDaysExcept(int sectionIndex) {
    final used = <int>{};
    for (int i = 0; i < _sections.length; i++) {
      if (i != sectionIndex) {
        used.addAll(_sections[i].selectedDays);
        used.addAll(_sections[i].restDays);
      }
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
            final isWorkout = section.selectedDays.contains(i);
            final isRest = section.restDays.contains(i);
            final disabled = usedDays.contains(i);

            Color bgColor;
            Color textColor;
            if (isWorkout) {
              bgColor = AppColors.accent;
              textColor = Colors.white;
            } else if (isRest) {
              bgColor = const Color(0xFF2A1F0A);
              textColor = const Color(0xFFD4A454);
            } else if (disabled) {
              bgColor = AppColors.surface.withValues(alpha: 0.5);
              textColor = AppColors.textSecondary.withValues(alpha: 0.35);
            } else {
              bgColor = AppColors.card;
              textColor = AppColors.textPrimary;
            }

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 6 ? 8 : 0),
                child: Material(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: disabled ? null : () => _toggleDay(index, i),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _dayLabels[i],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: textColor,
                            ),
                          ),
                          if (isRest) ...[
                            const SizedBox(height: 2),
                            Icon(Icons.hotel_rounded,
                                size: 10, color: textColor),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        // "Mark as rest day" button
        GestureDetector(
          onTap: section.selectedDays.isEmpty
              ? null
              : () => _markSelectedAsRest(index),
          child: Opacity(
            opacity: section.selectedDays.isEmpty ? 0.4 : 1.0,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1F0A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFD4A454).withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hotel_rounded,
                      color: Color(0xFFD4A454), size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Отметить выбранные как день отдыха',
                    style: TextStyle(
                      color: Color(0xFFD4A454),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
