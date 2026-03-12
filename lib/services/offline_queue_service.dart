import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'training_service.dart';

/// A pending set write that failed to reach Supabase.
class _PendingSet {
  final String sessionId;
  final String workoutExerciseId;
  final int setNumber;
  final double? weight;
  final int? reps;
  final int? rpe;
  final int? restSeconds;

  const _PendingSet({
    required this.sessionId,
    required this.workoutExerciseId,
    required this.setNumber,
    this.weight,
    this.reps,
    this.rpe,
    this.restSeconds,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'workoutExerciseId': workoutExerciseId,
        'setNumber': setNumber,
        'weight': weight,
        'reps': reps,
        'rpe': rpe,
        'restSeconds': restSeconds,
      };

  factory _PendingSet.fromJson(Map<String, dynamic> j) => _PendingSet(
        sessionId: j['sessionId'] as String,
        workoutExerciseId: j['workoutExerciseId'] as String,
        setNumber: j['setNumber'] as int,
        weight: (j['weight'] as num?)?.toDouble(),
        reps: j['reps'] as int?,
        rpe: j['rpe'] as int?,
        restSeconds: j['restSeconds'] as int?,
      );
}

/// Manages a local queue of set writes that failed due to network errors.
/// On reconnect, flushes all pending sets to Supabase.
class OfflineQueueService {
  static const _key = 'offline_set_queue';
  static bool _listening = false;

  /// Call once at app start (after WidgetsFlutterBinding.ensureInitialized).
  static void init() {
    if (_listening) return;
    _listening = true;
    Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) flush();
    });
  }

  /// Enqueue a failed set write for later retry.
  static Future<void> enqueue({
    required String sessionId,
    required String workoutExerciseId,
    required int setNumber,
    double? weight,
    int? reps,
    int? rpe,
    int? restSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(_PendingSet(
      sessionId: sessionId,
      workoutExerciseId: workoutExerciseId,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      rpe: rpe,
      restSeconds: restSeconds,
    ).toJson()));
    await prefs.setStringList(_key, raw);
    debugPrint('[OfflineQueue] enqueued set, queue size=${raw.length}');
  }

  /// Attempt to flush all pending sets. Stops on first failure.
  static Future<void> flush() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    if (raw.isEmpty) return;
    debugPrint('[OfflineQueue] flushing ${raw.length} pending set(s)');

    final remaining = <String>[];
    for (final item in raw) {
      try {
        final s = _PendingSet.fromJson(
            jsonDecode(item) as Map<String, dynamic>);
        final ok = await TrainingService.saveSet(
          s.sessionId,
          s.workoutExerciseId,
          s.setNumber,
          weight: s.weight,
          reps: s.reps,
          rpe: s.rpe,
          restSeconds: s.restSeconds,
        );
        if (!ok) remaining.add(item); // still failing — keep it
      } catch (e) {
        debugPrint('[OfflineQueue] flush error: $e');
        remaining.add(item);
      }
    }

    await prefs.setStringList(_key, remaining);
    debugPrint('[OfflineQueue] flushed, ${remaining.length} item(s) left');
  }

  /// Number of items currently queued.
  static Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).length;
  }
}
