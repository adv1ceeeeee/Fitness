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
  static const _cycleOptions = [4, 6, 8, 12, 16];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
            const Text(
              'Длительность цикла',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _cycleOptions.map((w) {
                final sel = _cycleWeeks == w;
                return ChoiceChip(
                  label: Text('$w нед.'),
                  selected: sel,
                  onSelected: (_) => setState(() => _cycleWeeks = w),
                  selectedColor: AppColors.accent,
                  checkmarkColor: Colors.black,
                  labelStyle: TextStyle(
                    color: sel ? Colors.black : AppColors.textPrimary,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                  ),
                );
              }).toList(),
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
