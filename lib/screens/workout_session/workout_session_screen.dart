import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/services/training_service.dart';

class WorkoutSessionScreen extends StatefulWidget {
  final String sessionId;

  const WorkoutSessionScreen({super.key, required this.sessionId});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  List<WorkoutExercise> _exercises = [];
  int _currentExerciseIndex = 0;
  int _currentSet = 1;
  double _weight = 0;
  int _reps = 8;
  bool _loading = true;
  bool _resting = false;
  int _restSeconds = 90;
  int _initialRestSeconds = 90;
  Timer? _restTimer;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSession() async {
    // Get workout from session, then exercises
    final sessionRes = await Supabase.instance.client
        .from('training_sessions')
        .select('workout_id')
        .eq('id', widget.sessionId)
        .single();

    final workoutId = sessionRes['workout_id'] as String;
    final ex = await TrainingService.getWorkoutExercisesForToday(workoutId);

    if (mounted) {
      setState(() {
        _exercises = ex;
        _loading = false;
        if (ex.isNotEmpty) {
          _restSeconds = ex.first.restSeconds;
        }
      });
    }
  }

  WorkoutExercise? get _currentExercise {
    if (_currentExerciseIndex >= _exercises.length) return null;
    return _exercises[_currentExerciseIndex];
  }

  bool get _isLastSet {
    if (_currentExercise == null) return true;
    return _currentSet >= _currentExercise!.sets;
  }

  bool get _isLastExercise {
    return _isLastSet && _currentExerciseIndex >= _exercises.length - 1;
  }

  Future<void> _completeSet() async {
    final we = _currentExercise!;
    await TrainingService.saveSet(
      widget.sessionId,
      we.id,
      _currentSet,
      weight: _weight > 0 ? _weight : null,
      reps: _reps,
    );

    if (_isLastExercise && _isLastSet) {
      await TrainingService.completeSession(widget.sessionId);
      if (mounted) _showCompletionDialog();
      return;
    }

    if (_isLastSet) {
      final nextRest = _currentExerciseIndex + 1 < _exercises.length
          ? _exercises[_currentExerciseIndex + 1].restSeconds
          : 90;
      setState(() {
        _currentExerciseIndex++;
        _currentSet = 1;
        _resting = true;
        _restSeconds = nextRest;
        _initialRestSeconds = nextRest;
      });
      _startRestTimer();
    } else {
      setState(() {
        _currentSet++;
        _resting = true;
        _restSeconds = we.restSeconds;
        _initialRestSeconds = we.restSeconds;
      });
      _startRestTimer();
    }
  }

  void _startRestTimer() {
    _restTimer?.cancel();
    var remaining = _restSeconds;
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      remaining--;
      if (mounted) {
        setState(() => _restSeconds = remaining);
        if (remaining <= 0) {
          t.cancel();
          setState(() => _resting = false);
        }
      }
    });
  }

  void _skipRest() {
    _restTimer?.cancel();
    setState(() => _resting = false);
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Тренировка завершена!',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🎉 Отличная работа!',
              style: TextStyle(
                fontSize: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/home');
            },
            child: Text('На главную', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_exercises.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Тренировка')),
        body: const Center(child: Text('Нет упражнений')),
      );
    }

    if (_resting) {
      return _RestScreen(
        initialSeconds: _initialRestSeconds,
        seconds: _restSeconds,
        onSkip: _skipRest,
        onNext: _skipRest,
      );
    }

    final we = _currentExercise!;
    final ex = we.exercise;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_currentExerciseIndex + 1}/${_exercises.length}'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ex?.name ?? '?',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Подход $_currentSet из ${we.sets}',
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              _WeightRepsInput(
                weight: _weight,
                reps: _reps,
                onWeightChanged: (v) => setState(() => _weight = v),
                onRepsChanged: (v) => setState(() => _reps = v),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: _completeSet,
                  icon: const Icon(Icons.check, size: 28),
                  label: const Text('Выполнил подход'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestScreen extends StatelessWidget {
  final int initialSeconds;
  final int seconds;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  const _RestScreen({
    required this.initialSeconds,
    required this.seconds,
    required this.onSkip,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final timeStr = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final progress = initialSeconds > 0
        ? 1 - (seconds / initialSeconds)
        : 1.0;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 8,
                      color: AppColors.accent,
                    ),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Отдых',
                style: TextStyle(
                  fontSize: 24,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onSkip,
                child: Text(
                  'Пропустить отдых',
                  style: TextStyle(color: AppColors.accent, fontSize: 18),
                ),
              ),
              const SizedBox(height: 16),
              if (seconds <= 0)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: onNext,
                    child: const Text('Следующий подход'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeightRepsInput extends StatelessWidget {
  final double weight;
  final int reps;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int> onRepsChanged;

  const _WeightRepsInput({
    required this.weight,
    required this.reps,
    required this.onWeightChanged,
    required this.onRepsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Вес (кг)', style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _BigButton(
              label: '-2.5',
              onTap: () => onWeightChanged((weight - 2.5).clamp(0, 999)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                width: 80,
                child: TextFormField(
                  key: ValueKey('weight_$weight'),
                  initialValue: weight > 0 ? weight.toString() : '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28),
                  decoration: const InputDecoration(
                    hintText: '0',
                  ),
                  onChanged: (v) {
                    final w = double.tryParse(v.replaceAll(',', '.'));
                    if (w != null) onWeightChanged(w);
                  },
                ),
              ),
            ),
            _BigButton(
              label: '+2.5',
              onTap: () => onWeightChanged(weight + 2.5),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text('Повторения', style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _BigButton(
              label: '-1',
              onTap: () => onRepsChanged((reps - 1).clamp(1, 999)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '$reps',
                style: const TextStyle(fontSize: 32),
              ),
            ),
            _BigButton(
              label: '+1',
              onTap: () => onRepsChanged(reps + 1),
            ),
          ],
        ),
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BigButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}
