import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, SystemSound, SystemSoundType;
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
import 'package:sportwai/services/recsys_service.dart';
import 'package:sportwai/services/body_metrics_service.dart';
import 'package:sportwai/services/calorie_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/notification_service.dart';
import 'package:sportwai/services/exercise_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/user_state_service.dart';
import 'package:sportwai/services/workout_service.dart';
import 'package:sportwai/services/gamification_service.dart';
import 'package:sportwai/utils/twemoji.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sportwai/services/image_cache_manager.dart';
import 'package:confetti/confetti.dart';

enum _SessionPhase { warmup, exercise, cooldown }

// ─── Локальная модель одного подхода ────────────────────────────────────────

class _SetData {
  int reps;
  int repsTarget;
  int? rpe;
  bool completed;
  bool isWarmup;

  _SetData(
      {required this.reps,
      required this.repsTarget,
      this.rpe,
      this.completed = false,
      this.isWarmup = false});

  _SetData copyWith(
          {int? reps,
          int? repsTarget,
          int? rpe,
          bool? completed,
          bool? isWarmup}) =>
      _SetData(
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
  Map<String, double> _personalBests1RM = {};
  String? _userGoal;
  double _rpeCalibrationOffset = 0.0;
  Map<String, Map<String, dynamic>> _lastSets = {};
  final Map<String, int> _avgRestByExercise = {};
  double? _userWeightKg;
  int _completedSetsBefore = 0;
  int _totalExpectedSets = 0;
  int _currentExerciseIndex = 0;
  bool _loading = true;
  bool _loadError = false;
  _SessionPhase _phase = _SessionPhase.exercise;
  int _warmupMinutes = 0;
  int _cooldownMinutes = 0;
  int _sessionCycleWeek = 1;
  int _phaseSecondsLeft = 0;
  Timer? _phaseTimer;
  bool _resting = false;
  int _restSeconds = 0;
  int _targetRestSeconds = 0;
  Timer? _restTimer;
  bool _goToNextAfterRest = false;
  DateTime? _restStartedAt;
  DateTime? _pausedAt;
  DateTime? _currentSetStartedAt; // when the current set began (rest ended)
  int _lastRestSeconds = 0;
  int? _lastCompletedSetIndex;

  bool _deloadActive = false;
  Set<String> _fatiguedCategories = {}; // categories trained < 48h ago
  bool _fatigueBannerDismissed = false;

  // Energy / intra-session fatigue RecSys
  Map<String, dynamic>? _todayWellness;

  /// Inter-session energy state loaded at session start (from DB checkpoint).
  EnergyState? _sessionEnergyState;

  /// Running minimum reserve across all muscle groups — saved as energy_end on complete.
  double _sessionEnergyEnd = 100.0;
  // exerciseId → {category, sets[]} accumulated this session
  final Map<String, Map<String, dynamic>> _sessionHistory = {};
  FatigueRec? _intraFatigueRec;
  bool _intraFatigueDismissed = false;

  List<_SetData> _sets = [];
  List<TextEditingController> _weightControllers = [];
  // Comparison result per set index: 1 = better, 0 = same, -1 = worse, null = no data
  final Map<int, int?> _setComparisons = {};
  final Map<String, Map<int, double>> _sessionWeeklyWeights = {};
  final Map<String, Map<int, double>> _sessionDropSetWeeklyWeights = {};
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

  Future<T> _optionalLoad<T>(
    String label,
    Future<T> future,
    T fallback, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      return await future.timeout(timeout);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('optional session load failed ($label): $e\n$st');
      }
      return fallback;
    }
  }

  double? _asDouble(Object? value) => (value as num?)?.toDouble();

  int? _asInt(Object? value) => (value as num?)?.toInt();

  String _formatWeightForInput(double weightKg) {
    final useKg = ref.read(useKgProvider);
    final displayWeight = useKg ? weightKg : weightKg * 2.20462;
    return displayWeight.toStringAsFixed(displayWeight % 1 == 0 ? 0 : 1);
  }

  void _prefillCurrentWeightFromLast(WorkoutExercise we) {
    if (_weightControllers.isEmpty) return;
    if (_sets.any((set) => set.completed)) return;
    if (_weightControllers.any((controller) => controller.text.isNotEmpty)) {
      return;
    }

    final lastWeight = _asDouble(_lastSets[we.exerciseId]?['weight']);
    if (lastWeight == null) return;
    final prefillWeight = _deloadActive ? lastWeight * 0.6 : lastWeight;
    _weightControllers.first.text = _formatWeightForInput(prefillWeight);
  }

  void _applyLastSets(Map<String, Map<String, dynamic>> lastSets) {
    if (!mounted || lastSets.isEmpty) return;
    final current = _currentExercise;
    setState(() {
      _lastSets = lastSets;
      if (current != null) {
        _prefillCurrentWeightFromLast(current);
      }
    });
  }

  String? _lastPerformanceText(WorkoutExercise we) {
    final last = _lastSets[we.exerciseId];
    if (last == null || last.isEmpty) return null;
    final weightKg = _asDouble(last['weight']);
    final reps = _asInt(last['reps']);
    if ((weightKg == null || weightKg <= 0) && (reps == null || reps <= 0)) {
      return null;
    }

    final useKg = ref.read(useKgProvider);
    final unit = useKg ? 'кг' : 'лб';
    final parts = <String>[];
    if (weightKg != null && weightKg > 0) {
      final displayWeight = useKg ? weightKg : weightKg * 2.20462;
      parts.add(
        '${displayWeight.toStringAsFixed(displayWeight % 1 == 0 ? 0 : 1)} $unit',
      );
    }
    if (reps != null && reps > 0) {
      parts.add('$reps повт.');
    }
    return parts.isEmpty ? null : 'Прошлый раз: ${parts.join(' × ')}';
  }

  Future<void> _loadSession() async {
    if (mounted) {
      setState(() {
        _loadError = false;
        _loading = true;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final deload = prefs.getBool('deload_active') ?? false;
      if (mounted) setState(() => _deloadActive = deload);

      final activeSession = ref.read(activeSessionProvider);
      var workoutId = activeSession.sessionId == widget.sessionId
          ? activeSession.workoutId
          : null;
      if (workoutId == null) {
        final sessionRes = await Supabase.instance.client
            .from('training_sessions')
            .select('workout_id')
            .eq('id', widget.sessionId)
            .single()
            .timeout(const Duration(seconds: 5));
        workoutId = sessionRes['workout_id'] as String;
      }

      // Phase 1: load only the data required to render the workout.
      final workoutFuture = Supabase.instance.client
          .from('workouts')
          .select('warmup_minutes, cooldown_minutes, cycle_weeks, created_at')
          .eq('id', workoutId)
          .single()
          .timeout(const Duration(seconds: 5));
      final exercisesFuture = TrainingService.getWorkoutExercisesForToday(
        workoutId,
      ).timeout(const Duration(seconds: 5));
      final workoutRes2 = await workoutFuture;
      final ex = await exercisesFuture;

      final warmupMins = workoutRes2['warmup_minutes'] as int? ?? 0;
      final cooldownMins = workoutRes2['cooldown_minutes'] as int? ?? 0;
      final cycleWeek = _cycleWeekFromWorkoutRow(workoutRes2);

      final savedIdx = ex.isNotEmpty
          ? ((await SharedPreferences.getInstance())
                      .getInt('session_ex_idx_${widget.sessionId}') ??
                  0)
              .clamp(0, ex.length - 1)
          : 0;

      if (mounted) {
        setState(() {
          _exercises = ex;
          _totalExpectedSets = ex.fold(0, (sum, e) => sum + e.sets);
          _warmupMinutes = warmupMins;
          _cooldownMinutes = cooldownMins;
          _sessionCycleWeek = cycleWeek;
          _loading = false;
          if (ex.isNotEmpty) {
            _currentExerciseIndex = savedIdx;
            _completedSetsBefore =
                ex.take(savedIdx).fold(0, (s, e) => s + e.sets);
            _initExercise(ex[savedIdx]);
          }
          if (_warmupMinutes > 0) {
            _phase = _SessionPhase.warmup;
            _phaseSecondsLeft = _warmupMinutes * 60;
          }
        });
        if (_warmupMinutes > 0) {
          _startPhaseTimer();
        }
        if (_exercises.isNotEmpty) {
          await _maybeRestoreDraft(_exercises[_currentExerciseIndex]);
        }

        _loadSessionEnhancements(ex);
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('_loadSession error: $e\n$st');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  void _loadSessionEnhancements(List<WorkoutExercise> ex) {
    final exerciseIds = ex.map((e) => e.exerciseId).toList();
    final topRepsMap = <String, int>{};
    for (final e in ex) {
      final top = _parseTopReps(e.repsRange);
      if (top != null) topRepsMap[e.exerciseId] = top;
    }

    final personalBestsFuture = _optionalLoad(
      'personal bests',
      TrainingService.getPersonalBestsForExercises(exerciseIds),
      <String, double>{},
    );
    final lastSetsFuture = _optionalLoad(
      'last sets',
      AnalyticsService.getLastSetsForExercises(exerciseIds),
      <String, Map<String, dynamic>>{},
    );
    final userMetricsFuture = _optionalLoad<Map<String, dynamic>?>(
      'user metrics',
      BodyMetricsService.getLatest(),
      null,
    );
    final userStateFuture = _optionalLoad(
      'user state',
      UserStateService.computeUserState(),
      const UserState(energyState: EnergyState(reserve: 100)),
    );
    final best1RMFuture = _optionalLoad(
      '1rm',
      AnalyticsService.getPersonalBest1RMForExercises(exerciseIds),
      <String, double>{},
    );
    final autoProgressFuture = _optionalLoad(
      'auto progress',
      AnalyticsService.getConsecutiveFullRepsExercises(
        exerciseIds,
        topRepsMap,
      ),
      <String>{},
    );
    final recentCatsFuture = _optionalLoad(
      'recent categories',
      AnalyticsService.getRecentlyTrainedCategories(),
      <String>{},
    );

    unawaited(lastSetsFuture.then(_applyLastSets));
    unawaited(() async {
      final pbs = await personalBestsFuture;
      final userMetrics = await userMetricsFuture;
      final userState = await userStateFuture;
      final personalBests1RM = await best1RMFuture;
      final autoProgress = await autoProgressFuture;
      final lastSets = await lastSetsFuture;

      final recentCats = await recentCatsFuture;
      final workoutCats =
          ex.map((e) => e.exercise?.category).whereType<String>().toSet();
      final fatigued = recentCats.intersection(workoutCats)..remove('cardio');

      if (!mounted) return;
      setState(() {
        _personalBests = pbs;
        _personalBests1RM = personalBests1RM;
        _lastSets = lastSets;
        _autoProgressSuggestions = autoProgress;
        _fatiguedCategories = fatigued;
        _todayWellness = userState.todayWellness;
        _sessionEnergyState = userState.energyState;
        _sessionEnergyEnd = userState.energyState.reserve;
        _userGoal = userState.userGoal;
        _rpeCalibrationOffset = userState.rpeCalibrationOffset;
        _userWeightKg = (userMetrics?['weight_kg'] as num?)?.toDouble();
      });

      final energyState = userState.energyState;
      for (final we in ex) {
        final isDb = we.exercise?.equipmentType == 'dumbbell';
        final dbIncrement = isDb ? ref.read(dumbbellIncrementProvider) : 2.5;
        final rec = evaluateProgression(
          lastSets[we.exerciseId],
          consecutiveFullReps: autoProgress.contains(we.exerciseId) ? 3 : 0,
          topRepsInRange: _parseTopReps(we.repsRange),
          weightIncrement: dbIncrement,
          energyState: energyState,
          personalBest1RMKg: personalBests1RM[we.exerciseId],
          userGoal: _userGoal,
          rpeCalibrationOffset: _rpeCalibrationOffset,
          isBodyweight: we.exercise?.equipmentType == 'bodyweight',
        );
        if (rec != null && rec.direction == ProgressionDirection.increase) {
          EventLogger.autoProgressSuggestionShown(
            exerciseId: we.exerciseId,
            isStrong: autoProgress.contains(we.exerciseId),
          );
        }
      }
    }());

    if (mounted) {
      // Load avg rest seconds per exercise (non-blocking — used only as a UI hint)
      Future.wait(ex.map(
          (e) => AnalyticsService.getAvgRestSeconds(e.exerciseId).then((v) {
                if (v != null && mounted) {
                  setState(() => _avgRestByExercise[e.exerciseId] = v);
                }
              }).catchError((_) {}))).ignore();
    }
  }

  void _initExercise(WorkoutExercise we) {
    final defaultReps = _parseDefaultReps(we.repsRange);
    final lastWeight = _asDouble(_lastSets[we.exerciseId]?['weight']);
    final prefillWeight =
        lastWeight != null && _deloadActive ? lastWeight * 0.6 : lastWeight;
    final lastWeightText =
        prefillWeight != null ? _formatWeightForInput(prefillWeight) : '';
    for (final c in _weightControllers) {
      c.dispose();
    }
    _lastCompletedSetIndex = null;
    _currentSetStartedAt = DateTime.now().toUtc();
    _weightControllers = List.generate(
        we.sets,
        (i) => TextEditingController(text: i == 0 ? lastWeightText : '')
          ..addListener(_saveDraft));
    _sets = List.generate(
        we.sets, (_) => _SetData(reps: defaultReps, repsTarget: defaultReps));
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

  int _cycleWeekFromWorkoutRow(Map<String, dynamic> row) {
    final cycleWeeks = row['cycle_weeks'] as int? ?? 1;
    final totalWeeks = cycleWeeks <= 0 ? 1 : cycleWeeks;
    final createdRaw = row['created_at'] as String?;
    if (createdRaw == null) {
      return 1;
    }
    final createdAt = DateTime.tryParse(createdRaw);
    if (createdAt == null) {
      return 1;
    }
    final startDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final elapsedDays = today.difference(startDate).inDays;
    final week = elapsedDays < 0 ? 1 : (elapsedDays ~/ 7) + 1;
    if (week < 1) {
      return 1;
    }
    if (week > totalWeeks) {
      return totalWeeks;
    }
    return week;
  }

  Future<void> _recordWeeklyWeightFromSession(
    WorkoutExercise we,
    double weightKg, {
    required bool isDropSetWeight,
  }) async {
    final storedWeights = isDropSetWeight
        ? _sessionDropSetWeeklyWeights[we.id] ?? we.dropSetWeeklyTargetWeights
        : _sessionWeeklyWeights[we.id] ?? we.weeklyTargetWeights;
    final currentWeight = storedWeights[_sessionCycleWeek];
    if (currentWeight != null && weightKg <= currentWeight) {
      return;
    }

    final nextWeights = Map<int, double>.from(storedWeights)
      ..[_sessionCycleWeek] = weightKg;
    if (isDropSetWeight) {
      _sessionDropSetWeeklyWeights[we.id] = nextWeights;
    } else {
      _sessionWeeklyWeights[we.id] = nextWeights;
    }
    try {
      if (isDropSetWeight) {
        await WorkoutService.updateWorkoutExercise(
          we.id,
          dropSetWeeklyTargetWeights: nextWeights,
        );
      } else {
        await WorkoutService.updateWorkoutExercise(
          we.id,
          weeklyTargetWeights: nextWeights,
        );
      }
    } catch (_) {
      // Set history is already saved; weekly summary can be retried next set.
    }
  }

  /// Returns the top (max) reps from a range like "8-12" → 12, "5" → 5.
  /// Returns null for cardio/time-based ranges (e.g. "15 мин").
  int? _parseTopReps(String range) {
    final parts = range.split('-');
    final last = parts.last.trim().split(' ')[0];
    return int.tryParse(last);
  }

  Widget _buildProgressionChip({
    required ProgressionRec progRec,
    required double currentWeightKg,
    required String exerciseId,
    required bool useKg,
    required String unit,
  }) {
    final (color, icon) = switch (progRec.direction) {
      ProgressionDirection.increase => (AppColors.success, Icons.trending_up),
      ProgressionDirection.maintain => (
          const Color(0xFFFF9F0A),
          Icons.trending_flat
        ),
      ProgressionDirection.decrease => (AppColors.error, Icons.trending_down),
    };

    final suggestedKg = progRec.suggestedWeightKg;
    final isStrong = progRec.direction == ProgressionDirection.increase &&
        _autoProgressSuggestions.contains(exerciseId);

    void applyWeight() {
      if (suggestedKg == null) return;
      final displaySuggested = useKg ? suggestedKg : suggestedKg * 2.20462;
      for (final c in _weightControllers) {
        final cur = double.tryParse(c.text.replaceAll(',', '.'));
        if (c.text.isEmpty || cur == currentWeightKg) {
          c.text = displaySuggested
              .toStringAsFixed(displaySuggested % 1 == 0 ? 0 : 1);
        }
      }
      EventLogger.autoProgressAccepted(
        exerciseId: exerciseId,
        suggestedWeightKg: suggestedKg,
        isStrong: isStrong,
      );
    }

    final chip = Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: suggestedKg != null ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              progRec.message,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight:
                    suggestedKg != null ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (suggestedKg != null) ...[
            const SizedBox(width: 6),
            Text(
              '→ ${(useKg ? suggestedKg : suggestedKg * 2.20462).toStringAsFixed(1)} $unit',
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );

    if (suggestedKg != null) {
      return GestureDetector(onTap: applyWeight, child: chip);
    }
    return chip;
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
    final lastWeight = _asDouble(_lastSets[we.exerciseId]?['weight']);
    if (lastWeight != null && weightKg > 0) {
      final diff = weightKg - lastWeight;
      _setComparisons[index] = diff > 0.001 ? 1 : (diff < -0.001 ? -1 : 0);
    } else {
      _setComparisons[index] = null;
    }

    _lastCompletedSetIndex = index;

    // Optimistic update — instant visual feedback
    setState(() {
      _sets[index] = setData.copyWith(completed: true);
      if (we.isDropSet && index + 1 < _sets.length) {
        _sets[index + 1] = _sets[index + 1].copyWith(
          reps: setData.reps,
          repsTarget: setData.repsTarget,
        );
        // Drop-set: auto-fill next set with half the current weight.
        if (weightKg > 0) {
          final half = weightKg / 2;
          final useKgLocal = ref.read(useKgProvider);
          final displayHalf = useKgLocal ? half : half * 2.20462;
          _weightControllers[index + 1].text =
              displayHalf.toStringAsFixed(displayHalf % 1 == 0 ? 0 : 1);
        }
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
        final inSameSuperset =
            we.supersetGroup != null && we.supersetGroup == next.supersetGroup;
        if (inSameSuperset) {
          // No rest inside a superset — advance immediately
          if (mounted) _advanceExercise();
        } else {
          _startRest(we.restSeconds, goToNext: true);
        }
      }
    }

    // Route fields by input mode. Weighted path is unchanged from before.
    final mode = we.exercise?.effectiveInputMode ?? ExerciseInputMode.weighted;
    final isCardio = mode == ExerciseInputMode.cardio;
    final isBodyweight = mode == ExerciseInputMode.bodyweight;

    // For cardio, `setData.reps` holds minutes (1..300) — convert to seconds.
    final durationSeconds = isCardio ? setData.reps * 60 : null;
    final weightToSave =
        (isCardio || isBodyweight) ? null : (weightKg > 0 ? weightKg : null);
    final repsToSave = isCardio ? null : setData.reps;
    final rpeToSave = isCardio ? null : setData.rpe;

    // Estimate kcal for this set
    final kcalEstimated = (isCardio || setData.reps > 0)
        ? estimateSetKcal(
            category: we.exercise?.category ?? 'chest',
            reps: setData.reps,
            rpe: setData.rpe,
            userWeightKg: _userWeightKg,
            durationSecondsOverride: durationSeconds,
          )
        : null;

    // Save to DB in background; show retry snackbar on failure
    final setStartedAt = _currentSetStartedAt;
    _currentSetStartedAt = null; // consumed
    final saved = await TrainingService.saveSet(
      widget.sessionId,
      we.id,
      index + 1,
      weight: weightToSave,
      reps: repsToSave,
      repsTarget: setData.repsTarget,
      rpe: rpeToSave,
      restSeconds: restSecondsToSave,
      kcalEstimated: kcalEstimated,
      isWarmup: setData.isWarmup,
      startedAt: setStartedAt,
      durationSeconds: durationSeconds,
    );

    if (!saved && mounted) {
      final sessionId = widget.sessionId;
      final weId = we.id;
      final setNum = index + 1;
      final w = weightToSave;
      final r = repsToSave;
      final rpe = rpeToSave;
      final rest = restSecondsToSave;
      final warmup = setData.isWarmup;
      final dur = durationSeconds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Не удалось сохранить подход'),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => TrainingService.saveSet(
              sessionId,
              weId,
              setNum,
              weight: w,
              reps: r,
              rpe: rpe,
              restSeconds: rest,
              isWarmup: warmup,
              durationSeconds: dur,
            ),
          ),
        ),
      );
    }
    if (saved && weightToSave != null) {
      unawaited(_recordWeeklyWeightFromSession(
        we,
        weightToSave,
        isDropSetWeight: we.isDropSet && index > 0,
      ));
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
        GamificationService.award('personal_record', sourceId: exerciseId);
        _showPrBanner(we.exercise?.displayName ?? '', weightKg);
      }
    }
  }

  void _showRpeInfo(BuildContext context) {
    const levels = [
      ('1–2', 'Очень легко', 'Можно говорить полными предложениями'),
      ('3–4', 'Легко', 'Небольшое усилие, дыхание свободное'),
      ('5–6', 'Умеренно', 'Заметное усилие, но можно продолжать'),
      ('7–8', 'Тяжело', 'Трудно говорить, ещё 1–2 повтора в запасе'),
      ('9', 'Очень тяжело', 'Почти максимум, 1 повтор в запасе'),
      ('10', 'Максимум', 'Больше невозможно — полный отказ'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Шкала RPE (Rate of Perceived Exertion)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Субъективная оценка нагрузки от 1 до 10',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ...levels.map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(l.$1,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accent)),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.$2,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            Text(l.$3,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlateCalc(double weightKg, {required bool useKg}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      useRootNavigator: true,
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
      _lastRestSeconds = DateTime.now().difference(_restStartedAt!).inSeconds;
      _restStartedAt = null;
    }
    // Pre-fill the next set from the just-completed one.
    if (!_goToNextAfterRest && _lastCompletedSetIndex != null) {
      final nextIdx = _lastCompletedSetIndex! + 1;
      if (nextIdx < _sets.length && !_sets[nextIdx].completed) {
        final previousSet = _sets[_lastCompletedSetIndex!];
        _sets[nextIdx] = _sets[nextIdx].copyWith(
          reps: previousSet.reps,
          repsTarget: previousSet.repsTarget,
        );
      }
      if (nextIdx < _weightControllers.length &&
          _weightControllers[nextIdx].text.isEmpty) {
        final prevWeight = _weightControllers[_lastCompletedSetIndex!].text;
        if (prevWeight.isNotEmpty) {
          _weightControllers[nextIdx].text = prevWeight;
        }
      }
    }
    _currentSetStartedAt = DateTime.now().toUtc();
    setState(() => _resting = false);
    _saveDraft();
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
      final current = _exercises[_currentExerciseIndex];
      final next = _exercises[nextIndex];
      _saveExerciseToHistory(current);
      final fatigue = _computeIntraFatigue(next);
      setState(() {
        _completedSetsBefore += _sets.length;
        _currentExerciseIndex = nextIndex;
        _intraFatigueRec = fatigue;
        _intraFatigueDismissed = false;
        _initExercise(next);
      });
      _saveExerciseIndex();
      _maybeRestoreDraft(next);
    }
  }

  void _previousExercise() {
    final prevIndex = _currentExerciseIndex - 1;
    if (prevIndex >= 0) {
      HapticFeedback.mediumImpact();
      final current = _exercises[_currentExerciseIndex];
      final prev = _exercises[prevIndex];
      _saveExerciseToHistory(current);
      final fatigue = _computeIntraFatigue(prev);
      setState(() {
        _completedSetsBefore =
            (_completedSetsBefore - prev.sets).clamp(0, _totalExpectedSets);
        _currentExerciseIndex = prevIndex;
        _intraFatigueRec = fatigue;
        _intraFatigueDismissed = false;
        _initExercise(prev);
      });
      _saveExerciseIndex();
      _maybeRestoreDraft(prev);
    }
  }

  /// Snapshot the current exercise's completed sets into [_sessionHistory].
  void _saveExerciseToHistory(WorkoutExercise we) {
    final category = we.exercise?.category;
    if (category == null) return;
    _sessionHistory[we.exerciseId] = {
      'category': category,
      'equipmentType': we.exercise?.equipmentType ?? 'other',
      'movementType': we.exercise?.effectiveMovementType ?? 'other',
      'inSuperset': we.supersetGroup != null,
      'sets': _sets
          .map((s) => {
                'isWarmup': s.isWarmup,
                'completed': s.completed,
                'rpe': s.rpe?.toDouble(),
              })
          .toList(),
    };
  }

  /// Runs [evaluateFatigue] for the exercise we're switching to.
  /// Also updates [_sessionEnergyEnd] (running minimum reserve across all
  /// muscle groups — persisted as energy_end checkpoint on session complete).
  FatigueRec? _computeIntraFatigue(WorkoutExercise we) {
    final category = we.exercise?.category;
    if (category == null || category == 'cardio') return null;
    final rec = evaluateFatigue(
      targetCategory: category,
      sessionHistory: _sessionHistory.values.toList(),
      initialState: _sessionEnergyState,
      wellness: _todayWellness,
    );
    if (rec != null && rec.reserve < _sessionEnergyEnd) {
      _sessionEnergyEnd = rec.reserve;
    }
    return rec;
  }

  // ─── Draft persistence (survives process kill) ───────────────────────────

  String _draftKey(String weId) => 'set_draft_${widget.sessionId}_$weId';
  String get _exerciseIdxKey => 'session_ex_idx_${widget.sessionId}';

  Future<void> _saveExerciseIndex() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_exerciseIdxKey, _currentExerciseIndex);
  }

  /// Persist current weights + reps for the active exercise to SharedPreferences.
  Future<void> _saveDraft() async {
    final we = _currentExercise;
    if (we == null) return;
    final data = List.generate(
        _sets.length,
        (i) => {
              'w': i < _weightControllers.length
                  ? _weightControllers[i].text
                  : '',
              'r': _sets[i].reps,
            });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey(we.id), jsonEncode(data));
  }

  /// Restore a saved draft into the already-initialised controllers/_sets.
  /// Triggers setState only when something actually changed.
  Future<void> _maybeRestoreDraft(WorkoutExercise we) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey(we.id));
    if (raw == null || !mounted) return;
    try {
      final data = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (data.length != _sets.length) return;
      var changed = false;
      for (var i = 0; i < data.length; i++) {
        final w = (data[i]['w'] as String?) ?? '';
        final r = (data[i]['r'] as int?) ?? _sets[i].reps;
        if (w.isNotEmpty && _weightControllers[i].text != w) {
          _weightControllers[i].text = w;
          changed = true;
        }
        if (_sets[i].reps != r) {
          _sets[i] = _sets[i].copyWith(reps: r);
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    } catch (_) {}
  }

  /// Remove all draft keys for this session (call on normal completion).
  Future<void> _clearAllDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_exerciseIdxKey);
    for (final we in _exercises) {
      await prefs.remove(_draftKey(we.id));
    }
  }

  void _addSet() {
    HapticFeedback.selectionClick();
    final defaultReps = _parseDefaultReps(_currentExercise!.repsRange);
    setState(() {
      _sets.add(_SetData(reps: defaultReps, repsTarget: defaultReps));
      _weightControllers.add(TextEditingController()..addListener(_saveDraft));
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
        builder: (_, sc) {
          var replaceQuery = '';
          return StatefulBuilder(
            builder: (ctx2, setInner) {
              final filtered = replaceQuery.isEmpty
                  ? exercises
                  : exercises.where((e) {
                      final q = replaceQuery.toLowerCase();
                      return e.name.toLowerCase().contains(q) ||
                          (e.nameRu?.toLowerCase().contains(q) ?? false);
                    }).toList();
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Заменить упражнение',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          autofocus: false,
                          onChanged: (v) =>
                              setInner(() => replaceQuery = v.trim()),
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Поиск упражнения...',
                            hintStyle: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 14),
                            prefixIcon: const Icon(Icons.search,
                                color: AppColors.textSecondary, size: 20),
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: sc,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final ex = filtered[i];
                        return ListTile(
                          title: Text(ex.displayName,
                              style: const TextStyle(
                                  color: AppColors.textPrimary)),
                          subtitle: Text(
                            Exercise.categoryDisplayName(ex.category),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                          onTap: () => Navigator.pop(ctx, ex),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
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
    final lastSets =
        await AnalyticsService.getLastSetsForExercises([picked.id]);
    if (mounted) {
      setState(() => _lastSets[picked.id] = lastSets[picked.id] ?? {});
    }
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
                  exerciseName: currentEx.exercise?.displayName ?? '?',
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
    await _clearAllDrafts();
    final sessionState = ref.read(activeSessionProvider);
    final durationSeconds =
        sessionState.isActive ? sessionState.elapsed.inSeconds : 0;
    EventLogger.workoutCompleted(
      sessionId: widget.sessionId,
      durationSeconds: durationSeconds,
      setsCount: _sets.where((s) => s.completed).length,
    );
    // Persist energy checkpoint so next session starts from correct reserve.
    AnalyticsService.saveEnergyEnd(widget.sessionId, _sessionEnergyEnd);
    // Invalidate cached stats so next screen open shows fresh numbers
    AnalyticsService.invalidateStatsCache();
    // Refresh weekly summary notification with updated stats (fire-and-forget)
    NotificationService.refreshWeeklySummary();
    // Check streak milestone (fire-and-forget)
    AnalyticsService.getCurrentStreak().then((streak) {
      const milestones = [7, 14, 30, 60, 100, 200, 365];
      if (milestones.contains(streak)) {
        EventLogger.streakMilestone(days: streak);
      }
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
              const Text('Не удалось загрузить тренировку',
                  textAlign: TextAlign.center),
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
                Icon(Icons.fitness_center_rounded,
                    size: 64,
                    color: AppColors.textSecondary.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                const Text(
                  'Нет упражнений',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Добавьте упражнения в эту тренировку',
                  style:
                      TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
      final nextEx =
          _goToNextAfterRest && _currentExerciseIndex + 1 < _exercises.length
              ? _exercises[_currentExerciseIndex + 1].exercise
              : null;
      return _RestScreen(
        seconds: _restSeconds,
        targetSeconds: _targetRestSeconds,
        onSkip: _skipRest,
        onExit: _confirmExit,
        onAdjust: (delta) => setState(() {
          _targetRestSeconds = (_targetRestSeconds + delta).clamp(0, 600);
        }),
        nextExerciseName: nextEx?.displayName,
        nextExerciseGifUrl: nextEx?.gifUrl,
        avgRestSeconds: _avgRestByExercise[_currentExercise?.exerciseId ?? ''],
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
                we.exercise?.displayName ?? '',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${_currentExerciseIndex + 1} / ${_exercises.length}',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w400),
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
            preferredSize: const Size.fromHeight(6),
            child: SizedBox(
              height: 6,
              child: CustomPaint(
                painter: _NeonProgressPainter(
                  progress: _progressValue,
                  color: AppColors.success,
                  background: AppColors.surface,
                ),
              ),
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
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: SingleChildScrollView(
                    key: ValueKey(_currentExerciseIndex),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Fatigue warning banner
                        if (_fatiguedCategories.isNotEmpty &&
                            !_fatigueBannerDismissed) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color:
                                      AppColors.error.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: AppColors.error, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Эти мышцы тренировались < 48 ч назад: '
                                    '${_fatiguedCategories.map((c) => Exercise.categoryDisplayName(c)).join(', ')}. '
                                    'Риск перетренированности.',
                                    style: const TextStyle(
                                        color: AppColors.error, fontSize: 12),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(
                                      () => _fatigueBannerDismissed = true),
                                  child: const Icon(Icons.close,
                                      size: 16, color: AppColors.error),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        // Intra-session fatigue RecSys banner
                        if (_intraFatigueRec != null &&
                            !_intraFatigueDismissed) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color:
                                      AppColors.warning.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _intraFatigueRec!.level == FatigueLevel.high
                                      ? Icons.local_fire_department_rounded
                                      : Icons.battery_4_bar_rounded,
                                  color: AppColors.warning,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _intraFatigueRec!.message,
                                    style: const TextStyle(
                                        color: AppColors.warning, fontSize: 12),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(
                                      () => _intraFatigueDismissed = true),
                                  child: const Icon(Icons.close,
                                      size: 16, color: AppColors.warning),
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
                                  color:
                                      AppColors.warning.withValues(alpha: 0.5)),
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
                            we.exercise?.displayName ?? '?',
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
                        Builder(builder: (_) {
                          final previous = _lastPerformanceText(we);
                          if (previous == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              previous,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }),
                        // Exercise GIF
                        if (we.exercise?.gifUrl != null) ...[
                          const SizedBox(height: 12),
                          _ExerciseMedia(
                            url: we.exercise!.gifUrl!,
                            height: 180,
                            width: double.infinity,
                          ),
                        ],
                        if (_lastSets[we.exerciseId] != null) ...[
                          const SizedBox(height: 2),
                          Builder(builder: (_) {
                            final last = _lastSets[we.exerciseId]!;
                            final w = _asDouble(last['weight']);
                            if (w == null) return const SizedBox.shrink();
                            final useKg = ref.read(useKgProvider);
                            final unit = useKg ? 'кг' : 'лб';
                            // ── Unified RecSys progression chip ──────────────
                            final isDumbbell =
                                we.exercise?.equipmentType == 'dumbbell';
                            final increment = isDumbbell
                                ? ref.read(dumbbellIncrementProvider)
                                : 2.5;
                            // Use muscle-specific reserve if available, else session-start state.
                            final energyForProg = _intraFatigueRec != null
                                ? EnergyState(
                                    reserve: _intraFatigueRec!.reserve)
                                : _sessionEnergyState;
                            final progRec = evaluateProgression(
                              _lastSets[we.exerciseId],
                              consecutiveFullReps: _autoProgressSuggestions
                                      .contains(we.exerciseId)
                                  ? 3
                                  : 0,
                              topRepsInRange: _parseTopReps(we.repsRange),
                              weightIncrement: increment,
                              energyState: energyForProg,
                              personalBest1RMKg:
                                  _personalBests1RM[we.exerciseId],
                              userGoal: _userGoal,
                              rpeCalibrationOffset: _rpeCalibrationOffset,
                              isBodyweight:
                                  we.exercise?.equipmentType == 'bodyweight',
                            );
                            if (progRec == null) {
                              return const SizedBox.shrink();
                            }
                            return _buildProgressionChip(
                              progRec: progRec,
                              currentWeightKg: w,
                              exerciseId: we.exerciseId,
                              useKg: useKg,
                              unit: unit,
                            );
                          }),
                        ],
                        const SizedBox(height: 20),

                        // Шапка столбцов
                        Padding(
                          padding: const EdgeInsets.only(left: 32, right: 44),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 48,
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
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _showRpeInfo(context),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('RPE',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                              letterSpacing: 0.5)),
                                      SizedBox(width: 2),
                                      Icon(Icons.info_outline,
                                          size: 11,
                                          color: AppColors.textSecondary),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Plate calculator chip
                        Builder(builder: (_) {
                          final activeCtrl = activeIndex >= 0 &&
                                  activeIndex < _weightControllers.length
                              ? _weightControllers[activeIndex]
                              : null;
                          final weightVal = double.tryParse(
                              activeCtrl?.text.replaceAll(',', '.') ?? '');
                          final useKg = ref.read(useKgProvider);
                          if (weightVal == null ||
                              weightVal <= 0 ||
                              we.exercise?.category == 'cardio') {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GestureDetector(
                              onTap: () =>
                                  _showPlateCalc(weightVal, useKg: useKg),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.accent
                                          .withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.fitness_center,
                                        size: 14, color: AppColors.accent),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Блины для ${useKg ? weightVal.toStringAsFixed(1) : (weightVal * 2.20462).toStringAsFixed(1)} ${useKg ? "кг" : "лб"}',
                                      style: const TextStyle(
                                          color: AppColors.accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),

                        // Блоки подходов
                        ...List.generate(_sets.length, (i) {
                          final canComplete =
                              !_sets[i].completed && i == activeIndex;
                          return Column(
                            children: [
                              if (we.isDropSet && i > 0)
                                const _DropSetDivider(),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Dismissible(
                                  key: ValueKey('set_$i'),
                                  direction: canComplete
                                      ? DismissDirection.startToEnd
                                      : DismissDirection.none,
                                  confirmDismiss: (_) async {
                                    _completeSet(i);
                                    return false; // не удалять из списка
                                  },
                                  background: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.success
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 20),
                                    child: const Icon(
                                        Icons.check_circle_outline,
                                        color: AppColors.success,
                                        size: 28),
                                  ),
                                  child: _SetBlock(
                                    index: i,
                                    data: _sets[i],
                                    isActive:
                                        i == activeIndex && !_sets[i].completed,
                                    weightController: _weightControllers[i],
                                    comparison: _setComparisons[i],
                                    inputMode:
                                        we.exercise?.effectiveInputMode ??
                                            ExerciseInputMode.weighted,
                                    onRepsChanged: (v) {
                                      setState(() => _sets[i] =
                                          _sets[i].copyWith(reps: v));
                                      _saveDraft();
                                    },
                                    onRpeChanged: (v) =>
                                        setState(() => _sets[i].rpe = v),
                                    onComplete: canComplete
                                        ? () => _completeSet(i)
                                        : null,
                                    onWarmupToggle: !_sets[i].completed
                                        ? () => setState(() => _sets[i] =
                                            _sets[i].copyWith(
                                                isWarmup: !_sets[i].isWarmup))
                                        : null,
                                  ),
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

              // Навигация между упражнениями
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    if (_currentExerciseIndex > 0)
                      Expanded(
                        flex: 1,
                        child: OutlinedButton.icon(
                          onPressed: _previousExercise,
                          icon: const Icon(Icons.chevron_left, size: 18),
                          label: const Text('Назад'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    if (_currentExerciseIndex > 0 &&
                        _allSetsCompleted &&
                        _currentExerciseIndex < _exercises.length - 1)
                      const SizedBox(width: 12),
                    if (_allSetsCompleted &&
                        _currentExerciseIndex < _exercises.length - 1)
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _advanceExercise,
                          child: const Text('Следующее упражнение'),
                        ),
                      ),
                  ],
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

  /// Input mode — defaults to `weighted` so existing call sites keep original UI.
  final ExerciseInputMode inputMode;

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
    this.inputMode = ExerciseInputMode.weighted,
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
            : isActive
                ? AppColors.success.withValues(alpha: 0.07)
                : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: warmup
            ? Border.all(
                color: const Color(0xFFB8690A).withValues(alpha: 0.35),
                width: 1)
            : isActive
                ? Border.all(color: AppColors.success, width: 1.5)
                : done
                    ? Border.all(
                        color: AppColors.success.withValues(alpha: 0.25),
                        width: 1)
                    : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Opacity(
        opacity: done ? 0.55 : 1.0,
        child: Row(
          children: [
            _SetBadge(
                number: index + 1,
                done: done,
                active: isActive && !warmup,
                isWarmup: warmup),
            const SizedBox(width: 4),
            // Поле ввода веса — только для weighted. Для bodyweight/cardio скрыто.
            if (inputMode == ExerciseInputMode.weighted) ...[
              SizedBox(
                width: 48,
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
                    color:
                        done ? AppColors.textSecondary : AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '—',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                      borderSide:
                          const BorderSide(color: AppColors.accent, width: 1.2),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: _Stepper(
                value: data.reps,
                min: 1,
                max: inputMode == ExerciseInputMode.cardio ? 300 : 999,
                enabled: !done,
                suffix: inputMode == ExerciseInputMode.cardio ? 'мин' : null,
                onChanged: onRepsChanged,
              ),
            ),
            const SizedBox(width: 4),
            // RPE — для weighted и bodyweight. Для cardio скрыт.
            if (inputMode != ExerciseInputMode.cardio) ...[
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
              const SizedBox(width: 2),
            ],
            if (!done)
              GestureDetector(
                onTap: onWarmupToggle,
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: Icon(
                    warmup
                        ? Icons.local_fire_department
                        : Icons.local_fire_department_outlined,
                    size: 16,
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
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? AppColors.success : AppColors.surface,
                  ),
                  child: Icon(Icons.check,
                      size: 18,
                      color: isActive ? Colors.white : AppColors.textSecondary),
                ),
              )
            else
              SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: comparison == null
                      ? const Icon(Icons.check_circle,
                          color: AppColors.success, size: 22)
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
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? (isWarmup ? warmupColor : AppColors.success)
            : active
                ? (isWarmup
                    ? warmupColor.withValues(alpha: 0.18)
                    : AppColors.success.withValues(alpha: 0.15))
                : AppColors.surface,
      ),
      alignment: Alignment.center,
      child: done
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : isWarmup
              ? const Icon(Icons.local_fire_department,
                  size: 14, color: warmupColor)
              : Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: active ? AppColors.success : AppColors.textSecondary,
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
  final String? suffix;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    this.zeroLabel,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final display = (value == 0 && zeroLabel != null) ? zeroLabel! : '$value';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MiniBtn(
            icon: Icons.remove,
            enabled: enabled && value > min,
            onTap: () => onChanged(value - 1)),
        const SizedBox(width: 2),
        SizedBox(
          width: suffix == null ? 22 : 42,
          child: Text.rich(
            TextSpan(
              text: display,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color:
                    enabled ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              children: suffix == null
                  ? null
                  : [
                      TextSpan(
                        text: ' $suffix',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 2),
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
        width: 22,
        height: 22,
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

class _ExerciseMedia extends StatefulWidget {
  final String url;
  final double height;
  final double width;

  const _ExerciseMedia({
    required this.url,
    required this.height,
    required this.width,
  });

  @override
  State<_ExerciseMedia> createState() => _ExerciseMediaState();
}

class _ExerciseMediaState extends State<_ExerciseMedia> {
  Timer? _timer;
  bool _loaded = false;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _startTimeout();
  }

  @override
  void didUpdateWidget(covariant _ExerciseMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loaded = false;
      _timedOut = false;
      _startTimeout();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimeout() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_loaded) {
        setState(() => _timedOut = true);
      }
    });
  }

  void _markLoaded() {
    if (_loaded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loaded) return;
      _timer?.cancel();
      setState(() => _loaded = true);
    });
  }

  Widget _fallback() {
    return Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 30,
          color: AppColors.textSecondary.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_timedOut) return _fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        cacheManager: AppImageCacheManager.instance,
        imageUrl: widget.url,
        height: widget.height,
        width: widget.width,
        fit: BoxFit.contain,
        imageBuilder: (context, imageProvider) {
          _markLoaded();
          return Image(
            image: imageProvider,
            height: widget.height,
            width: widget.width,
            fit: BoxFit.contain,
          );
        },
        placeholder: (_, __) => Container(
          height: widget.height,
          width: widget.width,
          color: AppColors.surface,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (_, __, ___) => _fallback(),
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
  late final ConfettiController _confetti;

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

    _confetti =
        ConfettiController(duration: const Duration(milliseconds: 1800));
    _ctrl.forward();
    _confetti.play();
    Future.delayed(const Duration(milliseconds: 2800), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse(from: 1.0);
    widget.onDismiss();
  }

  @override
  void dispose() {
    _confetti.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Positioned(
      top: safeTop,
      left: 0,
      right: 0,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          // Конфетти из центра экрана
          ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            numberOfParticles: 28,
            gravity: 0.35,
            particleDrag: 0.05,
            emissionFrequency: 0.06,
            colors: const [
              AppColors.success,
              Color(0xFFFFD60A),
              AppColors.accent,
              Color(0xFFFF9F0A),
              Color(0xFFFF453A),
              Colors.white,
            ],
          ),
          // Баннер
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _opacity,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.12),
                          blurRadius: 6,
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.8),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.35),
                          blurRadius: 52,
                          spreadRadius: 6,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Twemoji('🏆', size: 32),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Личный рекорд!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                              if (widget.exerciseName.isNotEmpty)
                                Text(
                                  '${widget.exerciseName} · ${widget.weightKg % 1 == 0 ? widget.weightKg.toInt() : widget.weightKg.toStringAsFixed(1)} кг',
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
          ),
        ],
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
        border:
            Border.all(color: const Color(0xFFFF6B00).withValues(alpha: 0.4)),
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
    final total = exercises.where((e) => e.supersetGroup == group).length;

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
  final ValueChanged<int> onAdjust;
  final String? nextExerciseName;
  final String? nextExerciseGifUrl;

  /// Empirical average rest duration from `performed_at` history (seconds).
  final int? avgRestSeconds;

  const _RestScreen({
    required this.seconds,
    required this.targetSeconds,
    required this.onSkip,
    required this.onExit,
    required this.onAdjust,
    this.nextExerciseName,
    this.nextExerciseGifUrl,
    this.avgRestSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final timeStr =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final done = targetSeconds > 0 && seconds >= targetSeconds;
    final progress =
        targetSeconds > 0 ? (seconds / targetSeconds).clamp(0.0, 1.0) : 0.0;

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
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        AppColors.accent.withValues(alpha: done ? 0.45 : 0.18),
                    blurRadius: done ? 52 : 32,
                    spreadRadius: done ? 8 : 2,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: targetSeconds > 0 ? (1 - progress) : null,
                      strokeWidth: 8,
                      backgroundColor: AppColors.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        done
                            ? AppColors.accent
                            : AppColors.accent.withValues(alpha: 0.6),
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
                done
                    ? 'Можно продолжать!'
                    : 'Цель: ${targetSeconds ~/ 60}:${(targetSeconds % 60).toString().padLeft(2, '0')}',
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
            if (avgRestSeconds != null) ...[
              const SizedBox(height: 8),
              Text(
                'Обычно вы отдыхаете ${avgRestSeconds! ~/ 60}:${(avgRestSeconds! % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AdjustRestButton(label: '−30с', onTap: () => onAdjust(-30)),
                const SizedBox(width: 16),
                SizedBox(
                  width: 160,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: onSkip,
                    child: const Text(
                      'Готов',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                _AdjustRestButton(label: '+30с', onTap: () => onAdjust(30)),
              ],
            ),
            if (nextExerciseName != null) ...[
              const SizedBox(height: 32),
              const Text(
                'Следующее',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Text(
                nextExerciseName!,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                textAlign: TextAlign.center,
              ),
              if (nextExerciseGifUrl != null) ...[
                const SizedBox(height: 12),
                _ExerciseMedia(
                  url: nextExerciseGifUrl!,
                  height: 140,
                  width: 220,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Кнопка регулировки таймера отдыха ───────────────────────────────────────

class _AdjustRestButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AdjustRestButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.accent,
          ),
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

  List<double> _calcPlates(
      double totalWeight, double bar, List<double> plates) {
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
    final displayStr = display % 1 == 0
        ? display.toInt().toString()
        : display.toStringAsFixed(1);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center,
                    color: AppColors.accent, size: 20),
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
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
                  final label =
                      p % 1 == 0 ? p.toInt().toString() : p.toStringAsFixed(2);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4)),
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
      ),
    );
  }
}

// ─── Неоновый прогресс-бар (CustomPainter) ───────────────────────────────────

class _NeonProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color background;

  const _NeonProgressPainter({
    required this.progress,
    required this.color,
    required this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = background,
    );
    if (progress <= 0) return;
    final filled =
        Rect.fromLTWH(0, 0, size.width * progress.clamp(0.0, 1.0), size.height);
    canvas.drawRect(
      filled,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRect(filled, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_NeonProgressPainter old) => old.progress != progress;
}
