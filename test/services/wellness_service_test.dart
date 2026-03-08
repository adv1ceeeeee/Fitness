import 'package:flutter_test/flutter_test.dart';

// Pure helpers that mirror the logic in WellnessService.upsert and
// the calendar's one-time session dot logic — tested without Supabase.

// ── Wellness upsert payload builder (mirrors WellnessService._buildPayload) ──

Map<String, dynamic> buildWellnessPayload({
  required String userId,
  required String date,
  double? sleepHours,
  int? stress,
  int? energy,
}) {
  return {
    'user_id': userId,
    'date': date,
    if (sleepHours != null) 'sleep_hours': sleepHours,
    if (stress != null) 'stress': stress,
    if (energy != null) 'energy': energy,
  };
}

// ── Calendar dot logic ────────────────────────────────────────────────────────

class _DayEvent {
  final bool completed;
  final bool planned;
  const _DayEvent({required this.completed, this.planned = false});
}

bool hasCompletedDot(List<_DayEvent> events) =>
    events.any((e) => e.completed);

/// Semi-transparent dot: any upcoming event (cyclic OR one-time scheduled).
bool hasPlannedDot(List<_DayEvent> events) =>
    events.any((e) => !e.completed);

void main() {
  group('WellnessService payload builder', () {
    test('always includes user_id and date', () {
      final p = buildWellnessPayload(userId: 'u1', date: '2024-03-01');
      expect(p['user_id'], 'u1');
      expect(p['date'], '2024-03-01');
    });

    test('omits null optional fields', () {
      final p = buildWellnessPayload(userId: 'u1', date: '2024-03-01');
      expect(p.containsKey('sleep_hours'), isFalse);
      expect(p.containsKey('stress'), isFalse);
      expect(p.containsKey('energy'), isFalse);
    });

    test('includes provided optional fields', () {
      final p = buildWellnessPayload(
        userId: 'u1',
        date: '2024-03-01',
        sleepHours: 7.5,
        stress: 4,
        energy: 8,
      );
      expect(p['sleep_hours'], 7.5);
      expect(p['stress'], 4);
      expect(p['energy'], 8);
    });

    test('partial: only energy provided', () {
      final p =
          buildWellnessPayload(userId: 'u2', date: '2024-03-02', energy: 9);
      expect(p['energy'], 9);
      expect(p.containsKey('sleep_hours'), isFalse);
      expect(p.containsKey('stress'), isFalse);
    });
  });

  group('Calendar dot logic', () {
    test('no dot when list is empty', () {
      expect(hasCompletedDot([]), isFalse);
      expect(hasPlannedDot([]), isFalse);
    });

    test('completed dot for finished session', () {
      final events = [const _DayEvent(completed: true)];
      expect(hasCompletedDot(events), isTrue);
      expect(hasPlannedDot(events), isFalse);
    });

    test('planned dot for cyclic planned slot', () {
      final events = [const _DayEvent(completed: false, planned: true)];
      expect(hasCompletedDot(events), isFalse);
      expect(hasPlannedDot(events), isTrue);
    });

    test('planned dot for one-time scheduled session (planned=false, completed=false)', () {
      final events = [const _DayEvent(completed: false, planned: false)];
      expect(hasCompletedDot(events), isFalse);
      expect(hasPlannedDot(events), isTrue);
    });

    test('both dots when day has completed and upcoming events', () {
      final events = [
        const _DayEvent(completed: true),
        const _DayEvent(completed: false, planned: true),
      ];
      expect(hasCompletedDot(events), isTrue);
      expect(hasPlannedDot(events), isTrue);
    });

    test('only completed dot when all sessions are done', () {
      final events = [
        const _DayEvent(completed: true),
        const _DayEvent(completed: true),
      ];
      expect(hasCompletedDot(events), isTrue);
      expect(hasPlannedDot(events), isFalse);
    });
  });
}
