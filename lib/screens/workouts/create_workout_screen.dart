import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/workout_service.dart';

class CreateWorkoutScreen extends StatefulWidget {
  const CreateWorkoutScreen({super.key});

  @override
  State<CreateWorkoutScreen> createState() => _CreateWorkoutScreenState();
}

class _CreateWorkoutScreenState extends State<CreateWorkoutScreen> {
  final _nameController = TextEditingController();
  final Set<int> _selectedDays = {};
  int _cycleWeeks = 8;
  bool _isLoading = false;
  String? _error;

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
  }

  Future<void> _createAndNext() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите название программы');
      return;
    }
    if (_selectedDays.isEmpty) {
      setState(() => _error = 'Выберите дни тренировок');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final workout = await WorkoutService.createWorkout(
        name,
        _selectedDays.toList()..sort(),
        cycleWeeks: _cycleWeeks,
      );
      if (mounted) {
        context.pushReplacement('/workouts/${workout.id}/exercises');
      }
    } catch (e) {
      setState(() {
        _error = 'Что-то пошло не так. Попробуйте позже.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая программа'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Название программы',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'Например: Ноги, Грудь+бицепс',
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
                final selected = _selectedDays.contains(i);
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 6 ? 8 : 0),
                    child: Material(
                      color: selected ? AppColors.accent : AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => _toggleDay(i),
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
            const SizedBox(height: 24),
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
                  final trackWidth = constraints.maxWidth - sliderPadding * 2;
                  final thumbX = sliderPadding + (sliderVal - min) / (max - min) * trackWidth;
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
                            overlayColor: AppColors.accent.withValues(alpha: 0.12),
                          ),
                          child: Slider(
                            value: sliderVal,
                            min: min,
                            max: max,
                            divisions: 12,
                            onChanged: (v) => setState(() => _cycleWeeks = v.round()),
                          ),
                        ),
                      ),
                      Positioned(
                        left: thumbX - 24,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('4 нед.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text('16 нед.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Дважды нажмите для ручного ввода',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary.withValues(alpha: 0.6)),
              ),
            ),
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
}
