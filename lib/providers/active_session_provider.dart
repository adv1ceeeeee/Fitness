import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  }) {
    state = ActiveSessionState(
      sessionId: sessionId,
      workoutId: workoutId,
      workoutName: workoutName,
      startTime: DateTime.now(),
    );
  }

  void stop() => state = const ActiveSessionState();
}

final activeSessionProvider =
    StateNotifierProvider<ActiveSessionNotifier, ActiveSessionState>(
  (ref) => ActiveSessionNotifier(),
);
