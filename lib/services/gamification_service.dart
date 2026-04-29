import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/app_cache.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/local_storage.dart';
import 'package:sportwai/services/gamification_config.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// GamificationService — XP awards, level tracking, seasons
// ═══════════════════════════════════════════════════════════════════════════════

class PlayerStats {
  final int xpTotal;
  final int level;
  final PlayerTitle title;
  final double progress; // 0.0–1.0 within current level
  final int xpToNext;
  final DateTime seasonEnds;

  const PlayerStats({
    required this.xpTotal,
    required this.level,
    required this.title,
    required this.progress,
    required this.xpToNext,
    required this.seasonEnds,
  });
}

class GamificationService {
  static SupabaseClient get _client => Supabase.instance.client;

  GamificationService._();

  // ─── Award XP ──────────────────────────────────────────────────────────────

  /// Award XP for a specific reason. Respects daily caps.
  /// Returns actual XP awarded (may be 0 if capped).
  static Future<int> award(
    String reason, {
    int? amount,
    String? sourceId,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 0;

    amount ??= _defaultAmount(reason);
    if (amount <= 0) return 0;

    try {
      // Check daily cap for this reason
      final capped = await _applyCap(userId, reason, amount);
      if (capped <= 0) return 0;

      // Apply daily activity multiplier
      final actions = await _todayActionCount(userId);
      final multiplier = dailyActivityMultiplier(actions);
      final finalAmount = (capped * multiplier).round();

      // Get running daily total for audit
      final dailyTotal = await _todayTotalXp(userId);

      // Insert log entry
      await _client.from('xp_log').insert({
        'user_id': userId,
        'amount': finalAmount,
        'reason': reason,
        'source_id': sourceId,
        'daily_total': dailyTotal + finalAmount,
      });

      // Increment xp_total on profile
      await _client.rpc('increment_xp', params: {
        'p_user_id': userId,
        'p_amount': finalAmount,
      }).catchError((_) async {
        // Fallback: manual increment if RPC doesn't exist yet
        final current = await _client
            .from('profiles')
            .select('xp_total')
            .eq('id', userId)
            .single();
        await _client.from('profiles').update({
          'xp_total': (current['xp_total'] as int? ?? 0) + finalAmount,
        }).eq('id', userId);
      });

      // Invalidate cache
      AppCache.invalidate('player_stats:$userId');

      return finalAmount;
    } catch (e) {
      debugPrint('[GamificationService] award error: $e');
      return 0;
    }
  }

  /// Award XP for multiple sets at once (batch after workout).
  static Future<int> awardSets(int setCount, {String? sessionId}) async {
    final capped = setCount.clamp(0, XpDailyCap.sets);
    if (capped <= 0) return 0;
    return award(
      'set_completed',
      amount: capped * XpAmount.setCompleted,
      sourceId: sessionId,
    );
  }

  /// Award XP for workout duration.
  static Future<int> awardDuration(int durationSeconds, {String? sessionId}) async {
    final xp = trainingDurationXp(durationSeconds);
    if (xp <= 0) return 0;
    return award('training_duration', amount: xp, sourceId: sessionId);
  }

  // ─── App time tracking ─────────────────────────────────────────────────────

  /// Add foreground time and award XP if threshold reached.
  /// Called from AppLifecycleListener on paused/detached.
  static Future<void> addActiveTime(int seconds) async {
    if (seconds <= 0) return;
    // Cap single session at idle limit
    final capped = seconds.clamp(0, maxIdleSessionSeconds);

    // Accumulate in local storage
    final prev = AppStorage.dailyActiveSeconds;
    final total = prev + capped;
    await AppStorage.setDailyActiveSeconds(total);

    // Calculate XP delta
    final prevXp = appTimeXp(prev);
    final newXp = appTimeXp(total);
    final delta = newXp - prevXp;
    if (delta > 0) {
      await award('app_time', amount: delta);
    }
  }

  // ─── Player stats ──────────────────────────────────────────────────────────

  /// Get current player stats. Cached for 5 minutes.
  static Future<PlayerStats> getPlayerStats() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return _emptyStats();

    return AppCache.get<PlayerStats>(
      key: 'player_stats:$userId',
      ttl: const Duration(minutes: 5),
      fetch: () => _fetchStats(userId),
      encode: (s) =>
          '${s.xpTotal}',
      decode: (raw) {
        if (raw == null) return _emptyStats();
        final xp = int.tryParse(raw) ?? 0;
        return _statsFromXp(xp);
      },
    );
  }

