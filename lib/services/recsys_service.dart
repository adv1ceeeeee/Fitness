/// Recommendation engine — deterministic heuristics over user data.
///
/// Each public method returns a typed recommendation (or null = no issue).
/// No Flutter dependencies — pure Dart, fully testable.
library;

import 'dart:math';

// ─── Severity ─────────────────────────────────────────────────────────────────

enum RecSeverity { info, warning, critical }

// ─── Wellness recommendation ──────────────────────────────────────────────────

class WellnessRec {
  final RecSeverity severity;
  final String title;
  final String message;

  const WellnessRec({
    required this.severity,
    required this.title,
    required this.message,
  });
}

/// Evaluates today's wellness log and returns a load recommendation.
///
/// Returns null when all indicators are in the healthy range.
///
/// [wellness] — row from wellness_logs:
///   sleep_hours (double?), stress 1–10 (int?),
///   energy 1–10 (int?), soreness 1–5 (int?)
WellnessRec? evaluateWellness(Map<String, dynamic>? wellness) {
  if (wellness == null) return null;

  final sleep        = (wellness['sleep_hours']  as num?)?.toDouble();
  final stress       = wellness['stress']        as int?;
  final energy       = wellness['energy']        as int?;
  final soreness     = wellness['soreness']      as int?;
  final sleepQuality = wellness['sleep_quality'] as int?; // 1–5

  final badSleep      = sleep        != null && sleep        < 6;
  final poorSleepQuality = sleepQuality != null && sleepQuality <= 2;
  final highStress    = stress       != null && stress       >= 8;
  final lowEnergy     = energy       != null && energy       <= 3;
  final highSoreness  = soreness     != null && soreness     >= 4;

  // Treat poor sleep quality (≤ 2/5) the same as short sleep for load purposes
  final effectiveBadSleep = badSleep || poorSleepQuality;

  // ── Critical: плохой сон/качество + высокий стресс одновременно ─────────
  if (effectiveBadSleep && highStress) {
    final sleepStr = sleep != null
        ? (sleep % 1 == 0 ? '${sleep.toInt()}ч' : '${sleep.toStringAsFixed(1)}ч')
        : null;
    final sleepDesc = sleepStr != null
        ? 'сон $sleepStr'
        : 'низкое качество сна (${sleepQuality!}/5)';
    return WellnessRec(
      severity: RecSeverity.critical,
      title: 'Сегодня лучше отдохнуть',
      message: '$sleepDesc и стресс $stress/10 — '
          'тяжёлая тренировка сейчас замедлит восстановление. '
          'Рассмотри лёгкую растяжку или прогулку.',
    );
  }

  // ── Warning: плохой сон/качество или высокий стресс ─────────────────────
  if (effectiveBadSleep || highStress) {
    final reasons = <String>[];
    if (badSleep) {
      final sleepStr = sleep % 1 == 0
          ? '${sleep.toInt()}ч'
          : '${sleep.toStringAsFixed(1)}ч';
      reasons.add('сон $sleepStr');
    } else if (poorSleepQuality) {
      reasons.add('качество сна $sleepQuality/5');
    }
    if (highStress) reasons.add('стресс $stress/10');
    return WellnessRec(
      severity: RecSeverity.warning,
      title: 'Снизь нагрузку сегодня',
      message: 'У тебя ${reasons.join(' и ')} — '
          'лучше сделать лёгкую тренировку и сократить объём.',
    );
  }

  // ── Warning: низкая энергия ───────────────────────────────────────────────
  if (lowEnergy) {
    return WellnessRec(
      severity: RecSeverity.warning,
      title: 'Энергия низкая',
      message: 'Энергия $energy/10 — пропусти тяжёлые упражнения '
          'или сократи объём на 20–30%.',
    );
  }

  // ── Info: высокая крепатура ───────────────────────────────────────────────
  if (highSoreness) {
    return WellnessRec(
      severity: RecSeverity.info,
      title: 'Высокая крепатура',
      message: 'Крепатура $soreness/5 — убедись что сегодня '
          'не тренируешь уставшие группы мышц.',
    );
  }

  return null; // всё в норме
}

// ─── Progression recommendation ───────────────────────────────────────────────

enum ProgressionDirection { increase, maintain, decrease }

class ProgressionRec {
  final ProgressionDirection direction;
  final String message;
  /// Concrete weight to suggest (kg). Non-null → chip is tappable.
  final double? suggestedWeightKg;

  const ProgressionRec({
    required this.direction,
    required this.message,
    this.suggestedWeightKg,
  });
}

