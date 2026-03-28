/// Recommendation engine — deterministic heuristics over user data.
///
/// Each public method returns a typed recommendation (or null = no issue).
/// No Flutter dependencies — pure Dart, fully testable.
library;

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

  final sleep   = (wellness['sleep_hours'] as num?)?.toDouble();
  final stress  = wellness['stress']   as int?;
  final energy  = wellness['energy']   as int?;
  final soreness = wellness['soreness'] as int?;

  final badSleep  = sleep  != null && sleep  < 6;
  final highStress = stress != null && stress >= 8;
  final lowEnergy  = energy != null && energy <= 3;
  final highSoreness = soreness != null && soreness >= 4;

  // ── Critical: плохой сон + высокий стресс одновременно ──────────────────
  if (badSleep && highStress) {
    final sleepStr = sleep % 1 == 0
        ? '${sleep.toInt()}ч'
        : '${sleep.toStringAsFixed(1)}ч';

    return WellnessRec(
      severity: RecSeverity.critical,
      title: 'Сегодня лучше отдохнуть',
      message: 'Сон $sleepStr и стресс $stress/10 — '
          'тяжёлая тренировка сейчас замедлит восстановление. '
          'Рассмотри лёгкую растяжку или прогулку.',
    );
  }

  // ── Warning: плохой сон или высокий стресс ───────────────────────────────
  if (badSleep || highStress) {
    final reasons = <String>[];
    if (badSleep) {
      final sleepStr = sleep % 1 == 0 ? '${sleep.toInt()}ч' : '${sleep.toStringAsFixed(1)}ч';
      reasons.add('сон $sleepStr');
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

  const ProgressionRec({required this.direction, required this.message});
}

/// Evaluates whether the user should increase, maintain, or decrease weight
/// for an exercise, based on the last 1–2 session results.
///
/// [last] — most recent session: {weight, reps, reps_target?, rpe?, prev?}
/// [prev] — previous session (optional, nested inside last['prev'])
///
/// Returns null when data is insufficient to make a recommendation.
ProgressionRec? evaluateProgression(Map<String, dynamic>? last) {
  if (last == null) return null;

  final lastReps       = last['reps']        as int?;
  final lastRepsTarget = last['reps_target'] as int?;
  final lastRpe        = last['rpe']         as int?;
  final lastWeight     = (last['weight'] as num?)?.toDouble();

  if (lastWeight == null || lastWeight <= 0) return null;

  final prev = last['prev'] as Map<String, dynamic>?;
  final prevRpe        = prev?['rpe']         as int?;
  final prevRepsTarget = prev?['reps_target'] as int?;
  final prevReps       = prev?['reps']        as int?;

  // ── Maintain: не выполнил целевые повторения (приоритет над decrease) ────
  if (lastRepsTarget != null && lastReps != null && lastReps < lastRepsTarget) {
    return ProgressionRec(
      direction: ProgressionDirection.maintain,
      message: 'В прошлый раз $lastReps из $lastRepsTarget повт — '
          'зафиксируй результат ещё на одну сессию.',
    );
  }

  // ── Decrease: RPE ≥ 9 в обеих сессиях ───────────────────────────────────
  if (lastRpe != null && lastRpe >= 9 &&
      prevRpe  != null && prevRpe  >= 9) {
    return const ProgressionRec(
      direction: ProgressionDirection.decrease,
      message: 'RPE 9+ два раза подряд — попробуй снизить вес или объём.',
    );
  }

  // ── Increase: RPE ≤ 7 в обеих сессиях + все повторения выполнены ─────────
  final lastHitTarget = lastRepsTarget == null ||
      (lastReps != null && lastReps >= lastRepsTarget);
  final prevHitTarget = prevRepsTarget == null ||
      (prevReps != null && prevReps >= prevRepsTarget);

  if (lastRpe != null && lastRpe <= 7 &&
      prevRpe  != null && prevRpe  <= 7 &&
      lastHitTarget && prevHitTarget) {
    return ProgressionRec(
      direction: ProgressionDirection.increase,
      message: 'RPE $lastRpe и $prevRpe/10 за последние 2 сессии — '
          'попробуй +2.5 кг сегодня.',
    );
  }

  // ── Increase (одна сессия): RPE ≤ 6 + все повторения выполнены ──────────
  if (lastRpe != null && lastRpe <= 6 && lastHitTarget) {
    return ProgressionRec(
      direction: ProgressionDirection.increase,
      message: 'RPE $lastRpe/10 в прошлый раз — хорошее время попробовать +2.5 кг.',
    );
  }

  return null; // данных недостаточно или всё нормально
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

// Antagonist pairs to check: (dominant, antagonist) category keys.
const _antagonistPairs = [
  ('chest', 'back'),
  ('back', 'chest'),
];

const _muscleRuLabels = {
  'chest':     'Грудь',
  'back':      'Спина',
  'shoulders': 'Плечи',
  'arms':      'Руки',
  'legs':      'Ноги',
  'core':      'Пресс',
  'cardio':    'Кардио',
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
