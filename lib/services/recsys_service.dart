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
