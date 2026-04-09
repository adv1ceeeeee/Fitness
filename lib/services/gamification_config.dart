import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Gamification — pure config & functions (no I/O, no Supabase)
// ═══════════════════════════════════════════════════════════════════════════════

// ─── XP amounts ──────────────────────────────────────────────────────────────

class XpAmount {
  static const int workoutCompleted = 50;
  static const int setCompleted = 2;
  static const int personalRecord = 30;
  static const int streakBonus = 15; // 7+ day streak, per workout
  static const int wellnessCheckIn = 5;
  static const int bodyMeasurement = 10;
  static const int trainingDurationPer10Min = 5;

  XpAmount._();
}

// ─── Daily caps ──────────────────────────────────────────────────────────────

class XpDailyCap {
  static const int workouts = 2; // max 2 workouts award XP
  static const int sets = 60; // max 60 sets
  static const int trainingMinutes = 60; // max 60 min of duration bonus
  static const int personalRecords = 5; // max 5 PRs
  static const int streakBonus = 1; // once per day
  static const int wellnessCheckIn = 1;
  static const int bodyMeasurement = 1;
  static const int appTimeXp = 27; // max from time-in-app

  XpDailyCap._();
}

// ─── Daily activity multiplier ───────────────────────────────────────────────

/// Returns a multiplier (1.0–2.0) based on the number of meaningful actions
/// performed today. Actions: completed set, check-in, measurement, program save.
double dailyActivityMultiplier(int actionCount) {
  if (actionCount <= 2) return 1.0;
  if (actionCount <= 5) return 1.2;
  if (actionCount <= 10) return 1.5;
  return 2.0;
}

// ─── App time XP (diminishing returns) ───────────────────────────────────────

/// Calculates XP earned from active foreground time (in seconds).
/// Diminishing returns: 1 XP/min for first 10 min, 0.5 for 10–30,
/// 0.25 for 30–60, 0 after 60 min. Max ~27 XP/day.
int appTimeXp(int activeSeconds) {
  final minutes = activeSeconds / 60.0;
  double xp = 0;
  if (minutes <= 10) {
    xp = minutes * 1.0;
  } else if (minutes <= 30) {
    xp = 10.0 + (minutes - 10) * 0.5;
  } else if (minutes <= 60) {
    xp = 10.0 + 10.0 + (minutes - 30) * 0.25;
  } else {
    xp = 10.0 + 10.0 + 7.5; // cap
  }
  return xp.floor().clamp(0, XpDailyCap.appTimeXp);
}

// ─── Training duration bonus ─────────────────────────────────────────────────

/// Bonus XP from workout duration. 5 XP per 10 minutes, capped at 60 min.
int trainingDurationXp(int durationSeconds) {
  final minutes = (durationSeconds / 60).clamp(0, XpDailyCap.trainingMinutes);
  return (minutes ~/ 10) * XpAmount.trainingDurationPer10Min;
}

// ─── Level curve: quadratic O(N²) ────────────────────────────────────────────

/// Cumulative XP required to reach level [n].
/// Formula: 5n² + 95n
int xpForLevel(int n) {
  if (n <= 0) return 0;
  return 5 * n * n + 95 * n;
}

/// XP needed to go from level [n] to level n+1.
/// Formula: 100 + 10n
int xpToNextLevel(int n) => 100 + 10 * max(0, n);

/// Derives level from cumulative XP.
/// Inverse of 5n² + 95n = xp → n = (-95 + sqrt(9025 + 20·xp)) / 10
int levelFromXp(int xp) {
  if (xp <= 0) return 0;
  final n = (-95 + sqrt(9025 + 20.0 * xp)) / 10;
  return n.floor().clamp(0, 999999);
}

/// Progress fraction (0.0–1.0) within the current level.
double levelProgress(int xp) {
  final level = levelFromXp(xp);
  final currentLevelXp = xpForLevel(level);
  final nextLevelXp = xpForLevel(level + 1);
  final range = nextLevelXp - currentLevelXp;
  if (range <= 0) return 0;
  return ((xp - currentLevelXp) / range).clamp(0.0, 1.0);
}

// ─── Titles ──────────────────────────────────────────────────────────────────

class PlayerTitle {
  final String name;
  final Color color;

  const PlayerTitle(this.name, this.color);
}

PlayerTitle titleForLevel(int level) {
  if (level >= 50) return const PlayerTitle('Легенда', Color(0xFFFFD700));
  if (level >= 40) return const PlayerTitle('Элита', Color(0xFFFF3B30));
  if (level >= 30) return const PlayerTitle('Мастер', Color(0xFFFF9500));
  if (level >= 20) return const PlayerTitle('Атлет', Color(0xFFAF52DE));
  if (level >= 10) return const PlayerTitle('Спортсмен', Color(0xFF007AFF));
  if (level >= 5) return const PlayerTitle('Любитель', Color(0xFF30D158));
  return const PlayerTitle('Новичок', AppColors.textSecondary);
}

// ─── Seasons ─────────────────────────────────────────────────────────────────

const double seasonDecayFactor = 0.5;
const Duration seasonLength = Duration(days: 182); // ~6 months

/// Returns the start of the current season. Seasons start on Jan 1 and Jul 1.
DateTime currentSeasonStart() {
  final now = DateTime.now();
  return now.month >= 7
      ? DateTime(now.year, 7, 1)
      : DateTime(now.year, 1, 1);
}

/// Returns the start of the next season.
DateTime nextSeasonStart() {
  final now = DateTime.now();
  return now.month >= 7
      ? DateTime(now.year + 1, 1, 1)
      : DateTime(now.year, 7, 1);
}

/// Applies decay to XP. Returns new total.
int applySeasonDecay(int xpTotal) => (xpTotal * seasonDecayFactor).round();

// ─── Idle detection ──────────────────────────────────────────────────────────

/// Max foreground session before idle cutoff (seconds).
const int maxIdleSessionSeconds = 30 * 60; // 30 min without interaction → capped

/// Min workout duration to award XP (seconds).
const int minWorkoutDurationForXp = 5 * 60; // 5 min
