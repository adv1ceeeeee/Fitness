import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/providers/active_session_provider.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
  });
  group('ActiveSessionState', () {
    test('initial state is not active', () {
      const state = ActiveSessionState();

      expect(state.isActive, isFalse);
      expect(state.sessionId, isNull);
      expect(state.workoutId, isNull);
      expect(state.workoutName, isNull);
      expect(state.startTime, isNull);
    });

    test('elapsed is Duration.zero when not active', () {
      const state = ActiveSessionState();

      expect(state.elapsed, Duration.zero);
    });

    test('elapsedFormatted is 00:00 when not active', () {
      const state = ActiveSessionState();

      expect(state.elapsedFormatted, '00:00');
    });

    test('isActive is true when sessionId is set', () {
      final state = ActiveSessionState(
        sessionId: 's1',
        workoutId: 'w1',
        workoutName: 'Грудь',
        startTime: DateTime.now(),
      );

      expect(state.isActive, isTrue);
    });

    test('elapsed reflects time since startTime', () {
      final start = DateTime.now().subtract(const Duration(minutes: 5));
      final state = ActiveSessionState(
        sessionId: 's1',
        workoutId: 'w1',
        workoutName: 'Test',
        startTime: start,
      );

      expect(state.elapsed.inSeconds, greaterThanOrEqualTo(299));
      expect(state.elapsed.inSeconds, lessThan(310));
    });

    test('elapsedFormatted uses mm:ss format under 1 hour', () {
      final state = ActiveSessionState(
        sessionId: 's1',
        workoutId: 'w1',
        workoutName: 'Test',
        startTime: DateTime.now().subtract(
          const Duration(minutes: 23, seconds: 7),
        ),
      );
      final parts = state.elapsedFormatted.split(':');

      expect(parts.length, 2);
      expect(parts[0], '23');
      expect(parts[1].length, 2);
    });

    test('elapsedFormatted uses h:mm:ss format at 1 hour or more', () {
      final state = ActiveSessionState(
        sessionId: 's1',
        workoutId: 'w1',
        workoutName: 'Test',
        startTime: DateTime.now().subtract(
          const Duration(hours: 1, minutes: 5, seconds: 3),
        ),
      );
      final parts = state.elapsedFormatted.split(':');

      expect(parts.length, 3);
      expect(parts[0], '1');
    });

    test('seconds and minutes are zero-padded in elapsedFormatted', () {
      final state = ActiveSessionState(
        sessionId: 's1',
        workoutId: 'w1',
        workoutName: 'Test',
        startTime: DateTime.now().subtract(const Duration(seconds: 5)),
      );
      final formatted = state.elapsedFormatted;
      final seconds = formatted.split(':').last;

      expect(seconds.length, 2);
    });
  });

  group('ActiveSessionNotifier', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('initial state is not active', () {
      expect(container.read(activeSessionProvider).isActive, isFalse);
    });

    test('start sets all fields correctly', () {
      container.read(activeSessionProvider.notifier).start(
            sessionId: 'sess-1',
            workoutId: 'work-1',
            workoutName: 'Ноги',
          );
      final state = container.read(activeSessionProvider);

      expect(state.isActive, isTrue);
      expect(state.sessionId, 'sess-1');
      expect(state.workoutId, 'work-1');
      expect(state.workoutName, 'Ноги');
      expect(state.startTime, isNotNull);
    });

    test('start records startTime close to now', () {
      final before = DateTime.now();
      container.read(activeSessionProvider.notifier).start(
            sessionId: 'sess-2',
            workoutId: 'work-2',
            workoutName: 'Спина',
          );
      final after = DateTime.now();
      final startTime = container.read(activeSessionProvider).startTime!;

      expect(startTime.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(startTime.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('stop resets to empty state', () {
      container.read(activeSessionProvider.notifier).start(
            sessionId: 'sess-3',
            workoutId: 'work-3',
            workoutName: 'Плечи',
          );
      container.read(activeSessionProvider.notifier).stop();
      final state = container.read(activeSessionProvider);

      expect(state.isActive, isFalse);
      expect(state.sessionId, isNull);
      expect(state.workoutId, isNull);
      expect(state.workoutName, isNull);
      expect(state.startTime, isNull);
      expect(state.elapsed, Duration.zero);
    });

    test('stop on already-stopped state is idempotent', () {
      container.read(activeSessionProvider.notifier).stop();
      container.read(activeSessionProvider.notifier).stop();

      expect(container.read(activeSessionProvider).isActive, isFalse);
    });

    test('start twice replaces previous session', () {
      container.read(activeSessionProvider.notifier).start(
            sessionId: 'old',
            workoutId: 'old-w',
            workoutName: 'Old workout',
          );
      container.read(activeSessionProvider.notifier).start(
            sessionId: 'new',
            workoutId: 'new-w',
            workoutName: 'New workout',
          );
      final state = container.read(activeSessionProvider);

      expect(state.sessionId, 'new');
      expect(state.workoutName, 'New workout');
    });
  });

  group('ActiveSessionNotifier.loadPersisted', () {
    test('returns null when no session persisted', () async {
      final result = await ActiveSessionNotifier.loadPersisted();
      expect(result, isNull);
    });

    test('returns state with all fields when session is persisted', () async {
      SharedPreferences.setMockInitialValues({
        'active_session_id': 'sess-42',
        'active_workout_id': 'work-7',
        'active_workout_name': 'Грудь',
        'active_session_start': '2026-01-15T10:30:00.000',
      });

      final result = await ActiveSessionNotifier.loadPersisted();

      expect(result, isNotNull);
      expect(result!.sessionId, 'sess-42');
      expect(result.workoutId, 'work-7');
      expect(result.workoutName, 'Грудь');
      expect(result.startTime, DateTime.parse('2026-01-15T10:30:00.000'));
      expect(result.isActive, isTrue);
    });

    test('returns state with null optional fields when keys missing', () async {
      SharedPreferences.setMockInitialValues({
        'active_session_id': 'sess-1',
      });

      final result = await ActiveSessionNotifier.loadPersisted();

      expect(result, isNotNull);
      expect(result!.sessionId, 'sess-1');
      expect(result.workoutId, isNull);
      expect(result.workoutName, isNull);
      expect(result.startTime, isNull);
    });

    test('returns null startTime for invalid date string', () async {
      SharedPreferences.setMockInitialValues({
        'active_session_id': 'sess-2',
        'active_session_start': 'not-a-date',
      });

      final result = await ActiveSessionNotifier.loadPersisted();

      expect(result, isNotNull);
      expect(result!.startTime, isNull);
    });

    test('persisted state is active', () async {
      SharedPreferences.setMockInitialValues({
        'active_session_id': 'sess-active',
        'active_workout_id': 'w',
        'active_workout_name': 'Ноги',
        'active_session_start': DateTime.now().toIso8601String(),
      });

      final result = await ActiveSessionNotifier.loadPersisted();
      expect(result!.isActive, isTrue);
    });

    test('start + stop clears prefs so loadPersisted returns null', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(activeSessionProvider.notifier).start(
            sessionId: 'sess-x',
            workoutId: 'w-x',
            workoutName: 'Test',
          );
      // Give async pref write time to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      c.read(activeSessionProvider.notifier).stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final result = await ActiveSessionNotifier.loadPersisted();
      expect(result, isNull);
    });
  });
}
