import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sportwai/data/standard_programs.dart';
import 'package:sportwai/models/exercise.dart';

/// Audits every exercise referenced in `lib/data/standard_programs.dart`
/// against the local fallback catalog (which mirrors the names available
/// in the Supabase `exercises` table for the offline path).
///
/// The same fuzzy matcher used at runtime — `_findExercise` in
/// `StandardWorkoutsScreen` and a copy in `ProgramGeneratorService` — is
/// reimplemented here so the test reports exactly the same "not found"
/// names that the import flow would produce. Keep the algorithm in sync
/// with both copies whenever you change matching.

Exercise? _findExercise(String name, List<Exercise> exercises) {
  String norm(String s) =>
      s.toLowerCase().replaceAll('ё', 'е').replaceAll('й', 'й');
  final q = norm(name);
  List<String> candidates(Exercise e) =>
      [norm(e.name), if (e.nameRu != null) norm(e.nameRu!)];

  final exact = exercises.where((e) => candidates(e).any((c) => c == q));
  if (exact.isNotEmpty) return exact.first;
  final contains =
      exercises.where((e) => candidates(e).any((c) => c.contains(q)));
  if (contains.isNotEmpty) return contains.first;
  final contained =
      exercises.where((e) => candidates(e).any((c) => q.contains(c)));
  if (contained.isNotEmpty) return contained.first;
  final words = q.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
  if (words.isEmpty) return null;
  final wordMatch = exercises.where((e) {
    final target = candidates(e).join(' ');
    return words.every((w) => target.contains(w));
  });
  if (wordMatch.isNotEmpty) return wordMatch.first;
  final scored = exercises
      .map((e) {
        final target = candidates(e).join(' ');
        final count = words.where((w) => target.contains(w)).length;
        return (e, count);
      })
      .where((p) => p.$2 >= (words.length * 0.6).ceil())
      .toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return scored.isNotEmpty ? scored.first.$1 : null;
}

Iterable<String> _allExerciseNames(Map<String, dynamic> program) sync* {
  final sections = program['sections'] as List?;
  if (sections != null) {
    for (final s in sections) {
      final exs = (s as Map<String, dynamic>)['exercises'] as List;
      for (final ex in exs) {
        yield (ex as Map<String, dynamic>)['name'] as String;
      }
    }
  } else {
    final exs = program['exercises'] as List;
    for (final ex in exs) {
      yield (ex as Map<String, dynamic>)['name'] as String;
    }
  }
}

void main() {
  test('every name in standardPrograms resolves to a catalog exercise', () {
    // Authoritative source: migration 055 sets `name_ru` for every standard
    // exercise in the DB. Parse those out and build dummy `Exercise` objects
    // the fuzzy matcher can match against — this mirrors what happens at
    // runtime when ExerciseService.getExercises() returns the DB catalog.
    final migration = File('supabase/migrations/055_russify_exercise_names.sql')
        .readAsStringSync();
    final ruNames = RegExp(r"SET name_ru = '([^']+)'")
        .allMatches(migration)
        .map((m) => m.group(1)!)
        .toSet()
        .toList();
    expect(ruNames.length, greaterThan(100),
        reason:
            'Migration 055 parsed fewer than 100 names — regex or migration changed');

    final catalog = [
      for (final name in ruNames)
        Exercise(id: name, name: name, nameRu: name, category: 'misc'),
    ];

    final orphans = <String, List<String>>{};
    for (final program in standardPrograms) {
      for (final name in _allExerciseNames(program)) {
        if (_findExercise(name, catalog) == null) {
          orphans.putIfAbsent(program['name'] as String, () => []).add(name);
        }
      }
    }

    if (orphans.isNotEmpty) {
      final buf = StringBuffer(
          'Standard programs reference exercises the catalog cannot resolve.\n'
          'Add these exercises to the Supabase `exercises` table (and to the '
          'local fallback list if relevant), or rename the references in '
          'lib/data/standard_programs.dart to match an existing name.\n\n');
      orphans.forEach((program, names) {
        buf.writeln('• $program:');
        for (final n in names) {
          buf.writeln('    – $n');
        }
      });
      fail(buf.toString());
    }
  });
}
