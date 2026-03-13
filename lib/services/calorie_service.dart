// ─── Calorie estimation for strength / cardio sets ───────────────────────────
//
// Method: MET-based active calorie + RPE adjustment + EPOC multiplier
//
// MET (Metabolic Equivalent of Task) values per exercise category:
//   legs      → 6.0  (squats, deadlifts — highest metabolic demand)
//   chest     → 5.5  (bench press, dips)
//   back      → 5.5  (rows, pull-ups)
//   shoulders → 4.0  (overhead press — mix of compound / isolation)
//   arms      → 3.5  (curls, extensions — isolation)
//   cardio    → 7.0  (running, cycling, HIIT)
//
// Formula:
//   met_adj   = MET_base + (rpe - 5).clamp(0, 5) × 0.3
//   duration  = reps × 3 seconds  (average time under tension)
//   kcal_act  = met_adj × userWeightKg × (duration / 3600)
//   EPOC_fac  = 1.0 + (rpe / 10) × 0.5   (strength training afterburn)
//   kcal      = kcal_act × EPOC_fac       clamped to [0.3, 50]
//
// References:
//   Compendium of Physical Activities (Ainsworth et al., 2011)
//   EPOC estimates: Børsheim & Bahr, Sports Medicine 2003

const _kDefaultUserWeightKg = 75.0;

const _kMetByCategory = {
  'legs':      6.0,
  'chest':     5.5,
  'back':      5.5,
  'shoulders': 4.0,
  'arms':      3.5,
  'cardio':    7.0,
};

/// Estimate kcal burned for a single completed set.
///
/// [category]      — exercise category key (chest / back / legs / shoulders / arms / cardio)
/// [reps]          — number of completed repetitions
/// [rpe]           — Rate of Perceived Exertion 1–10; null treated as 7 (moderate)
/// [userWeightKg]  — athlete body weight in kg; defaults to 75 kg if null
///
/// Returns estimated kcal rounded to 1 decimal.
double estimateSetKcal({
  required String category,
  required int reps,
  int? rpe,
  double? userWeightKg,
}) {
  if (reps <= 0) return 0.0;

  final baseMet = _kMetByCategory[category] ?? 4.5;
  final effectiveRpe = (rpe ?? 7).clamp(1, 10);
  final metAdj = baseMet + ((effectiveRpe - 5).clamp(0, 5) * 0.3);

  // ~3 seconds per rep (time under tension)
  final durationHours = reps * 3.0 / 3600.0;
  final userWt = userWeightKg ?? _kDefaultUserWeightKg;

  final kcalActive = metAdj * userWt * durationHours;

  // EPOC: strength training has 30–50% afterburn relative to active calories
  final epocFactor = 1.0 + (effectiveRpe / 10.0) * 0.5;

  final result = kcalActive * epocFactor;
  // Sanity clamp: minimum meaningful set ~0.3 kcal, max a very long heavy set ~50 kcal
  return double.parse((result.clamp(0.3, 50.0)).toStringAsFixed(1));
}

/// Estimate total kcal for a session given a list of per-set estimates.
double totalSessionKcal(Iterable<double> setKcals) =>
    setKcals.fold(0.0, (sum, k) => sum + k);
