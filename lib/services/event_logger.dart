import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/auth_service.dart';

/// Lightweight event logger with queue-based batching.
///
/// Events are buffered locally and flushed to Supabase either:
/// - when the queue reaches [_batchSize] events, or
/// - after [_flushInterval] of inactivity.
/// Call [flushOnExit] when the app is backgrounded/detached to drain the queue.
///
/// All methods are safe to call without await — errors are silently swallowed
/// so logging never breaks user-facing flows.
class EventLogger {
  static SupabaseClient get _client => Supabase.instance.client;

  static final List<Map<String, dynamic>> _queue = [];
  static Timer? _flushTimer;

  static const _batchSize = 20;
  static const _maxQueueSize = 200;
  static const _flushInterval = Duration(seconds: 30);

  @visibleForTesting
  static int get queueLength => _queue.length;

  // ─── Core ────────────────────────────────────────────────────────────────

  static void log(String event, {Map<String, dynamic>? props}) {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    if (_queue.length >= _maxQueueSize) return; // drop events at cap

    _queue.add({
      'user_id': userId,
      'event': event,
      if (props != null && props.isNotEmpty) 'props': props,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    if (_queue.length >= _batchSize) {
      _flush();
    } else {
      _flushTimer ??= Timer(_flushInterval, _flush);
    }
  }

  static void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_queue.isEmpty) return;

    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();

    _client.from('user_events').insert(batch).then(
          (_) {},
          onError: (e) => debugPrint('[EventLogger] flush failed: $e'),
        );
  }

  /// Flush remaining events synchronously — call on app pause/detach.
  static Future<void> flushOnExit() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_queue.isEmpty) return;

    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();

    try {
      await _client.from('user_events').insert(batch);
    } catch (e) {
      debugPrint('[EventLogger] flushOnExit failed: $e');
    }
  }

  // ─── Workout ─────────────────────────────────────────────────────────────

  static void workoutStarted({
    required String workoutId,
    required String workoutName,
    required String sessionId,
  }) =>
      log('workout_started', props: {
        'workout_id': workoutId,
        'workout_name': workoutName,
        'session_id': sessionId,
      });

  static void workoutCompleted({
    required String sessionId,
    required int durationSeconds,
    required int setsCount,
  }) =>
      log('workout_completed', props: {
        'session_id': sessionId,
        'duration_sec': durationSeconds,
        'sets_count': setsCount,
      });

  static void workoutAbandoned({required String sessionId}) =>
      log('workout_abandoned', props: {'session_id': sessionId});

  // ─── Sets ────────────────────────────────────────────────────────────────

  static void setCompleted({
    required String exerciseId,
    required int setNumber,
    required int reps,
    double? weightKg,
    int? restSeconds,
  }) =>
      log('set_completed', props: {
        'exercise_id': exerciseId,
        'set_number': setNumber,
        'reps': reps,
        if (weightKg != null) 'weight_kg': weightKg,
        if (restSeconds != null) 'rest_sec': restSeconds,
      });

  static void personalRecord({
    required String exerciseId,
    required double weightKg,
  }) =>
      log('personal_record', props: {
        'exercise_id': exerciseId,
        'weight_kg': weightKg,
      });

  static void restSkipped({required int elapsedSeconds}) =>
      log('rest_skipped', props: {'elapsed_sec': elapsedSeconds});

  // ─── Body metrics ────────────────────────────────────────────────────────

  static void bodyMetricsSaved({required int fieldsCount}) =>
      log('body_metrics_saved', props: {'fields_count': fieldsCount});

  // ─── Onboarding ──────────────────────────────────────────────────────────

  static void onboardingCompleted({
    required String level,
    String? goal,
    String? gender,
  }) =>
      log('onboarding_completed', props: {
        'level': level,
        if (goal != null) 'goal': goal,
        if (gender != null) 'gender': gender,
      });

  static void onboardingSkipped() => log('onboarding_skipped');

  // ─── Programs ────────────────────────────────────────────────────────────

  static void programAdded({required String programName}) =>
      log('program_added', props: {'program_name': programName});

  // ─── Navigation ──────────────────────────────────────────────────────────

  static void screenView(String screenName) =>
      log('screen_view', props: {'screen': screenName});
}