/// Unified progression evaluator — single source of truth for weight advice.
///
/// Signal priority (highest → lowest):
///   1. maintain  — reps < target last session
///   2. decrease  — RPE ≥ 9 in both recent sessions
///   3. increase  — ≥ 3 consecutive sessions with all reps completed
///   4. increase  — RPE ≤ 7 both sessions + all reps hit
///   5. increase  — RPE ≤ 6 last session + all reps hit
///   6. increase  — reps ≥ top of reps range (weak signal, no RPE needed)
///
/// [last]               — most recent session map: {weight, reps,
///                        reps_target?, rpe?, prev?}
/// [consecutiveFullReps]— how many consecutive sessions all reps were
///                        completed (from getConsecutiveFullRepsExercises).
/// [topRepsInRange]     — upper bound of the exercise's reps_range config
///                        (e.g. 12 for "8–12"). Used for the weak signal.
///
/// Returns null when data is insufficient to make a recommendation.
ProgressionRec? evaluateProgression(
  Map<String, dynamic>? last, {
  int consecutiveFullReps = 0,
  int? topRepsInRange,
  double weightIncrement = 2.5,
  /// Current intra-session energy state. Influences recommendation direction:
  ///   bucket 1–2 → boost (slightly lower RPE threshold)
  ///   bucket 5–6 → caution note added to increase messages
  ///   bucket 7–8 → override increase → maintain
  ///   bucket 9–10 → override to decrease
  EnergyState? energyState,
  /// All-time best estimated 1RM (Epley) for this exercise.
  /// When provided, a "close to PR" motivational note is appended when the
  /// next suggested 1RM is within 3% of the personal best 1RM.
  double? personalBest1RMKg,
  /// User's training goal (from profiles.goal).
  /// Adjusts progression thresholds: strength → faster, weight_loss/endurance → slower.
  String? userGoal,
  /// RPE calibration offset (median reported RPE − 7.0, clamped −2..+2).
  /// Positive = user over-reports RPE; their thresholds shift down accordingly.
  double rpeCalibrationOffset = 0.0,
  /// Whether this is a bodyweight exercise (is_bodyweight = true).
  /// Bodyweight exercises use rep-based progression, not weight-based.
  bool isBodyweight = false,
}) {
  if (last == null) return null;

  final lastReps       = last['reps']        as int?;
  final lastRepsTarget = last['reps_target'] as int?;
  final lastRpe        = last['rpe']         as int?;
  final lastWeight     = (last['weight'] as num?)?.toDouble();

  if (lastWeight == null || lastWeight <= 0) return null;

  // ── Bodyweight bypass ─────────────────────────────────────────────────────
  // For bodyweight exercises, weight increase signals don't apply.
  // Progression is rep-based instead.
  if (isBodyweight) {
    if (lastRepsTarget != null && lastReps != null && lastReps < lastRepsTarget) {
      return ProgressionRec(
        direction: ProgressionDirection.maintain,
        message: 'В прошлый раз $lastReps из $lastRepsTarget повт — продолжай работать над техникой.',
      );
    }
    if (lastReps != null && lastRepsTarget != null && lastReps >= lastRepsTarget) {
      if (consecutiveFullReps >= 2) {
        return ProgressionRec(
          direction: ProgressionDirection.increase,
          message: '$consecutiveFullReps сессии подряд — попробуй усложнить упражнение или добавь повторения.',
        );
      }
    }
    return null; // no weight-based signal for bodyweight
  }

  // ── 0. Extreme energy override ────────────────────────────────────────────
  // Applied before any signal: critical fatigue forces a decrease regardless
  // of RPE/reps history (athlete's capacity is too depleted to progress).
  if (energyState != null && energyState.bucket >= 9) {
    final pct = energyState.reserve.toStringAsFixed(0);
    return ProgressionRec(
      direction: ProgressionDirection.decrease,
      message: 'Резерв энергии критически низкий ($pct%) — снизь вес сегодня.',
      suggestedWeightKg: _prevIncrement(lastWeight, weightIncrement),
    );
  }

  // Round UP to the next available weight on the rack.
  // ceil((weight + ε) / increment) × increment ensures we always step forward
  // even when the current weight is already an exact multiple of the increment.
  final suggestedWeight = _nextIncrement(lastWeight, weightIncrement);

  // ── PR-proximity flag (1RM-based) ──────────────────────────────────────────
  // True when the next suggested 1RM would be within 3% of the personal best 1RM.
  final int estReps = lastReps ?? lastRepsTarget ?? 8;
  final double suggested1RM = estimatedOneRepMax(suggestedWeight, estReps);
  final nearPr = personalBest1RMKg != null && suggested1RM >= personalBest1RMKg * 0.97;
  const prSuffix = ' Это будет личный рекорд — дерзай!';

  // ── Goal-adjusted thresholds ──────────────────────────────────────────────
  // strength: progress faster (lower consecutive bar, higher RPE ceiling)
  // weight_loss/endurance: progress more conservatively
  final int consecutiveThreshold = userGoal == 'strength' ? 2 : 3;
  final int singleSessionRpeThreshold = userGoal == 'strength' ? 7 : 6;
  final bool allowWeakIncrease = userGoal != 'weight_loss' && userGoal != 'endurance';

  final prev        = last['prev'] as Map<String, dynamic>?;
  final prevRpe     = prev?['rpe']          as int?;
  final prevRepsTarget = prev?['reps_target'] as int?;
  final prevReps    = prev?['reps']          as int?;

  // ── RPE calibration ───────────────────────────────────────────────────────
  // Adjust reported RPE toward the population mean.
  // If user over-reports RPE (positive offset), their effective RPE is lower.
  final calibratedLastRpe = lastRpe != null
      ? (lastRpe - rpeCalibrationOffset).round().clamp(1, 10)
      : null;
  final calibratedPrevRpe = prevRpe != null
      ? (prevRpe - rpeCalibrationOffset).round().clamp(1, 10)
      : null;

  // ── 1. Maintain: не выполнил целевые повторения ───────────────────────────
  if (lastRepsTarget != null && lastReps != null && lastReps < lastRepsTarget) {
    return ProgressionRec(
      direction: ProgressionDirection.maintain,
      message: 'В прошлый раз $lastReps из $lastRepsTarget повт — '
          'зафиксируй результат ещё на одну сессию.',
    );
  }

  // ── 2. Decrease: RPE ≥ 9 в обеих сессиях ─────────────────────────────────
  if (calibratedLastRpe != null && calibratedLastRpe >= 9 &&
      calibratedPrevRpe  != null && calibratedPrevRpe  >= 9) {
    return ProgressionRec(
      direction: ProgressionDirection.decrease,
      message: 'RPE 9+ два раза подряд — попробуй снизить вес.',
      suggestedWeightKg: _prevIncrement(lastWeight, weightIncrement),
    );
  }

  final lastHitTarget = lastRepsTarget == null ||
      (lastReps != null && lastReps >= lastRepsTarget);
  final prevHitTarget = prevRepsTarget == null ||
      (prevReps != null && prevReps >= prevRepsTarget);

  final incLabel = _incrementLabel(weightIncrement);

  // ── 3. Increase (strong): N consecutive sessions ──────────────────────────
  if (consecutiveFullReps >= consecutiveThreshold && lastHitTarget) {
    return _applyEnergyToIncrease(
      ProgressionRec(
        direction: ProgressionDirection.increase,
        message: '$consecutiveFullReps сессии подряд — '
            'самое время попробовать $incLabel!${nearPr ? prSuffix : ''}',
        suggestedWeightKg: suggestedWeight,
      ),
      energyState, lastWeight, weightIncrement,
    );
  }

  // ── 4. Increase: RPE ≤ 7 в обеих сессиях + все повторения выполнены ──────
  if (calibratedLastRpe != null && calibratedLastRpe <= 7 &&
      calibratedPrevRpe  != null && calibratedPrevRpe  <= 7 &&
      lastHitTarget && prevHitTarget) {
    return _applyEnergyToIncrease(
      ProgressionRec(
        direction: ProgressionDirection.increase,
        message: 'RPE $lastRpe и $prevRpe/10 за последние 2 сессии — '
            'попробуй $incLabel сегодня.${nearPr ? prSuffix : ''}',
        suggestedWeightKg: suggestedWeight,
      ),
      energyState, lastWeight, weightIncrement,
    );
  }

  // ── 5. Increase: RPE ≤ threshold one session ──────────────────────────────
  if (calibratedLastRpe != null && calibratedLastRpe <= singleSessionRpeThreshold && lastHitTarget) {
    return _applyEnergyToIncrease(
      ProgressionRec(
        direction: ProgressionDirection.increase,
        message: 'RPE $lastRpe/10 в прошлый раз — '
            'хорошее время попробовать $incLabel.${nearPr ? prSuffix : ''}',
        suggestedWeightKg: suggestedWeight,
      ),
      energyState, lastWeight, weightIncrement,
    );
  }

  // ── 6. Increase (weak): reps ≥ top of range ───────────────────────────────
  if (allowWeakIncrease && topRepsInRange != null && lastReps != null &&
      lastReps >= topRepsInRange && lastHitTarget) {
    return _applyEnergyToIncrease(
      ProgressionRec(
        direction: ProgressionDirection.increase,
        message: 'Выполнил $lastReps повт — попробуй $incLabel.${nearPr ? prSuffix : ''}',
        suggestedWeightKg: suggestedWeight,
      ),
      energyState, lastWeight, weightIncrement,
    );
  }

  return null; // данных недостаточно или всё в норме
}

// ─── Cardio progression ───────────────────────────────────────────────────────
//
// Cardio progression is time- or distance-based. Weight/RPE-based signals from
// [evaluateProgression] do not apply. This evaluator is separate and additive:
// call sites decide which one to invoke based on the exercise's input mode.

/// Suggest a cardio progression step (increase duration or distance).
///
/// [last]        — most recent cardio set: {duration_seconds?, distance_m?}
/// [secondLast]  — previous cardio set; used to detect plateau
/// [increaseMin] — how many minutes to suggest adding (default 2)
///
/// Returns null when data is insufficient. Returns an `increase` rec if the
/// user has matched or beaten their previous duration/distance for two
/// consecutive sessions; a `maintain` rec if they fell short last time.
ProgressionRec? evaluateCardioProgression(
  Map<String, dynamic>? last, {
  Map<String, dynamic>? secondLast,
  int increaseMin = 2,
}) {
  if (last == null) return null;
  final lastDur = (last['duration_seconds'] as num?)?.toInt();
  final lastDist = (last['distance_m'] as num?)?.toDouble();
  if (lastDur == null && lastDist == null) return null;

  final prevDur = (secondLast?['duration_seconds'] as num?)?.toInt();

  // Regression — plateau or backslide relative to previous session.
  if (prevDur != null && lastDur != null && lastDur < prevDur) {
    final diffMin = ((prevDur - lastDur) / 60).ceil();
    return ProgressionRec(
      direction: ProgressionDirection.maintain,
      message:
          'В прошлый раз было на $diffMin мин больше — повтори прежний объём.',
    );
  }

  // Consistent or improving — suggest pushing further.
  final baseMin = lastDur != null ? (lastDur ~/ 60) : null;
  if (baseMin != null && baseMin > 0) {
    final target = baseMin + increaseMin;
    final repeated = prevDur != null && lastDur! >= prevDur;
    final msg = repeated
        ? 'Две сессии подряд по $baseMin мин — попробуй $target мин.'
        : 'Добавь $increaseMin мин к прошлому объёму ($baseMin мин).';
    return ProgressionRec(
      direction: ProgressionDirection.increase,
      message: msg,
    );
  }

  // Distance-only fallback (e.g. run tracker without duration).
  if (lastDist != null && lastDist > 0) {
    final km = lastDist / 1000;
    return ProgressionRec(
      direction: ProgressionDirection.increase,
      message: 'Попробуй пройти ${(km + 0.5).toStringAsFixed(1)} км.',
    );
  }

  return null;
}

// ─── Muscle balance recommendation ────────────────────────────────────────────

class MuscleImbalanceRec {
  /// Human-readable name of the undertrained group.
  final String weakLabel;
  /// Human-readable name of the overtrained group.
  final String strongLabel;
  /// Ratio of weak/strong (0..1). Lower = bigger imbalance.
  final double ratio;
  final String message;

  const MuscleImbalanceRec({
    required this.weakLabel,
    required this.strongLabel,
    required this.ratio,
    required this.message,
  });
}

// Antagonist pairs to check: (dominant, antagonist) category/sub-category keys.
// Top-level keys ('chest', 'back') come from getMuscleGroupBalance.
// Sub-category keys ('legs:quad', etc.) are also emitted by getMuscleGroupBalance.
const _antagonistPairs = [
  // Push / pull horizontal
  ('chest', 'back'),
  ('back',  'chest'),
  // Legs anterior / posterior chain
  ('legs:quad',     'legs:hamstring'),
  ('legs:hamstring', 'legs:quad'),
  // Shoulder push vs rear delt
  ('shoulders:push', 'shoulders:rear'),
  ('shoulders:rear', 'shoulders:push'),
];

const _muscleRuLabels = {
  'chest':            'Грудь',
  'back':             'Спина',
  'shoulders':        'Плечи',
  'arms':             'Руки',
  'legs':             'Ноги',
  'core':             'Пресс',
  'cardio':           'Кардио',
  // Sub-categories (from getMuscleGroupBalance sub-category split)
  'legs:quad':        'Квадрицепс',
  'legs:hamstring':   'Задняя поверхность бедра',
  'shoulders:push':   'Передние/боковые дельты',
  'shoulders:rear':   'Задние дельты',
};

