import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/services/training_service.dart';

// ─── Локальная модель одного подхода ────────────────────────────────────────

class _SetData {
  int reps;
  int? rpe;
  bool completed;

  _SetData({required this.reps, this.rpe, this.completed = false});

  _SetData copyWith({int? reps, int? rpe, bool? completed}) => _SetData(
        reps: reps ?? this.reps,
        rpe: rpe ?? this.rpe,
        completed: completed ?? this.completed,
      );
}

// ─── Экран тренировки ────────────────────────────────────────────────────────

class WorkoutSessionScreen extends StatefulWidget {
  final String sessionId;

  const WorkoutSessionScreen({super.key, required this.sessionId});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  List<WorkoutExercise> _exercises = [];
  int _currentExerciseIndex = 0;
  bool _loading = true;
  bool _resting = false;
  int _restSeconds = 90;
  int _initialRestSeconds = 90;
  Timer? _restTimer;
  bool _goToNextAfterRest = false;

  double _weight = 0;
  List<_SetData> _sets = [];

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
        if (ex.isNotEmpty) _initExercise(ex[0]);
      });
    }
  }

  void _initExercise(WorkoutExercise we) {
    final defaultReps = _parseDefaultReps(we.repsRange);
    _weight = 0;
    _sets = List.generate(we.sets, (_) => _SetData(reps: defaultReps));
  }

  int _parseDefaultReps(String range) {
    final first = range.split('-')[0].trim();
    return int.tryParse(first) ?? 8;
  }

  WorkoutExercise? get _currentExercise {
    if (_currentExerciseIndex >= _exercises.length) return null;
    return _exercises[_currentExerciseIndex];
  }

  int get _firstIncompleteIndex => _sets.indexWhere((s) => !s.completed);

  bool get _allSetsCompleted => _sets.every((s) => s.completed);

  Future<void> _completeSet(int index) async {
    final we = _currentExercise!;
    final setData = _sets[index];

    await TrainingService.saveSet(
      widget.sessionId,
      we.id,
      index + 1,
      weight: _weight > 0 ? _weight : null,
      reps: setData.reps,
      rpe: setData.rpe,
    );

    setState(() => _sets[index] = setData.copyWith(completed: true));

    final nowAllDone = _sets.every((s) => s.completed);
    if (!nowAllDone) {
      _startRest(we.restSeconds, goToNext: false);
      return;
    }

    final isLastExercise = _currentExerciseIndex >= _exercises.length - 1;
    if (isLastExercise) {
      await TrainingService.completeSession(widget.sessionId);
      if (mounted) _showCompletionDialog();
    } else {
      _startRest(we.restSeconds, goToNext: true);
    }
  }

  void _startRest(int seconds, {required bool goToNext}) {
    _restTimer?.cancel();
    _goToNextAfterRest = goToNext;
    var remaining = seconds;
    setState(() {
      _resting = true;
      _restSeconds = remaining;
      _initialRestSeconds = seconds;
    });
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      remaining--;
      if (mounted) {
        setState(() => _restSeconds = remaining);
        if (remaining <= 0) {
          t.cancel();
          _onRestEnd();
        }
      }
    });
  }

  void _onRestEnd() {
    setState(() => _resting = false);
    if (_goToNextAfterRest) _advanceExercise();
  }

  void _skipRest() {
    _restTimer?.cancel();
    _onRestEnd();
  }

  void _advanceExercise() {
    final nextIndex = _currentExerciseIndex + 1;
    if (nextIndex < _exercises.length) {
      setState(() {
        _currentExerciseIndex = nextIndex;
        _initExercise(_exercises[nextIndex]);
      });
    }
  }

  void _addSet() {
    final defaultReps = _parseDefaultReps(_currentExercise!.repsRange);
    setState(() => _sets.add(_SetData(reps: defaultReps)));
  }

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Прервать тренировку?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Текущий прогресс будет сохранён.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Продолжить',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/home');
            },
            child: const Text(
              'Выйти',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Тренировка завершена!',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          '🎉 Отличная работа!',
          style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/home');
            },
            child: const Text('На главную',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
        onExit: _confirmExit,
      );
    }

    final we = _currentExercise!;
    final activeIndex = _firstIncompleteIndex;
    final doneCount = _sets.where((s) => s.completed).length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _confirmExit,
        ),
        title: Text(
          '${_currentExerciseIndex + 1} / ${_exercises.length}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      we.exercise?.name ?? '?',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$doneCount из ${_sets.length} подходов выполнено',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),

                    // Вес
                    _WeightRow(
                      weight: _weight,
                      onChanged: (v) => setState(() => _weight = v),
                    ),
                    const SizedBox(height: 20),

                    // Шапка столбцов
                    const Padding(
                      padding: EdgeInsets.only(left: 44, right: 48),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Повт.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5)),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('RPE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Блоки подходов
                    ...List.generate(_sets.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SetBlock(
                          index: i,
                          data: _sets[i],
                          isActive:
                              i == activeIndex && !_sets[i].completed,
                          onRepsChanged: (v) => setState(
                              () => _sets[i] = _sets[i].copyWith(reps: v)),
                          onRpeChanged: (v) => setState(
                              () => _sets[i] = _sets[i].copyWith(rpe: v)),
                          onComplete: _sets[i].completed
                              ? null
                              : () => _completeSet(i),
                        ),
                      );
                    }),
                    const SizedBox(height: 4),

                    _AddSetButton(onTap: _addSet),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Кнопка следующего упражнения
            if (_allSetsCompleted &&
                _currentExerciseIndex < _exercises.length - 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: ElevatedButton(
                  onPressed: _advanceExercise,
                  child: const Text('Следующее упражнение'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Строка с весом ─────────────────────────────────────────────────────────

class _WeightRow extends StatelessWidget {
  final double weight;
  final ValueChanged<double> onChanged;

  const _WeightRow({required this.weight, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final display = weight > 0
        ? (weight % 1 == 0 ? '${weight.toInt()}' : '$weight')
        : '—';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Text('Вес, кг',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const Spacer(),
          _StepBtn(
            label: '−2.5',
            onTap: weight >= 2.5
                ? () => onChanged((weight - 2.5).clamp(0, 999))
                : null,
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 64,
            child: Text(
              display,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _StepBtn(
            label: '+2.5',
            onTap: () => onChanged(weight + 2.5),
          ),
        ],
      ),
    );
  }
}

// ─── Блок подхода ────────────────────────────────────────────────────────────

class _SetBlock extends StatelessWidget {
  final int index;
  final _SetData data;
  final bool isActive;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<int?> onRpeChanged;
  final VoidCallback? onComplete;

  const _SetBlock({
    required this.index,
    required this.data,
    required this.isActive,
    required this.onRepsChanged,
    required this.onRpeChanged,
    this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final done = data.completed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: isActive
            ? Border.all(color: AppColors.accent, width: 1.5)
            : done
                ? Border.all(
                    color: AppColors.accent.withValues(alpha: 0.25),
                    width: 1)
                : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Opacity(
        opacity: done ? 0.55 : 1.0,
        child: Row(
          children: [
            _SetBadge(number: index + 1, done: done, active: isActive),
            const SizedBox(width: 14),
            Expanded(
              child: _Stepper(
                value: data.reps,
                min: 1,
                max: 999,
                enabled: !done,
                onChanged: onRepsChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stepper(
                value: data.rpe ?? 0,
                min: 0,
                max: 10,
                enabled: !done,
                zeroLabel: '—',
                onChanged: (v) => onRpeChanged(v == 0 ? null : v),
              ),
            ),
            const SizedBox(width: 10),
            if (!done)
              GestureDetector(
                onTap: onComplete,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? AppColors.accent : AppColors.surface,
                  ),
                  child: Icon(Icons.check, size: 20,
                      color: isActive ? Colors.black : AppColors.textSecondary),
                ),
              )
            else
              const SizedBox(
                width: 38,
                height: 38,
                child: Center(
                  child: Icon(Icons.check_circle,
                      color: AppColors.accent, size: 22),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SetBadge extends StatelessWidget {
  final int number;
  final bool done;
  final bool active;

  const _SetBadge(
      {required this.number, required this.done, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? AppColors.accent
            : active
                ? AppColors.accent.withValues(alpha: 0.15)
                : AppColors.surface,
      ),
      alignment: Alignment.center,
      child: done
          ? const Icon(Icons.check, size: 15, color: Colors.black)
          : Text(
              '$number',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: active ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
    );
  }
}

// ─── Компактный степпер ──────────────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final String? zeroLabel;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    this.zeroLabel,
  });

  @override
  Widget build(BuildContext context) {
    final display =
        (value == 0 && zeroLabel != null) ? zeroLabel! : '$value';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MiniBtn(
            icon: Icons.remove,
            enabled: enabled && value > min,
            onTap: () => onChanged(value - 1)),
        const SizedBox(width: 6),
        SizedBox(
          width: 32,
          child: Text(display,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              )),
        ),
        const SizedBox(width: 6),
        _MiniBtn(
            icon: Icons.add,
            enabled: enabled && value < max,
            onTap: () => onChanged(value + 1)),
      ],
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _MiniBtn(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
            shape: BoxShape.circle, color: AppColors.surface),
        child: Icon(icon,
            size: 14,
            color: enabled
                ? AppColors.textPrimary
                : AppColors.textSecondary.withValues(alpha: 0.35)),
      ),
    );
  }
}

// ─── Кнопка «+» добавить подход ──────────────────────────────────────────────

class _AddSetButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddSetButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.45), width: 1.2),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: AppColors.accent, size: 18),
            SizedBox(width: 8),
            Text('Добавить подход',
                style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ─── Кнопки шага веса ────────────────────────────────────────────────────────

class _StepBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _StepBtn({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active
                    ? AppColors.accent
                    : AppColors.textSecondary
                        .withValues(alpha: 0.4))),
      ),
    );
  }
}

// ─── Экран отдыха ────────────────────────────────────────────────────────────

class _RestScreen extends StatelessWidget {
  final int initialSeconds;
  final int seconds;
  final VoidCallback onSkip;
  final VoidCallback onExit;

  const _RestScreen({
    required this.initialSeconds,
    required this.seconds,
    required this.onSkip,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final timeStr =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final progress =
        initialSeconds > 0 ? 1 - (seconds / initialSeconds) : 1.0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onExit,
        ),
        title: const Text('Отдых'),
      ),
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
                        color: AppColors.accent),
                    Text(timeStr,
                        style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text('Отдых',
                  style: TextStyle(
                      fontSize: 24, color: AppColors.textSecondary)),
              const Spacer(),
              TextButton(
                onPressed: onSkip,
                child: const Text('Пропустить',
                    style:
                        TextStyle(color: AppColors.accent, fontSize: 18)),
              ),
              if (seconds <= 0) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onSkip,
                    child: const Text('Следующий подход'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
