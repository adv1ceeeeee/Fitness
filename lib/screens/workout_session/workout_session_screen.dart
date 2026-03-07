import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportwai/providers/settings_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/providers/active_session_provider.dart';
import 'package:sportwai/services/event_logger.dart';
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

class WorkoutSessionScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const WorkoutSessionScreen({super.key, required this.sessionId});

  @override
  ConsumerState<WorkoutSessionScreen> createState() =>
      _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends ConsumerState<WorkoutSessionScreen> {
  List<WorkoutExercise> _exercises = [];
  Map<String, double> _personalBests = {};
  int _currentExerciseIndex = 0;
  bool _loading = true;
  bool _resting = false;
  int _restSeconds = 0;
  Timer? _restTimer;
  bool _goToNextAfterRest = false;
  DateTime? _restStartedAt;
  int _lastRestSeconds = 0;

  List<_SetData> _sets = [];
  List<TextEditingController> _weightControllers = [];

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    for (final c in _weightControllers) {
      c.dispose();
    }
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

    final pbs = <String, double>{};
    for (final e in ex) {
      final pb = await TrainingService.getPersonalBest(e.exerciseId);
      if (pb != null) pbs[e.exerciseId] = pb;
    }

    if (mounted) {
      setState(() {
        _exercises = ex;
        _personalBests = pbs;
        _loading = false;
        if (ex.isNotEmpty) _initExercise(ex[0]);
      });
    }
  }

  void _initExercise(WorkoutExercise we) {
    final defaultReps = _parseDefaultReps(we.repsRange);
    for (final c in _weightControllers) {
      c.dispose();
    }
    _weightControllers = List.generate(we.sets, (_) => TextEditingController());
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
    if (_sets[index].completed) return;
    final we = _currentExercise!;
    final setData = _sets[index];
    final restSecondsToSave = _lastRestSeconds > 0 ? _lastRestSeconds : null;

    final useKg = ref.read(useKgProvider);
    final weightText = _weightControllers[index].text.replaceAll(',', '.');
    final displayWeight = double.tryParse(weightText) ?? 0.0;
    final weightKg = useKg ? displayWeight : displayWeight / 2.20462;

    // Optimistic update — instant visual feedback
    setState(() => _sets[index] = setData.copyWith(completed: true));
    _lastRestSeconds = 0;

    final nowAllDone = _sets.every((s) => s.completed);
    if (!nowAllDone) {
      _startRest(we.restSeconds, goToNext: false);
    } else {
      final isLastExercise = _currentExerciseIndex >= _exercises.length - 1;
      if (isLastExercise) {
        if (mounted) _goToSummary();
      } else {
        _startRest(we.restSeconds, goToNext: true);
      }
    }

    // Save to DB in background
    await TrainingService.saveSet(
      widget.sessionId,
      we.id,
      index + 1,
      weight: weightKg > 0 ? weightKg : null,
      reps: setData.reps,
      rpe: setData.rpe,
      restSeconds: restSecondsToSave,
    );

    EventLogger.setCompleted(
      exerciseId: we.exerciseId,
      setNumber: index + 1,
      reps: setData.reps,
      weightKg: weightKg > 0 ? weightKg : null,
      restSeconds: restSecondsToSave,
    );

    // Personal record check
    if (weightKg > 0 && mounted) {
      final exerciseId = we.exerciseId;
      final prev = _personalBests[exerciseId];
      if (prev == null || weightKg > prev) {
        _personalBests[exerciseId] = weightKg;
        EventLogger.personalRecord(exerciseId: exerciseId, weightKg: weightKg);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Личный рекорд! 🏆'),
            backgroundColor: Color(0xFF30D158),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _startRest(int _, {required bool goToNext}) {
    _restTimer?.cancel();
    _goToNextAfterRest = goToNext;
    _restStartedAt = DateTime.now();
    setState(() {
      _resting = true;
      _restSeconds = 0;
    });
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() => _restSeconds++);
    });
  }

  void _onRestEnd() {
    if (_restStartedAt != null) {
      _lastRestSeconds =
          DateTime.now().difference(_restStartedAt!).inSeconds;
      _restStartedAt = null;
    }
    setState(() => _resting = false);
    if (_goToNextAfterRest) _advanceExercise();
  }

  void _skipRest() {
    _restTimer?.cancel();
    EventLogger.restSkipped(elapsedSeconds: _restSeconds);
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
    setState(() {
      _sets.add(_SetData(reps: defaultReps));
      _weightControllers.add(TextEditingController());
    });
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
              EventLogger.workoutAbandoned(sessionId: widget.sessionId);
              ref.read(activeSessionProvider.notifier).stop();
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

  void _goToSummary() {
    final sessionState = ref.read(activeSessionProvider);
    final durationSeconds = sessionState.isActive
        ? sessionState.elapsed.inSeconds
        : 0;
    EventLogger.workoutCompleted(
      sessionId: widget.sessionId,
      durationSeconds: durationSeconds,
      setsCount: _sets.where((s) => s.completed).length,
    );
    context.pushReplacement(
      '/session-summary',
      extra: {
        'sessionId': widget.sessionId,
        'workoutId': sessionState.workoutId ?? '',
        'durationSeconds': durationSeconds,
      },
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
        seconds: _restSeconds,
        onSkip: _skipRest,
        onExit: _confirmExit,
      );
    }

    final useKg = ref.watch(useKgProvider);
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

                    // Шапка столбцов
                    Padding(
                      padding: const EdgeInsets.only(left: 44, right: 48),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 72,
                            child: Text(
                              'Вес, ${weightLabel(useKg)}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 0.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('Повт.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5)),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
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
                          isActive: i == activeIndex && !_sets[i].completed,
                          weightController: _weightControllers[i],
                          onRepsChanged: (v) => setState(
                              () => _sets[i] = _sets[i].copyWith(reps: v)),
                          onRpeChanged: (v) =>
                              setState(() => _sets[i].rpe = v),
                          onComplete: (!_sets[i].completed && i == activeIndex)
                              ? () => _completeSet(i)
                              : null,
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

// ─── Блок подхода ────────────────────────────────────────────────────────────

class _SetBlock extends StatelessWidget {
  final int index;
  final _SetData data;
  final bool isActive;
  final TextEditingController weightController;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<int?> onRpeChanged;
  final VoidCallback? onComplete;

  const _SetBlock({
    required this.index,
    required this.data,
    required this.isActive,
    required this.weightController,
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
            const SizedBox(width: 8),
            // Поле ввода веса
            SizedBox(
              width: 72,
              height: 36,
              child: TextField(
                controller: weightController,
                enabled: !done,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: done
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: '—',
                  hintStyle:
                      const TextStyle(color: AppColors.textSecondary),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 8),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: AppColors.accent, width: 1.2),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
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
                  child: Icon(Icons.check,
                      size: 20,
                      color: isActive
                          ? Colors.black
                          : AppColors.textSecondary),
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

// ─── Экран отдыха ────────────────────────────────────────────────────────────

class _RestScreen extends StatelessWidget {
  final int seconds;
  final VoidCallback onSkip;
  final VoidCallback onExit;

  const _RestScreen({
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onExit,
        ),
        title: const Text('Отдых'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeStr,
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Отдых',
              style: TextStyle(fontSize: 20, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: 200,
              height: 52,
              child: ElevatedButton(
                onPressed: onSkip,
                child: const Text(
                  'Готов',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