/// Checks antagonist muscle pairs for significant imbalance (last 30 days).
///
/// [balance] — {categoryKey: completedSets} from getMuscleGroupBalance().
/// Returns the worst imbalance found, or null if everything is within range.
MuscleImbalanceRec? evaluateMuscleBalance(Map<String, int> balance) {
  if (balance.isEmpty) return null;

  const minSetsThreshold = 6; // ignore groups with too little data
  const imbalanceRatio   = 0.6; // weak must be < 60 % of strong to flag

  MuscleImbalanceRec? worst;

  for (final (a, b) in _antagonistPairs) {
    final setsA = balance[a] ?? 0;
    final setsB = balance[b] ?? 0;
    // Need enough data on the stronger side
    final stronger = setsA > setsB ? setsA : setsB;
    final weaker   = setsA > setsB ? setsB : setsA;
    final weakKey  = setsA > setsB ? b : a;
    final strongKey = setsA > setsB ? a : b;
    if (stronger < minSetsThreshold) continue;
    final ratio = weaker / stronger;
    if (ratio >= imbalanceRatio) continue;
    if (worst != null && ratio >= worst.ratio) continue;

    final weakLabel   = _muscleRuLabels[weakKey]   ?? weakKey;
    final strongLabel = _muscleRuLabels[strongKey] ?? strongKey;
    final pct = ((1 - ratio) * 100).round();
    worst = MuscleImbalanceRec(
      weakLabel: weakLabel,
      strongLabel: strongLabel,
      ratio: ratio,
      message: '$strongLabel тренируется на $pct% чаще чем $weakLabel '
          'за последние 30 дней — добавь больше упражнений на $weakLabel.',
    );
  }

  return worst;
}

// ─── Plateau recommendation ────────────────────────────────────────────────────

class PlateauRec {
  /// Exercise with the longest stagnation.
  final String exerciseName;
  /// Current working weight (kg).
  final double weightKg;
  /// How many consecutive weeks the weight hasn't changed.
  final int weeksStagnant;
  final String message;

  const PlateauRec({
    required this.exerciseName,
    required this.weightKg,
    required this.weeksStagnant,
    required this.message,
  });
}

/// Returns the most notable plateau from a list of stagnant exercises.
///
/// [stagnant] — output of AnalyticsService.getStagnantExercises():
///   [{exerciseId, exerciseName, currentWeightKg, weeksStagnant}]
///
/// Returns null when the list is empty (no detected plateaus).
PlateauRec? evaluatePlateau(List<Map<String, dynamic>> stagnant) {
  if (stagnant.isEmpty) return null;

  // Pick the exercise with the most weeks of stagnation
  final worst = stagnant.reduce((a, b) =>
      (a['weeksStagnant'] as int) >= (b['weeksStagnant'] as int) ? a : b);

  final name   = worst['exerciseName'] as String;
  final weight = (worst['currentWeightKg'] as num).toDouble();
  final weeks  = worst['weeksStagnant'] as int;

  final weightStr = weight % 1 == 0
      ? '${weight.toInt()} кг'
      : '${weight.toStringAsFixed(1)} кг';
  final weeksStr = _weeksLabel(weeks);

  return PlateauRec(
    exerciseName: name,
    weightKg: weight,
    weeksStagnant: weeks,
    message: '$name — $weightStr уже $weeksStr. '
        'Попробуй изменить схему подходов, темп или взять неделю deload.',
  );
}

// ─── Deload recommendation ────────────────────────────────────────────────────

class DeloadRec {
  /// How many percent above the personal baseline the recent load is.
  final double overloadPct;
  /// How many complete weeks the training has been above baseline.
  final int weeksAboveBaseline;
  final String message;

  const DeloadRec({
    required this.overloadPct,
    required this.weeksAboveBaseline,
    required this.message,
  });
}

/// Returns a deload recommendation when recent weekly volume is consistently
/// above the athlete's personal baseline.
///
/// Trigger: [recentAvgVolume] ≥ 110 % of [baselineAvgVolume] for at least 3
/// consecutive complete weeks ([consecutiveWeeks] ≥ 3).
///
/// [recentAvgVolume]    — average kg×reps per week over the last 4 weeks.
/// [baselineAvgVolume]  — average kg×reps per week over the prior baseline period.
/// [consecutiveWeeks]   — how many complete weeks the load has been above baseline.
///
/// Returns null when the training load is within normal range.
DeloadRec? evaluateDeload({
  required double recentAvgVolume,
  required double baselineAvgVolume,
  required int consecutiveWeeks,
}) {
  if (baselineAvgVolume <= 0) return null;
  final overloadPct = (recentAvgVolume - baselineAvgVolume) / baselineAvgVolume * 100;
  if (overloadPct < 10 || consecutiveWeeks < 3) return null;

  final pctStr = overloadPct.round().toString();
  final weeksStr = _weeksLabel(consecutiveWeeks);

  return DeloadRec(
    overloadPct: overloadPct,
    weeksAboveBaseline: consecutiveWeeks,
    message: 'Объём нагрузки на $pctStr% выше нормы уже $weeksStr — '
        'рассмотри неделю deload (−30–40% весов) для полноценного восстановления.',
  );
}

/// Applies energy state to an increase recommendation.
///
/// bucket 7–8 → downgrades to maintain (athlete too fatigued to safely add load)
/// bucket 5–6 → keeps increase but appends a caution note
/// bucket 1–4 → returns the rec unchanged
ProgressionRec _applyEnergyToIncrease(
  ProgressionRec rec,
  EnergyState? energyState,
  double lastWeight,
  double increment,
) {
  if (energyState == null) return rec;
  final bucket = energyState.bucket;
  final pct = energyState.reserve.toStringAsFixed(0);

  if (bucket >= 7) {
    return ProgressionRec(
      direction: ProgressionDirection.maintain,
      message: '${rec.message} Но резерв энергии низкий ($pct%) — '
          'сегодня лучше держать текущий вес.',
    );
  }
  if (bucket >= 5) {
    return ProgressionRec(
      direction: rec.direction,
      message: '${rec.message} Энергия умеренная ($pct%) — слушай тело.',
      suggestedWeightKg: rec.suggestedWeightKg,
    );
  }
  return rec;
}

/// Formats a weight increment for display in recommendation messages.
/// E.g. 2.5 → '+2.5 кг', 5 → '+5 кг', 1.25 → '+1.25 кг'.
/// Epley formula: estimated 1-rep max from a given weight and rep count.
/// Valid for reps 1–30; returns [weight] unchanged for reps <= 1.
double estimatedOneRepMax(double weight, int reps) {
  if (reps <= 1) return weight;
  if (reps > 30) reps = 30; // formula unreliable beyond 30 reps
  return weight * (1 + reps / 30.0);
}

String _incrementLabel(double inc) {
  final display = inc % 1 == 0 ? inc.toInt().toString() : inc.toString();
  return '+$display кг';
}

/// Returns the smallest multiple of [increment] that is strictly greater
/// than [weight], i.e. the next available weight on the rack.
///
/// Examples:
///   _nextIncrement(20.0, 5.0)  → 25.0
///   _nextIncrement(23.0, 5.0)  → 25.0  (not 28)
///   _nextIncrement(25.0, 5.0)  → 30.0
///   _nextIncrement(80.0, 2.5)  → 82.5
double _nextIncrement(double weight, double increment) {
  // Add a tiny epsilon so an exact multiple always rounds up to the next step.
  return ((weight + increment * 0.001) / increment).ceil() * increment;
}

/// Returns the largest multiple of [increment] strictly less than [weight],
/// i.e. one step down the rack.
///
/// Examples:
///   _prevIncrement(100.0, 2.5) → 97.5
///   _prevIncrement(25.0,  5.0) → 20.0
double _prevIncrement(double weight, double increment) {
  return ((weight - increment * 0.001) / increment).floor() * increment;
}

String _weeksLabel(int n) {
  if (n % 100 >= 11 && n % 100 <= 19) return '$n недель';
  switch (n % 10) {
    case 1: return '$n неделю';
    case 2:
    case 3:
    case 4: return '$n недели';
    default: return '$n недель';
  }
}

// ─── Wellness ↔ performance correlation ───────────────────────────────────────

class WellnessCorrelationRec {
  final String exerciseName;
  final double goodSleepAvgKg;
  final double badSleepAvgKg;
  /// Percentage drop: (goodAvg - badAvg) / goodAvg * 100
  final double dropPct;
  final int sessionCount;
  final String message;

  const WellnessCorrelationRec({
    required this.exerciseName,
    required this.goodSleepAvgKg,
    required this.badSleepAvgKg,
    required this.dropPct,
    required this.sessionCount,
    required this.message,
  });
}

// ─── Post-session contextual insights ─────────────────────────────────────────

enum PostSessionInsightKind { streak, volumeUp, volumeDown, setsCount }

class PostSessionInsight {
  final PostSessionInsightKind kind;
  final String message;

  const PostSessionInsight({required this.kind, required this.message});
}

