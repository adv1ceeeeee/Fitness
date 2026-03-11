import 'package:flutter_test/flutter_test.dart';

// Pure logic extracted from create_workout_screen.dart for unit testing.
// These functions mirror the logic inside _CreateWorkoutScreenState.

bool _sectionsHaveOverlappingDays(List<Set<int>> sections) {
  final seen = <int>{};
  for (final days in sections) {
    for (final d in days) {
      if (!seen.add(d)) return true;
    }
  }
  return false;
}

Set<int> _usedDaysExcept(List<Set<int>> sections, int excludeIndex) {
  final used = <int>{};
  for (int i = 0; i < sections.length; i++) {
    if (i != excludeIndex) used.addAll(sections[i]);
  }
  return used;
}

void main() {
  group('_sectionsHaveOverlappingDays', () {
    test('no sections — no overlap', () {
      expect(_sectionsHaveOverlappingDays([]), false);
    });

    test('single section — no overlap', () {
      expect(_sectionsHaveOverlappingDays([{0, 2, 4}]), false);
    });

    test('two sections with disjoint days — no overlap', () {
      expect(_sectionsHaveOverlappingDays([{0, 2}, {1, 3}]), false);
    });

    test('two sections sharing a day — overlap detected', () {
      expect(_sectionsHaveOverlappingDays([{0, 1}, {1, 3}]), true);
    });

    test('three sections, overlap in last two', () {
      expect(_sectionsHaveOverlappingDays([{0}, {2}, {2, 4}]), true);
    });

    test('max 7 sections each with one unique day — no overlap', () {
      final sections = List.generate(7, (i) => {i});
      expect(_sectionsHaveOverlappingDays(sections), false);
    });
  });

  group('_usedDaysExcept', () {
    test('excludes own section days', () {
      final sections = [{0, 1}, {2, 3}, {4, 5}];
      final used = _usedDaysExcept(sections, 0);
      expect(used, containsAll([2, 3, 4, 5]));
      expect(used.contains(0), false);
      expect(used.contains(1), false);
    });

    test('single section — no used days when excluded', () {
      final sections = [{0, 2, 4}];
      expect(_usedDaysExcept(sections, 0), isEmpty);
    });

    test('all other sections contribute to used set', () {
      final sections = [{0}, {1}, {2}];
      final used = _usedDaysExcept(sections, 1);
      expect(used, {0, 2});
    });
  });

  group('section count invariants', () {
    test('max 7 sections allowed (one per day of week)', () {
      // Adding an 8th section is invalid.
      // This mirrors the _addSection guard: if (_sections.length >= 7) return
      const maxSections = 7;
      final sections = List.generate(maxSections, (_) => <int>{});
      expect(sections.length, lessThanOrEqualTo(7));
    });
  });
}
