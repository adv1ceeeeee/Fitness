import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemSound, SystemSoundType;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/providers/settings_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/providers/active_session_provider.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/body_metrics_service.dart';
import 'package:sportwai/services/calorie_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/notification_service.dart';
import 'package:sportwai/services/exercise_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/workout_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

enum _SessionPhase { warmup, exercise, cooldown }

// ─── Локальная модель одного подхода ────────────────────────────────────────

class _SetData {
  int reps;
  int repsTarget;
  int? rpe;
  bool completed;
  bool isWarmup;

  _SetData({required this.reps, required this.repsTarget, this.rpe, this.completed = false, this.isWarmup = false});

  _SetData copyWith({int? reps, int? repsTarget, int? rpe, bool? completed, bool? isWarmup}) => _SetData(
        reps: reps ?? this.reps,
        repsTarget: repsTarget ?? this.repsTarget,
        rpe: rpe ?? this.rpe,
        completed: completed ?? this.completed,
        isWarmup: isWarmup ?? this.isWarmup,
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

class _WorkoutSessionScreenState extends ConsumerState<WorkoutSessionScreen>
    with WidgetsBindingObserver {
  List<WorkoutExercise> _exercises = [];
  Map<String, double> _personalBests = {};
  Map<String, Map<String, dynamic>> _lastSets = {};
  double? _userWeightKg;
  int _completedSetsBefore = 0;
  int _totalExpectedSets = 0;
  int _currentExerciseIndex = 0;
  bool _loading = true;
  bool _loadError = false;
  _SessionPhase _phase = _SessionPhase.exercise;
  int _warmupMinutes = 0;
  int _cooldownMinutes = 0;
  int _phaseSecondsLeft = 0;
  Timer? _phaseTimer;
  bool _resting = false;
  int _restSeconds = 0;
  int _targetRestSeconds = 0;
  Timer? _restTimer;
  bool _goToNextAfterRest = false;
  DateTime? _restStartedAt;
  DateTime? _pausedAt;
  int _lastRestSeconds = 0;

  bool _deloadActive = false;
  Set<String> _fatiguedCategories = {}; // categories trained < 48h ago
  bool _fatigueBannerDismissed = false;

  List<_SetData> _sets = [];
  List<TextEditingController> _weightControllers = [];
  // Comparison result per set index: 1 = better, 0 = same, -1 = worse, null = no data
  final Map<int, int?> _setComparisons = {};
  // exerciseIds where last 3 sessions all hit max reps → suggest weight increase
  Set<String> _autoProgressSuggestions = {};

  double get _progressValue {
    if (_totalExpectedSets == 0) return 0.0;
    final done = _completedSetsBefore + _sets.where((s) => s.completed).length;
    return (done / _totalExpectedSets).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phaseTimer?.cancel();
    _restTimer?.cancel();
    for (final c in _weightControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _resting) {
      _restTimer?.cancel();
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _resting) {
      if (_pausedAt != null) {
        final elapsed = DateTime.now().difference(_pausedAt!).inSeconds;
        _restSeconds += elapsed;
        _pausedAt = null;
      }
      _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _restSeconds++);
      });
    }
  }

  Future<void> _loadSession() async {
    if (mounted) setState(() => _loadError = false);
    try {
    final prefs = await SharedPreferences.getInstance();
    final deload = prefs.getBool('deload_active') ?? false;
    if (mounted) setState(() => _deloadActive = deload);

    final sessionRes = await Supabase.instance.client
        .from('training_sessions')
        .select('workout_id')
        .eq('id', widget.sessionId)
        .single()
        .timeout(const Duration(seconds: 15));

    final workoutId = sessionRes['workout_id'] as String;

    // Load exercises, workout settings, personal bests, and last sets concurrently
    final workoutFuture = Supabase.instance.client
        .from('workouts')
        .select('warmup_minutes, cooldown_minutes')
        .eq('id', workoutId)
        .single();
    final ex = await TrainingService.getWorkoutExercisesForToday(workoutId);
    final workoutRes2 = await workoutFuture;
    final exerciseIds = ex.map((e) => e.exerciseId).toList();

    final pbFutures = ex.map((e) => TrainingService.getPersonalBest(e.exerciseId)).toList();
    final lastSetsFuture = AnalyticsService.getLastSetsForExercises(exerciseIds);
    final userMetricsFuture = BodyMetricsService.getLatest();
    final pbValues = await Future.wait(pbFutures);
    final lastSets = await lastSetsFuture;
    final userMetrics = await userMetricsFuture;

    // Build topReps map for auto-progress check
    final topRepsMap = <String, int>{};
    for (final e in ex) {
      final top = _parseTopReps(e.repsRange);
      if (top != null) topRepsMap[e.exerciseId] = top;
    }
    final autoProgress = await AnalyticsService.getConsecutiveFullRepsExercises(
      exerciseIds, topRepsMap);

    // Fatigue check: categories of today's workout vs recently trained (<48h)
    final recentCats = await AnalyticsService.getRecentlyTrainedCategories();
    final workoutCats = ex
        .map((e) => e.exercise?.category)
        .whereType<String>()
        .toSet();
    final fatigued = recentCats.intersection(workoutCats)
      ..remove('cardio'); // cardio doesn't count as fatigue

    final pbs = <String, double>{};
    for (var i = 0; i < ex.length; i++) {
      if (pbValues[i] != null) pbs[ex[i].exerciseId] = pbValues[i]!;
    }

    final warmupMins = workoutRes2['warmup_minutes'] as int? ?? 0;
    final cooldownMins = workoutRes2['cooldown_minutes'] as int? ?? 0;

    if (mounted) {
      setState(() {
        _exercises = ex;
        _personalBests = pbs;
        _lastSets = lastSets;
        _autoProgressSuggestions = autoProgress;
        _fatiguedCategories = fatigued;
        _userWeightKg = (userMetrics?['weight_kg'] as num?)?.toDouble();
        _totalExpectedSets = ex.fold(0, (sum, e) => sum + e.sets);
        _warmupMinutes = warmupMins;
        _cooldownMinutes = cooldownMins;
        _loading = false;
        if (ex.isNotEmpty) _initExercise(ex[0]);
        if (_warmupMinutes > 0) {
          _phase = _SessionPhase.warmup;
          _phaseSecondsLeft = _warmupMinutes * 60;
        }
      });
      if (_warmupMinutes > 0) _startPhaseTimer();

      // Log auto-progress suggestions shown to user
      for (final exerciseId in autoProgress) {
        EventLogger.autoProgressSuggestionShown(
          exerciseId: exerciseId,
          isStrong: true,
        );
      }
      // Log single-session suggestions (suggestIncrease but not strongSuggest)
      for (final we in ex) {
        if (!autoProgress.contains(we.exerciseId)) {
          final top = _parseTopReps(we.repsRange);
          final lastReps = lastSets[we.exerciseId]?['reps'] as int?;
          final lastWeight = lastSets[we.exerciseId]?['weight'] as double?;
          if (top != null && lastReps != null && lastReps >= top && lastWeight != null && lastWeight > 0) {
            EventLogger.autoProgressSuggestionShown(
              exerciseId: we.exerciseId,
              isStrong: false,
            );
          }
        }
      }
    }
    } catch (e, st) {
      debugPrint('_loadSession error: $e\n$st');
      if (mounted) setState(() { _loading = false; _loadError = true; });
    }
  }

  void _initExercise(WorkoutExercise we) {
    final defaultReps = _parseDefaultReps(we.repsRange);
    final lastWeight = _lastSets[we.exerciseId]?['weight'] as double?;
    final prefillWeight =
        lastWeight != null && _deloadActive ? lastWeight * 0.6 : lastWeight;
    final lastWeightText = prefillWeight != null
        ? prefillWeight.toStringAsFixed(prefillWeight % 1 == 0 ? 0 : 1)
        : '';
    for (final c in _weightControllers) {
      c.dispose();
    }
    _weightControllers = List.generate(
        we.sets, (_) => TextEditingController(text: lastWeightText));
    _sets = List.generate(we.sets, (_) => _SetData(reps: defaultReps, repsTarget: defaultReps));
    _setComparisons.clear();
  }

  void _startPhaseTimer() {
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_phaseSecondsLeft > 0) {
          _phaseSecondsLeft--;
        } else {
          _phaseTimer?.cancel();
          _onPhaseTimerEnd();
        }
      });
    });
  }

  void _onPhaseTimerEnd() {
    if (_phase == _SessionPhase.warmup) {
      setState(() => _phase = _SessionPhase.exercise);
    } else if (_phase == _SessionPhase.cooldown) {
      _goToSummary();
    }
  }

  void _skipPhase() {
    _phaseTimer?.cancel();
    _onPhaseTimerEnd();
  }

  void _finishExercises() {
    if (_cooldownMinutes > 0) {
      setState(() {
        _phase = _SessionPhase.cooldown;
        _phaseSecondsLeft = _cooldownMinutes * 60;
      });
      _startPhaseTimer();
    } else {
      _goToSummary();
    }
  }

  int _parseDefaultReps(String range) {
    final first = range.split('-')[0].trim();
    return int.tryParse(first) ?? 8;
  }

  /// Returns the top (max) reps from a range like "8-12" → 12, "5" → 5.
  /// Returns null for cardio/time-based ranges (e.g. "15 мин").
  int? _parseTopReps(String range) {
    final parts = range.split('-');
    final last = parts.last.trim().split(' ')[0];
    return int.tryParse(last);
  }

  WorkoutExercise? get _currentExercise {
    if (_currentExerciseIndex >= _exercises.length) return null;
    return _exercises[_currentExerciseIndex];
  }

  int get _firstIncompleteIndex => _sets.indexWhere((s) => !s.completed);

  bool get _allSetsCompleted => _sets.every((s) => s.completed);

  Future<void> _completeSet(int index) async {
    if (_sets[index].completed) return;
    HapticFeedback.lightImpact();
    final we = _currentExercise!;
    final setData = _sets[index];
    final restSecondsToSave = _lastRestSeconds > 0 ? _lastRestSeconds : null;

    final useKg = ref.read(useKgProvider);
    final weightText = _weightControllers[index].text.replaceAll(',', '.');
    final displayWeight = double.tryParse(weightText) ?? 0.0;
    final weightKg = useKg ? displayWeight : displayWeight / 2.20462;

    // Compute comparison with last session
    final lastWeight = _lastSets[we.exerciseId]?['weight'] as double?;
    if (lastWeight != null && weightKg > 0) {
      final diff = weightKg - lastWeight;
      _setComparisons[index] = diff > 0.001 ? 1 : (diff < -0.001 ? -1 : 0);
    } else {
      _setComparisons[index] = null;
    }

    // Optimistic update — instant visual feedback
    setState(() {
      _sets[index] = setData.copyWith(completed: true);
      // Drop-set: auto-fill next set with half the current weight
      if (we.isDropSet && index + 1 < _sets.length && weightKg > 0) {
        final half = weightKg / 2;
        final useKgLocal = ref.read(useKgProvider);
        final displayHalf = useKgLocal ? half : half * 2.20462;
        _weightControllers[index + 1].text =
            displayHalf.toStringAsFixed(displayHalf % 1 == 0 ? 0 : 1);
      }
    });
    _lastRestSeconds = 0;

    final nowAllDone = _sets.every((s) => s.completed);
    if (!nowAllDone) {
      // Drop-set: no rest between sets — go straight to next set
      if (!we.isDropSet) {
        _startRest(we.restSeconds, goToNext: false);
      }
    } else {
      final isLastExercise = _currentExerciseIndex >= _exercises.length - 1;
      if (isLastExercise) {
        if (mounted) _finishExercises();
      } else {
        final next = _exercises[_currentExerciseIndex + 1];
        final inSameSuperset = we.supersetGroup != null &&
            we.supersetGroup == next.supersetGroup;
        if (inSameSuperset) {
          // No rest inside a superset — advance immediately
          if (mounted) _advanceExercise();
        } else {
          _startRest(we.restSeconds, goToNext: true);
        }
      }
    }

    // Estimate kcal for this set
    final kcalEstimated = setData.reps > 0
        ? estimateSetKcal(
            category: we.exercise?.category ?? 'chest',
            reps: setData.reps,
            rpe: setData.rpe,
            userWeightKg: _userWeightKg,
          )
        : null;

    // Save to DB in background; show retry snackbar on failure
    final saved = await TrainingService.saveSet(
      widget.sessionId,
      we.id,
      index + 1,
      weight: weightKg > 0 ? weightKg : null,
      reps: setData.reps,
      repsTarget: setData.repsTarget,
      rpe: setData.rpe,
      restSeconds: restSecondsToSave,
      kcalEstimated: kcalEstimated,
      isWarmup: setData.isWarmup,
    );

    if (!saved && mounted) {
      final sessionId = widget.sessionId;
      final weId = we.id;
      final setNum = index + 1;
      final w = weightKg > 0 ? weightKg : null;
      final r = setData.reps;
      final rpe = setData.rpe;
      final rest = restSecondsToSave;
      final warmup = setData.isWarmup;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Не удалось сохранить подход'),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => TrainingService.saveSet(
              sessionId, weId, setNum,
              weight: w, reps: r, rpe: rpe, restSeconds: rest, isWarmup: warmup,
            ),
          ),
        ),
      );
    }

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
        HapticFeedback.heavyImpact();
        EventLogger.personalRecord(exerciseId: exerciseId, weightKg: weightKg);
        _showPrBanner(we.exercise?.name ?? '', weightKg);
      }
    }
  }

  void _showPlateCalc(double weightKg, {required bool useKg}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PlateCalcSheet(weightKg: weightKg, useKg: useKg),
    );
  }

  void _showPrBanner(String exerciseName, double weightKg) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PrBanner(
        exerciseName: exerciseName,
        weightKg: weightKg,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  void _startRest(int targetSeconds, {required bool goToNext}) {
    _restTimer?.cancel();
    _goToNextAfterRest = goToNext;
    _restStartedAt = DateTime.now();
    _targetRestSeconds = targetSeconds;
    setState(() {
      _resting = true;
      _restSeconds = 0;
    });
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _restSeconds++);
      if (_restSeconds == _targetRestSeconds && _targetRestSeconds > 0) {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
      }
    });
  }

  void _onRestEnd() {
    HapticFeedback.mediumImpact();
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
      HapticFeedback.mediumImpact();
      setState(() {
        _completedSetsBefore += _sets.length;
        _currentExerciseIndex = nextIndex;
        _initExercise(_exercises[nextIndex]);
      });
    }
  }

  void _addSet() {
    HapticFeedback.selectionClick();
    final defaultReps = _parseDefaultReps(_currentExercise!.repsRange);
    setState(() {
      _sets.add(_SetData(reps: defaultReps, repsTarget: defaultReps));
      _weightControllers.add(TextEditingController());
    });
    EventLogger.setAdded(
      sessionId: widget.sessionId,
      exerciseId: _currentExercise!.exerciseId,
      newSetCount: _sets.length,
    );
  }

  Future<void> _showReplaceExercise() async {
    final exercises = await ExerciseService.getExercises();
    if (!mounted) return;
    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, sc) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Заменить упражнение',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: sc,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: exercises.length,
                itemBuilder: (_, i) {
                  final ex = exercises[i];
                  return ListTile(
                    title: Text(ex.name,
                        style: const TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(
                      Exercise.categoryDisplayName(ex.category),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    onTap: () => Navigator.pop(ctx, ex),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final we = _currentExercise!;
    EventLogger.exerciseReplaced(
      sessionId: widget.sessionId,
      fromExerciseId: we.exerciseId,
      toExerciseId: picked.id,
    );
    // Persist the replacement to the workout_exercise record
    await WorkoutService.updateExerciseInWorkout(we.id, picked.id);
    // Update local state
    final updated = we.copyWithExercise(picked);
    setState(() {
      _exercises[_currentExerciseIndex] = updated;
      _initExercise(updated);
    });
    // Load last sets for new exercise
    final lastSets = await AnalyticsService.getLastSetsForExercises([picked.id]);
    if (mounted) setState(() => _lastSets[picked.id] = lastSets[picked.id] ?? {});
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
              final currentEx = _currentExerciseIndex < _exercises.length
                  ? _exercises[_currentExerciseIndex]
                  : null;
              if (currentEx != null) {
                EventLogger.workoutAbandonedAt(
                  sessionId: widget.sessionId,
                  exerciseName: currentEx.exercise?.name ?? '?',
                  setsCompleted: _sets.where((s) => s.completed).length,
                );
              }
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

  Future<void> _goToSummary() async {
    HapticFeedback.heavyImpact();
    final sessionState = ref.read(activeSessionProvider);
    final durationSeconds = sessionState.isActive
        ? sessionState.elapsed.inSeconds
        : 0;
    EventLogger.workoutCompleted(
      sessionId: widget.sessionId,
      durationSeconds: durationSeconds,
      setsCount: _sets.where((s) => s.completed).length,
    );
    // Aggregate per-set kcal into session total (fire-and-forget, errors logged internally)
    TrainingService.saveSessionKcal(widget.sessionId);
    // Invalidate cached stats so next screen open shows fresh numbers
    AnalyticsService.invalidateStatsCache();
    // Refresh weekly summary notification with updated stats (fire-and-forget)
    NotificationService.refreshWeeklySummary();
    // Check streak milestone (fire-and-forget)
    AnalyticsService.getCurrentStreak().then((streak) {
      const milestones = [7, 14, 30, 60, 100, 200, 365];
      if (milestones.contains(streak)) EventLogger.streakMilestone(days: streak);
    }).catchError((_) {});
    if (!mounted) return;
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
    if (_loadError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Тренировка')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Не удалось загрузить тренировку', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadSession,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    if (_exercises.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Тренировка')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fitness_center_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                const Text(
                  'Нет упражнений',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Добавьте упражнения в эту тренировку',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_phase == _SessionPhase.warmup || _phase == _SessionPhase.cooldown) {
      return _PhaseScreen(
        isWarmup: _phase == _SessionPhase.warmup,
        secondsLeft: _phaseSecondsLeft,
        onSkip: _skipPhase,
        onExit: _confirmExit,
      );
    }
    if (_resting) {
      return _RestScreen(
        seconds: _restSeconds,
        targetSeconds: _targetRestSeconds,
        onSkip: _skipRest,
        onExit: _confirmExit,
        nextExerciseName: _goToNextAfterRest && _currentExerciseIndex + 1 < _exercises.length
            ? _exercises[_currentExerciseIndex + 1].exercise?.name
            : null,
      );
    }

    final useKg = ref.watch(useKgProvider);
    final we = _currentExercise!;
    final activeIndex = _firstIncompleteIndex;
    final doneCount = _sets.where((s) => s.completed).length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmExit,
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                we.exercise?.name ?? '',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${_currentExerciseIndex + 1} / ${_exercises.length}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: 'Заменить упражнение',
              onPressed: _showReplaceExercise,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: _progressValue,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
              minHeight: 4,
            ),
          ),
        ),
        body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                child: SingleChildScrollView(
                  key: ValueKey(_currentExerciseIndex),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fatigue warning banner
                    if (_fatiguedCategories.isNotEmpty && !_fatigueBannerDismissed) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Эти мышцы тренировались < 48 ч назад: '
                                '${_fatiguedCategories.map((c) => Exercise.categoryDisplayName(c)).join(', ')}. '
                                'Риск перетренированности.',
                                style: const TextStyle(color: AppColors.error, fontSize: 12),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _fatigueBannerDismissed = true),
                              child: const Icon(Icons.close, size: 16, color: AppColors.error),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Deload banner
                    if (_deloadActive) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.5)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.battery_saver_rounded,
                                color: AppColors.warning, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'Деload-неделя: вес снижен на 40%',
                              style: TextStyle(
                                color: AppColors.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Drop-set badge
                    if (we.isDropSet) ...[
                      const _DropSetBadge(),
                      const SizedBox(height: 8),
                    ],
                    // Superset badge
                    if (we.supersetGroup != null) ...[
                      _SupersetBadge(
                        exercises: _exercises,
                        currentIndex: _currentExerciseIndex,
                      ),
                      const SizedBox(height: 8),
                    ],
                    GestureDetector(
                      onLongPress: we.exercise != null
                          ? () => context.push(
                                '/exercise/${we.exerciseId}/history',
                                extra: we.exercise,
                              )
                          : null,
                      child: Text(
                        we.exercise?.name ?? '?',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$doneCount из ${_sets.length} подходов выполнено',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                    // Exercise GIF
                    if (we.exercise?.gifUrl != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: we.exercise!.gifUrl!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => Container(
                            height: 180,
                            color: AppColors.surface,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                    if (_lastSets[we.exerciseId] != null) ...[
                      const SizedBox(height: 2),
                      Builder(builder: (_) {
                        final last = _lastSets[we.exerciseId]!;
                        final w = last['weight'] as double;
                        final r = last['reps'] as int;
                        final d = last['date'] as String;
                        final useKg = ref.read(useKgProvider);
                        final displayW = useKg ? w : w * 2.20462;
                        final unit = useKg ? 'кг' : 'лб';
                        final dateShort = d.length >= 10
                            ? '${d.substring(8, 10)}.${d.substring(5, 7)}'
                            : d;
                        // Suggestion: if last reps >= top of range, suggest +2.5 kg
                        final topReps = _parseTopReps(we.repsRange);
                        final suggestIncrease = topReps != null && r >= topReps && w > 0;
                        final strongSuggest = _autoProgressSuggestions.contains(we.exerciseId);
                        final suggestWeight = useKg ? w + 2.5 : (w + 2.5) * 2.20462;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Прошлый: ${displayW.toStringAsFixed(1)} $unit × $r ($dateShort)',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.accent),
                            ),
                            if (strongSuggest) ...[
                              GestureDetector(
                                onTap: () {
                                  final suggestWeightKg = w + 2.5;
                                  for (final c in _weightControllers) {
                                    if (c.text.isEmpty || double.tryParse(c.text.replaceAll(',', '.')) == w) {
                                      c.text = suggestWeightKg.toStringAsFixed(suggestWeightKg % 1 == 0 ? 0 : 1);
                                    }
                                  }
                                  EventLogger.autoProgressAccepted(
                                    exerciseId: we.exerciseId,
                                    suggestedWeightKg: suggestWeightKg,
                                    isStrong: true,
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.trending_up, size: 14, color: AppColors.success),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Пора увеличить вес! 3 подряд → ${suggestWeight.toStringAsFixed(1)} $unit',
                                        style: const TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ] else if (suggestIncrease) ...[
                              GestureDetector(
                                onTap: () {
                                  final suggestWeightKg = w + 2.5;
                                  for (final c in _weightControllers) {
                                    if (c.text.isEmpty || double.tryParse(c.text.replaceAll(',', '.')) == w) {
                                      c.text = suggestWeightKg.toStringAsFixed(suggestWeightKg % 1 == 0 ? 0 : 1);
                                    }
                                  }
                                  EventLogger.autoProgressAccepted(
                                    exerciseId: we.exerciseId,
                                    suggestedWeightKg: suggestWeightKg,
                                    isStrong: false,
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.trending_up, size: 14, color: AppColors.success),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Попробуй +2.5 $unit → ${suggestWeight.toStringAsFixed(1)} $unit',
                                        style: const TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      }),
                    ],
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

                    // Plate calculator chip
                    Builder(builder: (_) {
                      final activeCtrl = activeIndex >= 0 && activeIndex < _weightControllers.length
                          ? _weightControllers[activeIndex]
                          : null;
                      final weightVal = double.tryParse(
                          activeCtrl?.text.replaceAll(',', '.') ?? '');
                      final useKg = ref.read(useKgProvider);
                      if (weightVal == null || weightVal <= 0 || we.exercise?.category == 'cardio') {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () => _showPlateCalc(weightVal, useKg: useKg),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.fitness_center, size: 14, color: AppColors.accent),
                                const SizedBox(width: 6),
                                Text(
                                  'Блины для ${useKg ? weightVal.toStringAsFixed(1) : (weightVal * 2.20462).toStringAsFixed(1)} ${useKg ? "кг" : "лб"}',
                                  style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                    // Блоки подходов
                    ...List.generate(_sets.length, (i) {
                      return Column(
                        children: [
                          if (we.isDropSet && i > 0)
                            const _DropSetDivider(),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SetBlock(
                              index: i,
                              data: _sets[i],
                              isActive: i == activeIndex && !_sets[i].completed,
                              weightController: _weightControllers[i],
                              comparison: _setComparisons[i],
                              onRepsChanged: (v) => setState(
                                  () => _sets[i] = _sets[i].copyWith(reps: v)),
                              onRpeChanged: (v) =>
                                  setState(() => _sets[i].rpe = v),
                              onComplete: (!_sets[i].completed && i == activeIndex)
                                  ? () => _completeSet(i)
                                  : null,
                              onWarmupToggle: !_sets[i].completed
                                  ? () => setState(() => _sets[i] =
                                      _sets[i].copyWith(isWarmup: !_sets[i].isWarmup))
                                  : null,
                            ),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 4),

                    _AddSetButton(onTap: _addSet),
                    const SizedBox(height: 16),
                  ],
                ),
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
  // 1 = better than last, 0 = same, -1 = worse, null = no previous data
  final int? comparison;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<int?> onRpeChanged;
  final VoidCallback? onComplete;
  final VoidCallback? onWarmupToggle;

  const _SetBlock({
    required this.index,
    required this.data,
    required this.isActive,
    required this.weightController,
    this.comparison,
    required this.onRepsChanged,
    required this.onRpeChanged,
    this.onComplete,
    this.onWarmupToggle,
  });

  @override
  Widget build(BuildContext context) {
    final done = data.completed;

    final warmup = data.isWarmup;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: warmup
            ? const Color(0xFFB8690A).withValues(alpha: 0.08)
            : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: warmup
            ? Border.all(color: const Color(0xFFB8690A).withValues(alpha: 0.35), width: 1)
            : isActive
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
            _SetBadge(number: index + 1, done: done, active: isActive && !warmup, isWarmup: warmup),
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
            const SizedBox(width: 4),
            if (!done)
              GestureDetector(
                onTap: onWarmupToggle,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    warmup
                        ? Icons.local_fire_department
                        : Icons.local_fire_department_outlined,
                    size: 20,
                    color: warmup
                        ? const Color(0xFFB8690A)
                        : AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            const SizedBox(width: 2),
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
              SizedBox(
                width: 38,
                height: 38,
                child: Center(
                  child: comparison == null
                      ? const Icon(Icons.check_circle,
                          color: AppColors.accent, size: 22)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              comparison! > 0
                                  ? Icons.arrow_upward
                                  : comparison! < 0
                                      ? Icons.arrow_downward
                                      : Icons.remove,
                              size: 18,
                              color: comparison! > 0
                                  ? AppColors.success
                                  : comparison! < 0
                                      ? AppColors.error
                                      : AppColors.textSecondary,
                            ),
                          ],
                        ),
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
  final bool isWarmup;

  const _SetBadge({
    required this.number,
    required this.done,
    required this.active,
    this.isWarmup = false,
  });

  @override
  Widget build(BuildContext context) {
    const warmupColor = Color(0xFFB8690A);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? (isWarmup ? warmupColor : AppColors.accent)
            : active
                ? (isWarmup
                    ? warmupColor.withValues(alpha: 0.18)
                    : AppColors.accent.withValues(alpha: 0.15))
                : AppColors.surface,
      ),
      alignment: Alignment.center,
      child: done
          ? Icon(Icons.check, size: 15, color: isWarmup ? Colors.white : Colors.black)
          : isWarmup
              ? const Icon(Icons.local_fire_department, size: 15, color: warmupColor)
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

class _MiniBtn extends StatefulWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _MiniBtn(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  State<_MiniBtn> createState() => _MiniBtnState();
}

class _MiniBtnState extends State<_MiniBtn> {
  Timer? _timer;

  void _startRepeat() {
    widget.onTap();
    HapticFeedback.selectionClick();
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (widget.enabled) {
        widget.onTap();
        HapticFeedback.selectionClick();
      }
    });
  }

  void _stopRepeat() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      onLongPressStart: widget.enabled ? (_) => _startRepeat() : null,
      onLongPressEnd: (_) => _stopRepeat(),
      onLongPressCancel: _stopRepeat,
      child: Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
            shape: BoxShape.circle, color: AppColors.surface),
        child: Icon(widget.icon,
            size: 14,
            color: widget.enabled
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

// ─── PR Overlay Banner ───────────────────────────────────────────────────────

class _PrBanner extends StatefulWidget {
  final String exerciseName;
  final double weightKg;
  final VoidCallback onDismiss;

  const _PrBanner({
    required this.exerciseName,
    required this.weightKg,
    required this.onDismiss,
  });

  @override
  State<_PrBanner> createState() => _PrBannerState();
}

class _PrBannerState extends State<_PrBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 2200), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse(from: 1.0);
    widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Positioned(
      top: safeTop + 12,
      left: 24,
      right: 24,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _opacity,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Личный рекорд!',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (widget.exerciseName.isNotEmpty)
                          Text(
                            '${widget.exerciseName} — ${widget.weightKg % 1 == 0 ? widget.weightKg.toInt() : widget.weightKg.toStringAsFixed(1)} кг',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Значок дроп-сета ────────────────────────────────────────────────────────

class _DropSetBadge extends StatelessWidget {
  const _DropSetBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B00).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF6B00).withValues(alpha: 0.4)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_down, size: 14, color: Color(0xFFFF6B00)),
          SizedBox(width: 4),
          Text(
            'Дроп-сет — без отдыха между подходами',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFFFF6B00),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Разделитель дроп-сета ────────────────────────────────────────────────────

class _DropSetDivider extends StatelessWidget {
  const _DropSetDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const SizedBox(width: 44),
          const Icon(Icons.arrow_downward, size: 14, color: Color(0xFFFF6B00)),
          const SizedBox(width: 4),
          Text(
            'Снизьте вес',
            style: TextStyle(
              fontSize: 11,
              color: const Color(0xFFFF6B00).withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Значок суперсета ─────────────────────────────────────────────────────────

class _SupersetBadge extends StatelessWidget {
  final List<WorkoutExercise> exercises;
  final int currentIndex;

  const _SupersetBadge({
    required this.exercises,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final group = exercises[currentIndex].supersetGroup!;

    // Build ordered list of unique groups to derive a letter
    final seenGroups = <int>[];
    for (final e in exercises) {
      if (e.supersetGroup != null && !seenGroups.contains(e.supersetGroup)) {
        seenGroups.add(e.supersetGroup!);
      }
    }
    final letter =
        String.fromCharCode('A'.codeUnitAt(0) + seenGroups.indexOf(group));

    // Count position within the group up to currentIndex
    int pos = 0;
    for (int i = 0; i <= currentIndex; i++) {
      if (exercises[i].supersetGroup == group) pos++;
    }
    final total =
        exercises.where((e) => e.supersetGroup == group).length;

    const colors = [
      AppColors.success,
      AppColors.warning,
      Color(0xFFFF453A),
      Color(0xFFBF5AF2),
    ];
    final color = colors[seenGroups.indexOf(group) % colors.length];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            'Суперсет $letter  ·  $pos / $total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Экран разминки / заминки ─────────────────────────────────────────────────

class _PhaseScreen extends StatelessWidget {
  final bool isWarmup;
  final int secondsLeft;
  final VoidCallback onSkip;
  final VoidCallback onExit;

  const _PhaseScreen({
    required this.isWarmup,
    required this.secondsLeft,
    required this.onSkip,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final m = secondsLeft ~/ 60;
    final s = secondsLeft % 60;
    final timeStr =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final label = isWarmup ? 'Разминка' : 'Заминка';
    final icon = isWarmup ? Icons.directions_walk : Icons.self_improvement;
    final skipLabel = isWarmup ? 'Пропустить разминку' : 'Пропустить заминку';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onExit,
        ),
        title: Text(label),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.accent),
            const SizedBox(height: 24),
            Text(
              label,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              timeStr,
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: 220,
              height: 52,
              child: ElevatedButton(
                onPressed: onSkip,
                child: Text(
                  skipLabel,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Экран отдыха ────────────────────────────────────────────────────────────

class _RestScreen extends StatelessWidget {
  final int seconds;
  final int targetSeconds;
  final VoidCallback onSkip;
  final VoidCallback onExit;
  final String? nextExerciseName;

  const _RestScreen({
    required this.seconds,
    required this.targetSeconds,
    required this.onSkip,
    required this.onExit,
    this.nextExerciseName,
  });

  @override
  Widget build(BuildContext context) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final timeStr =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final done = targetSeconds > 0 && seconds >= targetSeconds;
    final progress = targetSeconds > 0
        ? (seconds / targetSeconds).clamp(0.0, 1.0)
        : 0.0;

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
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: targetSeconds > 0 ? (1 - progress) : null,
                      strokeWidth: 8,
                      backgroundColor: AppColors.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        done ? AppColors.accent : AppColors.accent.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: done ? AppColors.accent : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (targetSeconds > 0)
              Text(
                done ? 'Можно продолжать!' : 'Цель: ${targetSeconds ~/ 60}:${(targetSeconds % 60).toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 14,
                  color: done ? AppColors.accent : AppColors.textSecondary,
                  fontWeight: done ? FontWeight.w600 : FontWeight.normal,
                ),
              )
            else
              const Text(
                'Отдых',
                style: TextStyle(fontSize: 20, color: AppColors.textSecondary),
              ),
            const SizedBox(height: 32),
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
            if (nextExerciseName != null) ...[
              const SizedBox(height: 32),
              const Text(
                'Следующее',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                nextExerciseName!,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Plate calculator sheet ───────────────────────────────────────────────────

class _PlateCalcSheet extends StatelessWidget {
  final double weightKg;
  final bool useKg;

  const _PlateCalcSheet({required this.weightKg, required this.useKg});

  static const _platesKg = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
  static const _platesLb = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];
  static const _barKg = 20.0;
  static const _barLb = 45.0;

  List<double> _calcPlates(double totalWeight, double bar, List<double> plates) {
    final perSide = (totalWeight - bar) / 2;
    if (perSide <= 0) return [];
    double rem = perSide;
    final result = <double>[];
    for (final p in plates) {
      while (rem >= p - 0.001) {
        result.add(p);
        rem -= p;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final bar = useKg ? _barKg : _barLb;
    final plates = useKg ? _platesKg : _platesLb;
    final unit = useKg ? 'кг' : 'лб';
    final display = useKg ? weightKg : weightKg * 2.20462;
    final perSide = _calcPlates(display, bar, plates);
    final displayStr = display % 1 == 0 ? display.toInt().toString() : display.toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fitness_center, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Блины для $displayStr $unit',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Гриф: $bar $unit · по одной стороне',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (perSide.isEmpty)
            Text(
              display <= bar
                  ? 'Только гриф ($bar $unit)'
                  : 'Не удалось подобрать блины',
              style: const TextStyle(color: AppColors.textSecondary),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: perSide.map((p) {
                final label = p % 1 == 0 ? p.toInt().toString() : p.toStringAsFixed(2);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '$label $unit',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