/// Generates contextual insights to show on the post-session summary screen.
///
/// [streak]          — current training streak after this session.
/// [sessionVolume]   — total working volume (kg × reps) of this session.
/// [recentAvgVolume] — avg volume of last N completed sessions (null = unknown).
/// [workingSetsCount]— number of non-warmup completed sets this session.
List<PostSessionInsight> evaluatePostSession({
  required int streak,
  required double sessionVolume,
  double? recentAvgVolume,
  required int workingSetsCount,
}) {
  final insights = <PostSessionInsight>[];

  // 1. Streak
  if (streak >= 2) {
    final msg = _streakMessage(streak);
    insights.add(PostSessionInsight(kind: PostSessionInsightKind.streak, message: msg));
  }

  // 2. Volume vs recent average
  if (recentAvgVolume != null && recentAvgVolume > 0 && sessionVolume > 0) {
    final diffPct = (sessionVolume - recentAvgVolume) / recentAvgVolume * 100;
    if (diffPct >= 10) {
      insights.add(PostSessionInsight(
        kind: PostSessionInsightKind.volumeUp,
        message: 'Объём на ${diffPct.round()}% выше обычного — сильная сессия!',
      ));
    } else if (diffPct <= -15) {
      insights.add(PostSessionInsight(
        kind: PostSessionInsightKind.volumeDown,
        message: 'Объём на ${diffPct.round().abs()}% ниже среднего — лёгкое восстановление.',
      ));
    }
  }

  // 3. High set count
  if (workingSetsCount >= 12) {
    insights.add(PostSessionInsight(
      kind: PostSessionInsightKind.setsCount,
      message: '$workingSetsCount рабочих подходов — высокий объём!',
    ));
  }

  return insights;
}

String _streakMessage(int streak) {
  if (streak == 2) return '2 тренировки подряд — отличное начало!';
  if (streak == 3) return '3 тренировки подряд — войдите в ритм!';
  if (streak % 10 == 0) return '🔥 $streak тренировок подряд — невероятно!';
  if (streak % 5 == 0) return '🔥 $streak тренировок подряд — так держать!';
  return '$streak тренировок подряд';
}

// ─── Wellness ↔ performance correlation ───────────────────────────────────────

/// Picks the most notable sleep → performance correlation from pre-computed data.
///
/// [data] — output of AnalyticsService.getWellnessPerformanceCorrelation():
///   [{exerciseName, goodSleepAvgKg, badSleepAvgKg, dropPct, sessionCount}]
///
/// Returns null when no meaningful correlation was found.
WellnessCorrelationRec? evaluateWellnessCorrelation(
    List<Map<String, dynamic>> data) {
  if (data.isEmpty) return null;

  // data is already sorted by dropPct desc — take the top entry
  final top = data.first;

  final name     = top['exerciseName'] as String;
  final goodAvg  = (top['goodSleepAvgKg'] as num).toDouble();
  final badAvg   = (top['badSleepAvgKg']  as num).toDouble();
  final dropPct  = (top['dropPct']         as num).toDouble();
  final count    = top['sessionCount'] as int;

  final goodStr = goodAvg % 1 == 0
      ? '${goodAvg.toInt()} кг'
      : '${goodAvg.toStringAsFixed(1)} кг';
  final badStr  = badAvg % 1 == 0
      ? '${badAvg.toInt()} кг'
      : '${badAvg.toStringAsFixed(1)} кг';
  final pctStr  = dropPct.round().toString();

  return WellnessCorrelationRec(
    exerciseName:    name,
    goodSleepAvgKg:  goodAvg,
    badSleepAvgKg:   badAvg,
    dropPct:         dropPct,
    sessionCount:    count,
    message: 'Замечено: когда ты спишь меньше 6ч, результаты в «$name» '
        'падают в среднем на $pctStr% ($badStr vs $goodStr при хорошем сне). '
        'На основе $count сессий.',
  );
}

// ─── Energy state ─────────────────────────────────────────────────────────────

/// The athlete's current energy reserve as a continuous hidden-state variable.
///
/// This value is the single source of truth for fatigue recommendations and
/// progression scaling throughout a session. It starts from the inter-session
/// checkpoint and drains multiplicatively as sets are completed.
class EnergyState {
  /// Estimated energy reserve: 0.0 (exhausted) – 100.0 (peak).
  final double reserve;

  const EnergyState({required this.reserve});

  /// Maps reserve to a 1–10 bucket (1 = peak energy, 10 = exhausted).
  ///
  ///   100–90 → 1,  90–80 → 2,  …,  10–0 → 10
  int get bucket {
    if (reserve >= 100) return 1;
    return (10 - (reserve / 10).floor()).clamp(1, 10);
  }

  /// Short human-readable label for the current energy level (Russian).
  String get label {
    if (bucket <= 2) return 'Пик';
    if (bucket <= 4) return 'Хорошо';
    if (bucket <= 6) return 'Умеренно';
    if (bucket <= 8) return 'Низко';
    return 'Истощён';
  }

  /// Returns a copy with the given reserve clamped to [0, 100].
  EnergyState withReserve(double r) => EnergyState(reserve: r.clamp(0.0, 100.0));
}

/// Computes the energy state at the **start** of a new session.
///
/// This is the inter-session recovery model. It starts from [lastEnergyEnd]
/// (the checkpoint saved to `training_sessions.energy_end` when the previous
/// session completed) and applies exponential recovery over time.
///
/// Formula:
///   E_start = 100 − (100 − E_end) × exp(−Δt × wellnessMod / τ)
///
/// This ensures the hidden state advances strictly forward in time: we never
/// recompute from scratch — we always continue from the last known checkpoint.
///
/// [lastEnergyEnd]     — energy_end from the previous session (0–100).
///                       Pass 100 when no prior session exists.
/// [hoursSinceLast]    — hours elapsed since the last session ended.
/// [lastSessionRpe]    — session_rpe of the last session (used to derive τ).
/// [trainingMonths]    — months of experience (more → faster recovery).
/// [wellnessSinceLast] — worst wellness_log entry between sessions.
///                       Keys: sleep_hours (double), stress (int), energy (int).
EnergyState computeEnergyStart({
  double lastEnergyEnd = 100.0,
  double hoursSinceLast = 48.0,
  int? lastSessionRpe,
  int trainingMonths = 12,
  Map<String, dynamic>? wellnessSinceLast,
}) {
  // ── Recovery time constant τ ──────────────────────────────────────────
  // How long (hours) until ~63 % of fatigue is cleared, based on session intensity.
  final double tauBase = lastSessionRpe == null || lastSessionRpe <= 6
      ? 24.0   // light / cardio
      : lastSessionRpe <= 8
          ? 36.0   // medium strength
          : 48.0;  // heavy strength

  // More experience → faster recovery (τ scaled down).
  final double expMod = trainingMonths < 6
      ? 1.20   // beginner: slower
      : trainingMonths <= 24
          ? 1.00   // intermediate: baseline
          : 0.85;  // advanced: faster
  final tau = tauBase * expMod;

  // ── Wellness modifier: poor recovery quality slows restoration ────────
  // Each bad factor reduces the effective recovery rate.
  double wellnessMod = 1.0;
  if (wellnessSinceLast != null) {
    final sleep  = (wellnessSinceLast['sleep_hours'] as num?)?.toDouble();
    final stress = wellnessSinceLast['stress'] as int?;
    final energy = wellnessSinceLast['energy'] as int?;
    if (sleep  != null && sleep  < 6)   wellnessMod *= 0.70;
    if (stress != null && stress >= 8)  wellnessMod *= 0.80;
    if (energy != null && energy <= 3)  wellnessMod *= 0.80;
  }

  // ── Exponential recovery ──────────────────────────────────────────────
  final reserve = (100.0 - (100.0 - lastEnergyEnd) * exp(-hoursSinceLast * wellnessMod / tau))
      .clamp(0.0, 100.0);

  return EnergyState(reserve: reserve);
}

// ─── Intra-session fatigue recommendation ─────────────────────────────────────

enum FatigueLevel { high, moderate }

class FatigueRec {
  /// 0.0–100.0: estimated energy reserve for this muscle group.
  /// Computed via multiplicative decay — never negative, never above 100.
  final double reserve;
  /// Category key of the fatigued muscle group (e.g. 'chest').
  final String category;
  final String categoryLabel;
  /// How many non-warmup sets have already been done on this group this session.
  final int setsOnMuscle;
  final FatigueLevel level;
  final String message;

  const FatigueRec({
    required this.reserve,
    required this.category,
    required this.categoryLabel,
    required this.setsOnMuscle,
    required this.level,
    required this.message,
  });
}

