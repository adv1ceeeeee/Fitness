import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSessionId = 'active_session_id';
const _kWorkoutId = 'active_workout_id';
const _kWorkoutName = 'active_workout_name';
const _kStartTime = 'active_session_start';

@immutable
class ActiveSessionState {
  final String? sessionId;
  final String? workoutId;
  final String? workoutName;
  final DateTime? startTime;

  const ActiveSessionState({
    this.sessionId,
    this.workoutId,
    this.workoutName,
    this.startTime,
  });

  bool get isActive => sessionId != null;

  Duration get elapsed =>
      isActive ? DateTime.now().difference(startTime!) : Duration.zero;

  String get elapsedFormatted {
    final d = elapsed;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class ActiveSessionNotifier extends StateNotifier<ActiveSessionState> {
  ActiveSessionNotifier() : super(const ActiveSessionState());

  void start({
    required String sessionId,
    required String workoutId,
    required String workoutName,
    DateTime? startTime,
  }) {
    final t = startTime ?? DateTime.now();
    state = ActiveSessionState(
      sessionId: sessionId,
      workoutId: workoutId,
      workoutName: workoutName,
      startTime: t,
    );
    SharedPreferences.getInstance().then((p) {
      p.setString(_kSessionId, sessionId);
      p.setString(_kWorkoutId, workoutId);
      p.setString(_kWorkoutName, workoutName);
      p.setString(_kStartTime, t.toIso8601String());
    });
  }

  void stop() {
    state = const ActiveSessionState();
    SharedPreferences.getInstance()
        .then((p) => p..remove(_kSessionId)..remove(_kWorkoutId)
            ..remove(_kWorkoutName)..remove(_kStartTime));
  }

  /// Checks SharedPreferences for a persisted session (crash recovery).
  /// Returns the saved state if found, null otherwise.
  static Future<ActiveSessionState?> loadPersisted() async {
    final p = await SharedPreferences.getInstance();
    final sessionId = p.getString(_kSessionId);
    if (sessionId == null) return null;
    return ActiveSessionState(
      sessionId: sessionId,
      workoutId: p.getString(_kWorkoutId),
      workoutName: p.getString(_kWorkoutName),
      startTime: DateTime.tryParse(p.getString(_kStartTime) ?? ''),
    );
  }
}

final activeSessionProvider =
    StateNotifierProvider<ActiveSessionNotifier, ActiveSessionState>(
  (ref) => ActiveSessionNotifier(),
);