  static Future<PlayerStats> _fetchStats(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('xp_total')
          .eq('id', userId)
          .single();
      final xp = row['xp_total'] as int? ?? 0;
      return _statsFromXp(xp);
    } catch (e) {
      debugPrint('[GamificationService] _fetchStats error: $e');
      return _emptyStats();
    }
  }

  static PlayerStats _statsFromXp(int xp) {
    final level = levelFromXp(xp);
    return PlayerStats(
      xpTotal: xp,
      level: level,
      title: titleForLevel(level),
      progress: levelProgress(xp),
      xpToNext: xpForLevel(level + 1) - xp,
      seasonEnds: nextSeasonStart(),
    );
  }

  /// Lv 0 / 0 XP placeholder — used as a render fallback before the real
  /// stats finish loading, so the level badge can paint with the correct
  /// layout immediately on first navigation.
  static PlayerStats emptyStats() => _emptyStats();

  static PlayerStats _emptyStats() => PlayerStats(
        xpTotal: 0,
        level: 0,
        title: titleForLevel(0),
        progress: 0,
        xpToNext: xpForLevel(1),
        seasonEnds: nextSeasonStart(),
      );

  // ─── Season decay ──────────────────────────────────────────────────────────

  /// Check and apply season decay if a new season has started.
  /// Should be called once on app open.
  static Future<void> checkSeasonDecay() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;

    try {
      final seasonStart = currentSeasonStart();

      // Check if decay was already applied this season
      final existing = await _client
          .from('xp_season_log')
          .select('id')
          .eq('user_id', userId)
          .eq('season_start', seasonStart.toIso8601String().split('T')[0])
          .maybeSingle();

      if (existing != null) return; // Already applied

      // Check if user existed before this season
      final profile = await _client
          .from('profiles')
          .select('xp_total, created_at')
          .eq('id', userId)
          .single();

      final xpBefore = profile['xp_total'] as int? ?? 0;
      if (xpBefore == 0) return; // Nothing to decay

      final createdAt = DateTime.tryParse(profile['created_at'] as String? ?? '');
      if (createdAt != null && createdAt.isAfter(seasonStart)) return; // New user this season

      // Apply decay
      final xpAfter = applySeasonDecay(xpBefore);

      await _client.from('profiles').update({
        'xp_total': xpAfter,
      }).eq('id', userId);

      await _client.from('xp_season_log').insert({
        'user_id': userId,
        'season_start': seasonStart.toIso8601String().split('T')[0],
        'xp_before': xpBefore,
        'xp_after': xpAfter,
        'decay_factor': seasonDecayFactor,
      });

      AppCache.invalidate('player_stats:$userId');
      debugPrint('[GamificationService] Season decay applied: $xpBefore → $xpAfter');
    } catch (e) {
      debugPrint('[GamificationService] checkSeasonDecay error: $e');
    }
  }

  // ─── Daily caps ────────────────────────────────────────────────────────────

  static Future<int> _applyCap(String userId, String reason, int amount) async {
    final cap = _capForReason(reason);
    if (cap == null) return amount; // No cap for this reason

    final today = DateTime.now().toIso8601String().split('T')[0];
    final rows = await _client
        .from('xp_log')
        .select('amount')
        .eq('user_id', userId)
        .eq('reason', reason)
        .gte('created_at', '${today}T00:00:00')
        .lte('created_at', '${today}T23:59:59');

    int todayTotal = 0;
    int todayCount = 0;
    for (final r in rows) {
      todayTotal += r['amount'] as int;
      todayCount++;
    }

    // For count-based caps (wellness, body measurement, streak)
    final countCap = _countCapForReason(reason);
    if (countCap != null && todayCount >= countCap) return 0;

    // For amount-based caps (sets, training duration)
    final maxXp = _maxXpForReason(reason);
    if (maxXp != null) {
      final remaining = maxXp - todayTotal;
      if (remaining <= 0) return 0;
      return amount.clamp(0, remaining);
    }

    return amount;
  }

  static int? _capForReason(String reason) => switch (reason) {
        'workout_completed' => XpDailyCap.workouts,
        'set_completed' => XpDailyCap.sets,
        'personal_record' => XpDailyCap.personalRecords,
        'streak_bonus' => XpDailyCap.streakBonus,
        'wellness_checkin' => XpDailyCap.wellnessCheckIn,
        'body_measurement' => XpDailyCap.bodyMeasurement,
        'app_time' => XpDailyCap.appTimeXp,
        'training_duration' => XpDailyCap.trainingMinutes,
        _ => null,
      };

  static int? _countCapForReason(String reason) => switch (reason) {
        'workout_completed' => XpDailyCap.workouts,
        'streak_bonus' => XpDailyCap.streakBonus,
        'wellness_checkin' => XpDailyCap.wellnessCheckIn,
        'body_measurement' => XpDailyCap.bodyMeasurement,
        'personal_record' => XpDailyCap.personalRecords,
        _ => null,
      };

  static int? _maxXpForReason(String reason) => switch (reason) {
        'set_completed' => XpDailyCap.sets * XpAmount.setCompleted,
        'training_duration' =>
          (XpDailyCap.trainingMinutes ~/ 10) * XpAmount.trainingDurationPer10Min,
        'app_time' => XpDailyCap.appTimeXp,
        _ => null,
      };

  static int _defaultAmount(String reason) => switch (reason) {
        'workout_completed' => XpAmount.workoutCompleted,
        'set_completed' => XpAmount.setCompleted,
        'personal_record' => XpAmount.personalRecord,
        'streak_bonus' => XpAmount.streakBonus,
        'wellness_checkin' => XpAmount.wellnessCheckIn,
        'body_measurement' => XpAmount.bodyMeasurement,
        _ => 0,
      };

  // ─── Helpers ───────────────────────────────────────────────────────────────

  static Future<int> _todayActionCount(String userId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    try {
      final rows = await _client
          .from('xp_log')
          .select('id')
          .eq('user_id', userId)
          .gte('created_at', '${today}T00:00:00')
          .lte('created_at', '${today}T23:59:59');
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> _todayTotalXp(String userId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    try {
      final rows = await _client
          .from('xp_log')
          .select('amount')
          .eq('user_id', userId)
          .gte('created_at', '${today}T00:00:00')
          .lte('created_at', '${today}T23:59:59');
      int total = 0;
      for (final r in rows) {
        total += r['amount'] as int;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Invalidate cached stats (call after XP changes from outside).
  static void invalidate() {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    AppCache.invalidate('player_stats:$userId');
  }
}