/// Estimates the energy reserve for [targetCategory] and returns a fatigue
/// recommendation when the reserve is below the threshold.
///
/// [targetCategory]   — category key of the exercise being switched to.
/// [sessionHistory]   — completed sets so far, grouped by exercise.
///   Each entry: {
///     'category':      String,   // muscle group key
///     'equipmentType': String,   // 'barbell'|'dumbbell'|'cable'|'machine'|'bodyweight'|'other'
///     'movementType':  String,   // 'press'|'squat'|'row'|'lunge'|'curl'|etc.
///     'sets': [{'isWarmup': bool, 'completed': bool, 'rpe': double?}]
///   }
/// [initialState]     — inter-session energy checkpoint from [computeEnergyStart].
///   When provided, the starting reserve is [initialState.reserve] and today's
///   wellness is already factored in — the wellness baseline is skipped.
///   When null (no prior session data), starts at 100 and applies wellness.
/// [wellness]         — today's wellness_log row (used only when [initialState]
///   is null). Keys: sleep_hours (double), stress (int 1-10), energy (int 1-10).
///
/// Returns null when reserve ≥ 50 (no notable fatigue) or no sets yet.
FatigueRec? evaluateFatigue({
  required String targetCategory,
  required List<Map<String, dynamic>> sessionHistory,
  EnergyState? initialState,
  Map<String, dynamic>? wellness,
  /// Injectable for deterministic tests (defaults to a fresh Random).
  Random? random,
}) {
  final rng = random ?? Random();

  // ── 1. Starting reserve ───────────────────────────────────────────────────
  // If an inter-session checkpoint is provided, use it directly — wellness
  // was already factored in by computeEnergyStart().
  // Otherwise fall back to the legacy wellness-baseline model (100 × multipliers).
  double reserve;
  if (initialState != null) {
    reserve = initialState.reserve;
  } else {
    // Legacy path: no prior checkpoint, start at 100 and apply today's wellness.
    reserve = 100.0;
    if (wellness != null) {
      final sleep  = (wellness['sleep_hours'] as num?)?.toDouble() ?? 7.0;
      final stress = (wellness['stress']      as num?)?.toInt()    ?? 5;
      final energy = (wellness['energy']      as num?)?.toInt()    ?? 5;
      if (sleep < 6)   reserve *= 0.85;
      if (stress >= 8) reserve *= 0.90;
      if (energy <= 3) reserve *= 0.85;
    }
  }

  // ── 2. Per-set multiplicative drain with diffusion noise ──────────────────
  // Model: reserve *= (1 − drain) × (1 + σ·ε)   where ε ~ N(0,1), σ = 0.025
  // The ±2.5% white noise adds biological variability (diffusion process).
  // Clamped to [0, 1] so reserve stays in (0, 100].
  const double sigma = 0.025;
  int setsOnMuscle = 0;

  for (final entry in sessionHistory) {
    if ((entry['category'] as String?) != targetCategory) continue;
    final equipmentType = (entry['equipmentType'] as String?) ?? 'other';
    final movementType  = (entry['movementType']  as String?) ?? 'other';
    final inSuperset = (entry['inSuperset'] as bool?) ?? false;
    final supersetMultiplier = inSuperset ? 1.2 : 1.0;
    final sets = entry['sets'] as List<dynamic>? ?? [];

    for (final s in sets) {
      final map       = s as Map<String, dynamic>;
      final isWarmup  = map['isWarmup']  as bool? ?? false;
      final completed = map['completed'] as bool? ?? true;
      if (isWarmup || !completed) continue;

      final rpe = (map['rpe'] as num?)?.toDouble() ?? 7.0;
      final drain = _drainFactor(movementType, equipmentType, rpe);
      final noise = _gaussianNoise(rng);
      final multiplier = ((1.0 - drain * supersetMultiplier) * (1.0 + sigma * noise)).clamp(0.0, 1.0);
      reserve *= multiplier;
      setsOnMuscle++;
    }
  }

  if (setsOnMuscle == 0) return null;
  if (reserve >= 50.0)   return null;

  final label = _muscleRuLabels[targetCategory] ?? targetCategory;

  if (reserve < 30.0) {
    return FatigueRec(
      reserve:       reserve,
      category:      targetCategory,
      categoryLabel: label,
      setsOnMuscle:  setsOnMuscle,
      level:         FatigueLevel.high,
      message:       'Высокая усталость в «$label» — '
                     'рекомендуем снизить вес на 15–20%.',
    );
  }

  return FatigueRec(
    reserve:       reserve,
    category:      targetCategory,
    categoryLabel: label,
    setsOnMuscle:  setsOnMuscle,
    level:         FatigueLevel.moderate,
    message:       'Мышца «$label» уже поработала — '
                   'попробуй снизить вес на 5–10%.',
  );
}

