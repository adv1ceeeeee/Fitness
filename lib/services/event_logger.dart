import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:uuid/uuid.dart';

/// Lightweight event logger with queue-based batching.
///
/// Events are buffered locally and flushed to Supabase either:
/// - when the queue reaches [_batchSize] events, or
/// - after [_flushInterval] of inactivity.
/// Call [flushOnExit] when the app is backgrounded/detached to drain the queue.
///
/// Failed batches are persisted to SharedPreferences and retried on next flush.
/// All methods are safe to call without await — errors are silently swallowed
/// so logging never breaks user-facing flows.
class EventLogger {
  static SupabaseClient get _client => Supabase.instance.client;

  static final List<Map<String, dynamic>> _queue = [];
  static Timer? _flushTimer;

  static const _batchSize = 20;
  static const _maxQueueSize = 200;
  static const _flushInterval = Duration(seconds: 30);
  static const _offlineKey = 'event_logger_offline_queue';

  /// Unique ID for the current app session (regenerated on each app open).
  static String _appSessionId = const Uuid().v4();

  @visibleForTesting
  static int get queueLength => _queue.length;

  // ─── Core ────────────────────────────────────────────────────────────────

  static void log(String event, {Map<String, dynamic>? props}) {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    if (_queue.length >= _maxQueueSize) return; // drop events at cap

    final mergedProps = <String, dynamic>{
      'app_session_id': _appSessionId,
      ...?props,
    };

    _queue.add({
      'user_id': userId,
      'event': event,
      'props': mergedProps,
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

    // Try to send; on failure persist to SharedPreferences for retry.
    _client.from('user_events').insert(batch).then(
      (_) => _loadAndRetryOffline(),
      onError: (e) {
        debugPrint('[EventLogger] flush failed: $e');
        _persistOffline(batch);
      },
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
      await _loadAndRetryOffline();
    } catch (e) {
      debugPrint('[EventLogger] flushOnExit failed: $e');
      await _persistOffline(batch);
    }
  }

  /// Regenerate session ID and emit [app_opened]. Call after auth completes
  /// or when the app resumes from background.
  static void resetSession() {
    _appSessionId = const Uuid().v4();
  }

  // ─── Offline persistence ──────────────────────────────────────────────────

  static Future<void> _persistOffline(List<Map<String, dynamic>> batch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_offlineKey);
      final List<dynamic> stored =
          existing != null ? jsonDecode(existing) as List : [];
      stored.addAll(batch);
      // Keep at most 500 offline events to avoid unbounded growth
      final trimmed = stored.length > 500 ? stored.sublist(stored.length - 500) : stored;
      await prefs.setString(_offlineKey, jsonEncode(trimmed));
    } catch (e) {
      debugPrint('[EventLogger] persistOffline failed: $e');
    }
  }

  static Future<void> _loadAndRetryOffline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_offlineKey);
      if (raw == null) return;

      final List<dynamic> stored = jsonDecode(raw) as List;
      if (stored.isEmpty) return;

      final batch = stored.cast<Map<String, dynamic>>();
      await prefs.remove(_offlineKey);
      await _client.from('user_events').insert(batch);
      debugPrint('[EventLogger] retried ${batch.length} offline events');
    } catch (e) {
      debugPrint('[EventLogger] offline retry failed: $e');
    }
  }

  // ─── App lifecycle ────────────────────────────────────────────────────────

  static void appOpened({String? source}) =>
      log('app_opened', props: {if (source != null) 'source': source});

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

  static void workoutCreated({required String workoutName}) =>
      log('workout_created', props: {'workout_name': workoutName});

  static void workoutDeleted({required String workoutName}) =>
      log('workout_deleted', props: {'workout_name': workoutName});

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

  static void standardProgramUsed({required String programName}) =>
      log('standard_program_used', props: {'program_name': programName});

  // ─── Auth ─────────────────────────────────────────────────────────────────

  static void userLoggedIn() => log('user_logged_in');

  static void userRegistered({String? goal, String? level}) =>
      log('user_registered', props: {
        if (goal != null) 'goal': goal,
        if (level != null) 'level': level,
      });

  static void userLoggedOut() => log('user_logged_out');

  // ─── Sessions / Calendar ──────────────────────────────────────────────────

  static void sessionScheduled({String? workoutName}) =>
      log('session_scheduled', props: {
        if (workoutName != null) 'workout_name': workoutName,
      });

  static void sessionSkipped({required String reason}) =>
      log('session_skipped', props: {'reason': reason});

  // ─── Profile ──────────────────────────────────────────────────────────────

  static void goalSet({required String goal}) =>
      log('goal_set', props: {'goal': goal});

  static void exportTriggered({required String format}) =>
      log('export_triggered', props: {'format': format});

  static void notificationToggled({required bool enabled}) =>
      log('notification_toggled', props: {'enabled': enabled});

  static void pinSetup({required bool enabled}) =>
      log('pin_setup', props: {'enabled': enabled});

  static void checkInSaved({required String type}) =>
      log('check_in_saved', props: {'type': type});

  // ─── Navigation ──────────────────────────────────────────────────────────

  static void screenView(String screenName) =>
      log('screen_view', props: {'screen': screenName});
}