/// Box-Muller transform: returns one standard-normal sample ε ~ N(0,1).
/// Uses two uniform samples to avoid log(0) by clamping u1 away from zero.
double _gaussianNoise(Random rng) {
  final u1 = rng.nextDouble().clamp(1e-10, 1.0);
  final u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

/// Compound movements (multi-joint) — higher neural + muscular demand.
const _compoundMovements = {'press', 'squat', 'lunge', 'row'};

/// Per-set drain factor for the multiplicative fatigue model.
///
/// drain_factor = base_rate × equipment_multiplier × rpe_modifier
///
/// Base rates:
///   compound  0.12  — multi-joint, highest fatigue
///   isolation 0.07  — single-joint, lower fatigue
///
/// Equipment multipliers (relative neural + stabilisation demand):
///   barbell   1.00  (highest — free bar, full neural activation)
///   dumbbell  0.85
///   bodyweight 0.75
///   cable     0.70
///   machine   0.60  (guided path — least stabiliser demand)
///   other     0.65
///
/// RPE modifier = rpe / 7 (RPE 7 = baseline 1.0×), clamped [0.5, 1.5].
double _drainFactor(String movementType, String equipmentType, double rpe) {
  final base = _compoundMovements.contains(movementType) ? 0.12 : 0.07;

  const eqMult = <String, double>{
    'barbell':    1.00,
    'dumbbell':   0.85,
    'bodyweight': 0.75,
    'cable':      0.70,
    'machine':    0.60,
    'other':      0.65,
  };
  final mult = eqMult[equipmentType] ?? 0.65;

  final rpeModifier = (rpe / 7.0).clamp(0.5, 1.5);
  return base * mult * rpeModifier;
}

// ═════════════════════════════════════════════════════════════════════════════
// Extended recommendation pool (v2) — 12 new evaluators
// All pure functions. No DB access. Fully unit-testable.
// ═════════════════════════════════════════════════════════════════════════════

// ─── 1. Autoregulation by session RPE ─────────────────────────────────────────

enum AutoregDirection { increase, decrease, hold }

class AutoregulationRec {
  final AutoregDirection direction;
  final double avgRpe;
  final int sessionsAnalyzed;
  final String message;

  const AutoregulationRec({
    required this.direction,
    required this.avgRpe,
    required this.sessionsAnalyzed,
    required this.message,
  });
}

/// Autoregulates weekly load based on average session RPE.
///
/// [recentSessionRpes] — session_rpe values for the last 4-8 sessions, newest
/// first. Null/missing RPEs are ignored.
///
/// Thresholds:
///   avg RPE ≥ 8.5 → decrease (too hard, deload incoming)
///   avg RPE ≤ 6.5 → increase (undertrained, add intensity)
///   otherwise     → null (on target)
///
/// Requires at least 4 sessions with valid RPE.
AutoregulationRec? evaluateAutoregulation(List<double?> recentSessionRpes) {
  final valid = recentSessionRpes.whereType<double>().toList();
  if (valid.length < 4) return null;

  final avg = valid.reduce((a, b) => a + b) / valid.length;
  final avgStr = avg.toStringAsFixed(1);
  final n = valid.length;

  if (avg >= 8.5) {
    return AutoregulationRec(
      direction: AutoregDirection.decrease,
      avgRpe: avg,
      sessionsAnalyzed: n,
      message: 'Средний RPE за $n тренировок: $avgStr — слишком тяжело. '
          'Сделай лёгкую неделю или сократи объём на 20-30%.',
    );
  }
  if (avg <= 6.5) {
    return AutoregulationRec(
      direction: AutoregDirection.increase,
      avgRpe: avg,
      sessionsAnalyzed: n,
      message: 'Средний RPE за $n тренировок: $avgStr — можно прибавить '
          'интенсивность: добавь подход или 2.5–5 кг в ключевых упражнениях.',
    );
  }
  return null;
}

// ─── 2. Rep range diversification ─────────────────────────────────────────────

enum RepRangeBlock { strength, hypertrophy, endurance }

class RepRangeRec {
  /// Block the user has been stuck in.
  final RepRangeBlock currentBlock;
  /// Block the user should try next.
  final RepRangeBlock suggestedBlock;
  /// How many consecutive weeks in the current block.
  final int weeksInBlock;
  final String message;

  const RepRangeRec({
    required this.currentBlock,
    required this.suggestedBlock,
    required this.weeksInBlock,
    required this.message,
  });
}

/// Suggests rotating into a different rep range when a user has been in the
/// same rep block for too many weeks.
///
/// [avgRepsPerWeek] — average top-of-range reps per week, newest first.
/// A week counts as "in block" when the average reps falls into the block.
///
/// Block boundaries:
///   strength:    ≤ 6 reps
///   hypertrophy: 7–12 reps
///   endurance:   ≥ 13 reps
///
/// Triggers when ≥ 8 consecutive weeks in the same block.
RepRangeRec? evaluateRepRangeDiversification(List<double> avgRepsPerWeek) {
  if (avgRepsPerWeek.length < 8) return null;

  RepRangeBlock blockFor(double r) {
    if (r <= 6) return RepRangeBlock.strength;
    if (r <= 12) return RepRangeBlock.hypertrophy;
    return RepRangeBlock.endurance;
  }

  final current = blockFor(avgRepsPerWeek.first);
  int streak = 0;
  for (final r in avgRepsPerWeek) {
    if (blockFor(r) == current) {
      streak++;
    } else {
      break;
    }
  }
  if (streak < 8) return null;

  // Pick a new block — rotate through strength/hypertrophy/endurance
  final suggested = switch (current) {
    RepRangeBlock.strength => RepRangeBlock.hypertrophy,
    RepRangeBlock.hypertrophy => RepRangeBlock.strength,
    RepRangeBlock.endurance => RepRangeBlock.hypertrophy,
  };

  String blockLabel(RepRangeBlock b) => switch (b) {
        RepRangeBlock.strength => 'сила (3–6 повторов)',
        RepRangeBlock.hypertrophy => 'гипертрофия (8–12 повторов)',
        RepRangeBlock.endurance => 'выносливость (15–20 повторов)',
      };

  return RepRangeRec(
    currentBlock: current,
    suggestedBlock: suggested,
    weeksInBlock: streak,
    message: '${_weeksLabel(streak)} подряд в блоке "${blockLabel(current)}". '
        'Для лучшего прогресса попробуй блок "${blockLabel(suggested)}" — '
        'смена стимула запускает новый рост.',
  );
}

// ─── 3. Consistency rescue ────────────────────────────────────────────────────

class ConsistencyRec {
  final int sessionsLast2Weeks;
  final double baselineSessionsPer2Weeks;
  final double dropPct;
  final String message;

  const ConsistencyRec({
    required this.sessionsLast2Weeks,
    required this.baselineSessionsPer2Weeks,
    required this.dropPct,
    required this.message,
  });
}

/// Nudges the user when recent frequency has dropped below their personal
/// baseline.
///
/// [sessionsLast2Weeks]       — count of completed sessions in the last 14 days.
/// [baselineSessionsPer2Weeks] — average completed sessions per 2-week window
///   over the preceding 8 weeks.
///
/// Triggers when the recent count is < 70 % of baseline AND baseline ≥ 2
/// (otherwise there's not enough data to judge a drop).
ConsistencyRec? evaluateConsistency({
  required int sessionsLast2Weeks,
  required double baselineSessionsPer2Weeks,
}) {
  if (baselineSessionsPer2Weeks < 2) return null;
  final ratio = sessionsLast2Weeks / baselineSessionsPer2Weeks;
  if (ratio >= 0.70) return null;

  final dropPct = (1.0 - ratio) * 100;
  final dropStr = dropPct.round().toString();

  return ConsistencyRec(
    sessionsLast2Weeks: sessionsLast2Weeks,
    baselineSessionsPer2Weeks: baselineSessionsPer2Weeks,
    dropPct: dropPct,
    message: 'Частота упала на $dropStr% по сравнению с твоим обычным ритмом. '
        'Запланируй следующую тренировку прямо сейчас — маленький шаг сегодня '
        'вернёт тебя в форму.',
  );
}

// ─── 4. Goal alignment check ──────────────────────────────────────────────────

class GoalAlignmentRec {
  final String userGoal;
  /// Average reps per set across the current program.
  final double avgReps;
  /// What the goal optimally recommends.
  final String recommendedRange;
  final String message;

  const GoalAlignmentRec({
    required this.userGoal,
    required this.avgReps,
    required this.recommendedRange,
    required this.message,
  });
}

/// Checks whether the user's current program matches their stated training
/// goal (profiles.goal). Returns null when aligned.
///
/// [userGoal] values: 'strength', 'mass' (hypertrophy), 'weight_loss',
///   'endurance', or other. Unknown goals → null.
/// [avgRepsInProgram] — average top-of-range reps across all workout_exercises
///   in the user's active program(s).
GoalAlignmentRec? evaluateGoalAlignment({
  required String? userGoal,
  required double avgRepsInProgram,
}) {
  if (userGoal == null || avgRepsInProgram <= 0) return null;

  final goal = userGoal.toLowerCase();

  // Strength: 3-6 reps is optimal
  if (goal == 'strength' && avgRepsInProgram > 8) {
    return GoalAlignmentRec(
      userGoal: goal,
      avgReps: avgRepsInProgram,
      recommendedRange: '3-6',
      message: 'Твоя цель — сила, но в программе в среднем '
          '${avgRepsInProgram.toStringAsFixed(1)} повторов. Для развития силы '
          'эффективнее диапазон 3-6 повторов с бо́льшими весами.',
    );
  }

  // Mass/hypertrophy: 8-12 reps
  if (goal == 'mass' && (avgRepsInProgram < 6 || avgRepsInProgram > 15)) {
    return GoalAlignmentRec(
      userGoal: goal,
      avgReps: avgRepsInProgram,
      recommendedRange: '8-12',
      message: 'Твоя цель — набор мышечной массы. В среднем '
          '${avgRepsInProgram.toStringAsFixed(1)} повторов — '
          'для максимальной гипертрофии лучше работать в диапазоне 8-12.',
    );
  }

  // Endurance: 15+ reps
  if (goal == 'endurance' && avgRepsInProgram < 12) {
    return GoalAlignmentRec(
      userGoal: goal,
      avgReps: avgRepsInProgram,
      recommendedRange: '15-20',
      message: 'Твоя цель — выносливость, но в программе в среднем '
          '${avgRepsInProgram.toStringAsFixed(1)} повторов. Для выносливости '
          'эффективнее 15-20 повторов с меньшими весами.',
    );
  }

  return null;
}

// ─── 5. PR readiness signal ───────────────────────────────────────────────────

class PrReadinessRec {
  /// Exercise most primed for a PR attempt.
  final String exerciseName;
  final String exerciseId;
  /// Current working weight (kg).
  final double currentWeightKg;
  /// Suggested PR attempt weight.
  final double suggestedWeightKg;
  /// Confidence score 0.0–1.0.
  final double confidence;
  final String message;

  const PrReadinessRec({
    required this.exerciseName,
    required this.exerciseId,
    required this.currentWeightKg,
    required this.suggestedWeightKg,
    required this.confidence,
    required this.message,
  });
}

/// Detects when the user is primed for a PR attempt.
///
/// Trigger conditions (all must be true):
///   • sleep ≥ 7 h
///   • stress ≤ 5
///   • energy ≥ 7
///   • last 3 sessions with this exercise completed all prescribed reps
///   • days since last PR on this exercise ≥ 14
///
/// [candidate] — best PR-attempt candidate:
///   {
///     'exerciseId': String,
///     'exerciseName': String,
///     'currentWeightKg': double,
///     'consecutiveFullSessions': int,
///     'daysSinceLastPr': int,
///   }
PrReadinessRec? evaluatePrReadiness({
  required Map<String, dynamic>? wellness,
  required Map<String, dynamic>? candidate,
  double prIncrementKg = 2.5,
}) {
  if (wellness == null || candidate == null) return null;

  final sleep = (wellness['sleep_hours'] as num?)?.toDouble();
  final stress = (wellness['stress'] as num?)?.toInt();
  final energy = (wellness['energy'] as num?)?.toInt();

  if (sleep == null || stress == null || energy == null) return null;
  if (sleep < 7 || stress > 5 || energy < 7) return null;

  final consecutive = candidate['consecutiveFullSessions'] as int? ?? 0;
  final daysSincePr = candidate['daysSinceLastPr'] as int? ?? 0;
  if (consecutive < 3 || daysSincePr < 14) return null;

  final exerciseName = candidate['exerciseName'] as String;
  final exerciseId = candidate['exerciseId'] as String;
  final currentWeight =
      (candidate['currentWeightKg'] as num?)?.toDouble() ?? 0;
  if (currentWeight <= 0) return null;

  final suggested = currentWeight + prIncrementKg;
  final curStr = currentWeight % 1 == 0
      ? '${currentWeight.toInt()} кг'
      : '${currentWeight.toStringAsFixed(1)} кг';
  final sugStr = suggested % 1 == 0
      ? '${suggested.toInt()} кг'
      : '${suggested.toStringAsFixed(1)} кг';

  // Confidence scales with how much margin above thresholds
  final confidence =
      ((sleep - 7).clamp(0, 2) / 2 * 0.3 +
              (5 - stress).clamp(0, 5) / 5 * 0.3 +
              (energy - 7).clamp(0, 3) / 3 * 0.4)
          .clamp(0.0, 1.0)
          .toDouble();

  return PrReadinessRec(
    exerciseName: exerciseName,
    exerciseId: exerciseId,
    currentWeightKg: currentWeight,
    suggestedWeightKg: suggested,
    confidence: confidence,
    message: 'Отличный день для рекорда! Сон, стресс и энергия в норме, '
        '$exerciseName выполняется стабильно. Попробуй $sugStr вместо $curStr.',
  );
}

// ─── 6. Volume landmarks (MEV / MAV / MRV) ────────────────────────────────────

enum VolumeZone { belowMev, withinRange, aboveMrv }

class VolumeLandmarkRec {
  final String muscleGroup;
  final String muscleGroupLabel;
  final int currentWeeklySets;
  final int mev; // Minimum Effective Volume
  final int mav; // Maximum Adaptive Volume
  final int mrv; // Maximum Recoverable Volume
  final VolumeZone zone;
  final String message;

  const VolumeLandmarkRec({
    required this.muscleGroup,
    required this.muscleGroupLabel,
    required this.currentWeeklySets,
    required this.mev,
    required this.mav,
    required this.mrv,
    required this.zone,
    required this.message,
  });
}

/// Evaluates weekly volume per muscle group against Renaissance Periodization
/// landmarks (Mike Israetel et al).
///
/// [setsByMuscle] — current weekly working-set counts by muscle key:
///   { 'chest': 12, 'back': 18, 'legs': 10, ... }
///
/// Returns the single most notable deviation (largest magnitude from range),
/// or null if all groups are within their healthy range.
VolumeLandmarkRec? evaluateVolumeLandmarks(Map<String, int> setsByMuscle) {
  // Per-muscle MEV / MAV / MRV (sets per week) — consensus literature values.
  const landmarks = <String, (int mev, int mav, int mrv)>{
    'chest':     (10, 16, 22),
    'back':      (12, 18, 25),
    'shoulders': (8,  16, 20),
    'arms':      (8,  14, 20),
    'legs':      (10, 18, 25),
    'core':      (8,  14, 20),
  };

  const labels = {
    'chest': 'грудь',
    'back': 'спина',
    'shoulders': 'плечи',
    'arms': 'руки',
    'legs': 'ноги',
    'core': 'пресс',
  };

  VolumeLandmarkRec? worst;
  int worstScore = 0; // larger = worse deviation

  for (final entry in setsByMuscle.entries) {
    final lm = landmarks[entry.key];
    if (lm == null) continue;
    final sets = entry.value;
    final mev = lm.$1;
    final mav = lm.$2;
    final mrv = lm.$3;

    VolumeZone? zone;
    String? message;
    int score = 0;
    final label = labels[entry.key] ?? entry.key;

    if (sets < mev) {
      zone = VolumeZone.belowMev;
      score = mev - sets; // how far below
      message = 'Объём на "$label" — $sets сетов/нед, ниже минимального '
          '($mev). Добавь 2-3 рабочих сета для стимула к росту.';
    } else if (sets > mrv) {
      zone = VolumeZone.aboveMrv;
      score = sets - mrv;
      message = 'Объём на "$label" — $sets сетов/нед, выше предела '
          'восстановления ($mrv). Сократи до $mav — избыток объёма мешает '
          'прогрессу.';
    }

    if (zone != null && score > worstScore) {
      worstScore = score;
      worst = VolumeLandmarkRec(
        muscleGroup: entry.key,
        muscleGroupLabel: label,
        currentWeeklySets: sets,
        mev: mev,
        mav: mav,
        mrv: mrv,
        zone: zone,
        message: message!,
      );
    }
  }

  return worst;
}

// ─── 7. Exercise stagnation with variations ───────────────────────────────────

class ExerciseVariationRec {
  final String stagnantExerciseName;
  final String stagnantExerciseId;
  final int weeksStagnant;
  final List<String> suggestedVariations;
  final String message;

  const ExerciseVariationRec({
    required this.stagnantExerciseName,
    required this.stagnantExerciseId,
    required this.weeksStagnant,
    required this.suggestedVariations,
    required this.message,
  });
}

/// Exercise-variation knowledge base. Each key is a name-substring (lowercased)
/// matched against the stagnant exercise; value is a list of Russian variation
/// suggestions to display to the user.
const _variationMap = <String, List<String>>{
  'жим штанги лёжа': [
    'Жим гантелей лёжа',
    'Жим штанги на наклонной',
    'Жим в тренажёре Смита'
  ],
  'жим лёжа': [
    'Жим гантелей лёжа',
    'Жим на наклонной скамье',
    'Отжимания на брусьях'
  ],
  'приседан': [
    'Фронтальный присед',
    'Присед в Смите',
    'Болгарский сплит-присед'
  ],
  'становая': [
    'Румынская тяга',
    'Становая на прямых ногах',
    'Тяга сумо'
  ],
  'подтягиван': [
    'Подтягивания обратным хватом',
    'Тяга верхнего блока',
    'Подтягивания с дополнительным весом'
  ],
  'тяга штанги в наклоне': [
    'Тяга гантели одной рукой',
    'Т-гриф тяга',
    'Тяга в Смите'
  ],
  'жим стоя': [
    'Жим гантелей сидя',
    'Арнольд-жим',
    'Жим в тренажёре'
  ],
  'жим сидя': [
    'Жим гантелей сидя',
    'Жим штанги стоя',
    'Арнольд-жим'
  ],
  'подъём штанги на бицепс': [
    'Подъём гантелей на бицепс',
    'Молотки',
    'Подъём на скамье Скотта'
  ],
  'французский жим': [
    'Разгибания на верхнем блоке',
    'Жим узким хватом',
    'Разгибания гантели из-за головы'
  ],
};

/// Suggests exercise variations when an exercise has been stagnant for 6+ weeks.
///
/// [stagnantExercises] — output of AnalyticsService.getStagnantExercises():
///   [{exerciseId, exerciseName, weeksStagnant}]
ExerciseVariationRec? evaluateExerciseVariations(
    List<Map<String, dynamic>> stagnantExercises) {
  final candidates =
      stagnantExercises.where((e) => (e['weeksStagnant'] as int? ?? 0) >= 6);
  if (candidates.isEmpty) return null;

  // Pick the most stagnant
  final worst = candidates.reduce((a, b) =>
      (a['weeksStagnant'] as int) >= (b['weeksStagnant'] as int) ? a : b);

  final name = worst['exerciseName'] as String;
  final id = worst['exerciseId'] as String;
  final weeks = worst['weeksStagnant'] as int;
  final nameLower = name.toLowerCase();

  // Find variations by substring match
  List<String>? variations;
  for (final entry in _variationMap.entries) {
    if (nameLower.contains(entry.key)) {
      variations = entry.value;
      break;
    }
  }
  variations ??= const [
    'Попробуй другую постановку хвата/стоп',
    'Измени темп выполнения (медленный эксцентрик)',
    'Замени на похожее упражнение из той же группы мышц',
  ];

  return ExerciseVariationRec(
    stagnantExerciseName: name,
    stagnantExerciseId: id,
    weeksStagnant: weeks,
    suggestedVariations: variations,
    message: '$name не прогрессирует ${_weeksLabel(weeks)}. '
        'Попробуй заменить на: ${variations.take(2).join(" / ")} — '
        'смена упражнения часто пробивает плато.',
  );
}

// ─── 8. Frequency optimization per muscle ─────────────────────────────────────

class FrequencyOptRec {
  final String muscleGroup;
  final String muscleGroupLabel;
  final double currentDaysBetween;
  final int suggestedSessionsPerWeek;
  final String message;

  const FrequencyOptRec({
    required this.muscleGroup,
    required this.muscleGroupLabel,
    required this.currentDaysBetween,
    required this.suggestedSessionsPerWeek,
    required this.message,
  });
}

/// Suggests increasing muscle-group frequency when the user trains a group
/// less often than 2×/week.
///
/// [avgDaysBetweenByMuscle] — output of
///   AnalyticsService.getAvgDaysBetweenSessionsByMuscle():
///   { 'chest': 7.5, 'back': 3.8, 'legs': 9.0, ... }
///
/// Trigger: avg days between sessions > 6 (i.e. less than ~1×/week)
/// Returns the single most under-trained group.
FrequencyOptRec? evaluateFrequencyOptimization(
    Map<String, double> avgDaysBetweenByMuscle) {
  const labels = {
    'chest': 'грудь',
    'back': 'спина',
    'shoulders': 'плечи',
    'arms': 'руки',
    'legs': 'ноги',
    'core': 'пресс',
  };

  MapEntry<String, double>? worst;
  for (final entry in avgDaysBetweenByMuscle.entries) {
    if (!labels.containsKey(entry.key)) continue;
    if (entry.value <= 6.0) continue;
    if (worst == null || entry.value > worst.value) {
      worst = entry;
    }
  }
  if (worst == null) return null;

  final label = labels[worst.key] ?? worst.key;
  final daysStr = worst.value.toStringAsFixed(1);

  return FrequencyOptRec(
    muscleGroup: worst.key,
    muscleGroupLabel: label,
    currentDaysBetween: worst.value,
    suggestedSessionsPerWeek: 2,
    message: 'Группа "$label" тренируется раз в $daysStr дней. '
        'Исследования показывают, что 2 тренировки в неделю на мышечную '
        'группу дают больше роста, чем одна. Распредели объём на 2 дня.',
  );
}

// ─── 9. Volume ramp injury guard ──────────────────────────────────────────────

enum VolumeRampSeverity { info, warning, danger }

class VolumeRampRec {
  final double currentWeekVolume;
  final double prior4WeekAvg;
  final double rampPct;
  final VolumeRampSeverity severity;
  final String message;

  const VolumeRampRec({
    required this.currentWeekVolume,
    required this.prior4WeekAvg,
    required this.rampPct,
    required this.severity,
    required this.message,
  });
}

/// Flags rapid volume ramps that increase injury risk (ACWR-inspired).
///
/// [currentWeekVolume] — total weekly volume (kg × reps) for the current week.
/// [prior4WeekAvg]     — average weekly volume over the previous 4 weeks.
///
/// Rules:
///   ramp > 30 % → danger (acute:chronic ratio ≥ 1.5)
///   ramp > 20 % → warning
///   otherwise   → null
VolumeRampRec? evaluateVolumeRamp({
  required double currentWeekVolume,
  required double prior4WeekAvg,
}) {
  if (prior4WeekAvg <= 0) return null;
  final ramp = (currentWeekVolume - prior4WeekAvg) / prior4WeekAvg * 100;
  if (ramp <= 20) return null;

  final rampStr = ramp.round().toString();
  VolumeRampSeverity severity;
  String message;

  if (ramp > 30) {
    severity = VolumeRampSeverity.danger;
    message = 'Объём за неделю вырос на $rampStr% относительно предыдущих '
        'четырёх. Такой скачок повышает риск травмы. Вернись к прежнему '
        'объёму или прибавляй не более 10% в неделю.';
  } else {
    severity = VolumeRampSeverity.warning;
    message = 'Рост недельного объёма +$rampStr%. Это за пределами безопасного '
        'диапазона (+10%). Не наращивай дальше, дай телу адаптироваться.';
  }

  return VolumeRampRec(
    currentWeekVolume: currentWeekVolume,
    prior4WeekAvg: prior4WeekAvg,
    rampPct: ramp,
    severity: severity,
    message: message,
  );
}

// ─── 10. Time-of-day performance ──────────────────────────────────────────────

enum TimeOfDay { morning, afternoon, evening }

class TimeOfDayRec {
  final TimeOfDay bestTime;
  final double bestTimeAvgVolume;
  final double worstTimeAvgVolume;
  final double deltaPct;
  final String message;

  const TimeOfDayRec({
    required this.bestTime,
    required this.bestTimeAvgVolume,
    required this.worstTimeAvgVolume,
    required this.deltaPct,
    required this.message,
  });
}

/// Compares average session volume by time-of-day bucket and suggests training
/// at the best-performing time.
///
/// [sessionsByBucket] — each entry: { hour: int 0-23, volumeKg: double }
///
/// Buckets:
///   morning   — 5-11
///   afternoon — 12-17
///   evening   — 18-23
///
/// Triggers when best bucket has ≥ 15 % higher avg volume than the worst,
/// and each bucket has at least 3 sessions.
TimeOfDayRec? evaluateTimeOfDay(List<Map<String, dynamic>> sessions) {
  if (sessions.length < 9) return null;

  final buckets = <TimeOfDay, List<double>>{
    TimeOfDay.morning: [],
    TimeOfDay.afternoon: [],
    TimeOfDay.evening: [],
  };

  for (final s in sessions) {
    final hour = s['hour'] as int?;
    final vol = (s['volumeKg'] as num?)?.toDouble();
    if (hour == null || vol == null || vol <= 0) continue;
    if (hour >= 5 && hour <= 11) {
      buckets[TimeOfDay.morning]!.add(vol);
    } else if (hour >= 12 && hour <= 17) {
      buckets[TimeOfDay.afternoon]!.add(vol);
    } else if (hour >= 18 && hour <= 23) {
      buckets[TimeOfDay.evening]!.add(vol);
    }
  }

  // Require all three buckets to have at least 3 sessions
  if (buckets.values.any((v) => v.length < 3)) return null;

  double avg(List<double> l) => l.reduce((a, b) => a + b) / l.length;
  final avgs = {
    for (final e in buckets.entries) e.key: avg(e.value),
  };

  final best = avgs.entries.reduce((a, b) => a.value >= b.value ? a : b);
  final worst = avgs.entries.reduce((a, b) => a.value <= b.value ? a : b);
  if (worst.value <= 0) return null;

  final deltaPct = (best.value - worst.value) / worst.value * 100;
  if (deltaPct < 15) return null;

  final timeLabel = switch (best.key) {
    TimeOfDay.morning => 'утром (5:00-11:00)',
    TimeOfDay.afternoon => 'днём (12:00-17:00)',
    TimeOfDay.evening => 'вечером (18:00-23:00)',
  };

  return TimeOfDayRec(
    bestTime: best.key,
    bestTimeAvgVolume: best.value,
    worstTimeAvgVolume: worst.value,
    deltaPct: deltaPct,
    message: 'Твой объём $timeLabel в среднем на ${deltaPct.round()}% выше. '
        'Попробуй переносить тяжёлые тренировки именно в это время.',
  );
}

// ─── 11. DOMS-guided recovery ─────────────────────────────────────────────────

class DomsRec {
  final int soreness;
  final String plannedMuscle;
  final String plannedMuscleLabel;
  final String message;

  const DomsRec({
    required this.soreness,
    required this.plannedMuscle,
    required this.plannedMuscleLabel,
    required this.message,
  });
}

/// Warns when the user plans to train a still-sore muscle group.
///
/// [soreness] — self-reported soreness today, 1-5 scale.
/// [plannedMuscle] — muscle group key the user is about to train.
/// [plannedMuscleRecentlyWorked] — true if this group was trained in the last
///   48 hours (soreness likely refers to it).
///
/// Triggers when soreness ≥ 4 AND the planned muscle was recently worked.
DomsRec? evaluateDoms({
  required int? soreness,
  required String? plannedMuscle,
  required bool plannedMuscleRecentlyWorked,
}) {
  if (soreness == null || soreness < 4) return null;
  if (plannedMuscle == null || !plannedMuscleRecentlyWorked) return null;

  const labels = {
    'chest': 'грудь',
    'back': 'спина',
    'shoulders': 'плечи',
    'arms': 'руки',
    'legs': 'ноги',
    'core': 'пресс',
  };

  final label = labels[plannedMuscle] ?? plannedMuscle;

  return DomsRec(
    soreness: soreness,
    plannedMuscle: plannedMuscle,
    plannedMuscleLabel: label,
    message: 'Крепатура $soreness/5 и ты собираешься тренировать "$label", '
        'которая уже работала за последние 48 часов. Дай мышцам ещё день '
        'отдыха или переключись на другую группу.',
  );
}

// ─── 12. Session duration optimization ────────────────────────────────────────

class SessionDurationRec {
  final double avgDurationMin;
  final double lastThirdDropPct;
  final int sessionsAnalyzed;
  final String message;

  const SessionDurationRec({
    required this.avgDurationMin,
    required this.lastThirdDropPct,
    required this.sessionsAnalyzed,
    required this.message,
  });
}

/// Detects sessions that run too long with noticeable performance drop-off in
/// the final third, suggesting to shorten or split the workout.
///
/// [sessions] — each entry:
///   {
///     'durationMin': double,
///     'firstThirdAvgVolume': double, // avg set volume in the first third
///     'lastThirdAvgVolume':  double, // avg set volume in the last third
///   }
///
/// Triggers when average duration > 75 min AND average last-third drop > 10%
/// AND at least 4 sessions analyzed.
SessionDurationRec? evaluateSessionDuration(
    List<Map<String, dynamic>> sessions) {
  final longs = sessions
      .where((s) => ((s['durationMin'] as num?)?.toDouble() ?? 0) > 75)
      .toList();
  if (longs.length < 4) return null;

  double totalDrop = 0;
  double totalDuration = 0;
  int valid = 0;

  for (final s in longs) {
    final first = (s['firstThirdAvgVolume'] as num?)?.toDouble() ?? 0;
    final last = (s['lastThirdAvgVolume'] as num?)?.toDouble() ?? 0;
    final dur = (s['durationMin'] as num?)?.toDouble() ?? 0;
    if (first <= 0 || last <= 0 || dur <= 0) continue;
    final drop = (first - last) / first * 100;
    totalDrop += drop;
    totalDuration += dur;
    valid++;
  }
  if (valid < 4) return null;

  final avgDrop = totalDrop / valid;
  final avgDuration = totalDuration / valid;
  if (avgDrop < 10) return null;

  return SessionDurationRec(
    avgDurationMin: avgDuration,
    lastThirdDropPct: avgDrop,
    sessionsAnalyzed: valid,
    message: 'Твои тренировки длятся в среднем ${avgDuration.round()} мин, '
        'а производительность в последней трети падает на '
        '${avgDrop.round()}%. Сократи до 60-70 мин или раздели программу '
        'на A/B — короткие интенсивные сессии эффективнее длинных.',
  );
}
