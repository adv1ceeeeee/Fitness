import 'package:sportwai/data/standard_programs.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/services/exercise_service.dart';
import 'package:sportwai/services/workout_service.dart';

/// One exercise as it was added to a generated workout — display data only,
/// used by the review sheet so the user can expand a day and see what's
/// inside before saving.
class GeneratedExerciseInfo {
  final String name;
  final int sets;
  final String reps;

  const GeneratedExerciseInfo({
    required this.name,
    required this.sets,
    required this.reps,
  });
}

/// Returned after a successful generation.
class GeneratedProgram {
  final List<Workout> workouts;
  final String programName;
  final List<String> notFoundExercises;
  /// Per-workout-id list of exercises that ended up in the program — used
  /// by the review sheet for the expandable "what's inside" view.
  final Map<String, List<GeneratedExerciseInfo>> exercisesByWorkoutId;

  const GeneratedProgram({
    required this.workouts,
    required this.programName,
    required this.notFoundExercises,
    this.exercisesByWorkoutId = const {},
  });

  Workout get firstWorkout => workouts.first;
  bool get isMultiSection => workouts.length > 1;
}

/// Rule-based program generator. Picks a template from [standardPrograms] using
/// the (goal, level) matrix in the user's profile, then materialises it into the
/// user's workouts via [WorkoutService]. Designed to feel "smart" without a real
/// model — the user sees a tailored draft and can edit anything afterward.
class ProgramGeneratorService {
  ProgramGeneratorService._();

  /// True when [profile] has the minimum fields required to generate.
  static bool canGenerateFor(Profile? profile) {
    if (profile == null) return false;
    return _normalisedGoal(profile.goal) != null &&
        _normalisedLevel(profile.level) != null;
  }

  /// Generates a program for [profile] and persists it via [WorkoutService].
  /// Throws [StateError] if the profile is missing required fields.
  static Future<GeneratedProgram> generate(Profile profile) async {
    final goal = _normalisedGoal(profile.goal);
    final level = _normalisedLevel(profile.level);
    if (goal == null || level == null) {
      throw StateError('Profile is missing goal or level');
    }

    final template = _pickTemplate(goal: goal, level: level);
    final allExercises = await ExerciseService.getExercises();

    return _materialise(template, allExercises);
  }

  // ─── Template selection ────────────────────────────────────────────────────

  /// Looks up the best-matching template from [standardPrograms].
  /// Falls back to a level-agnostic match if no exact (goal, level) entry
  /// exists; ultimately falls back to the first general/beginner program.
  static Map<String, dynamic> _pickTemplate({
    required String goal,
    required String level,
  }) {
    final exact = standardPrograms.where(
      (p) => p['goal'] == goal && p['level'] == level && p['premium'] != true,
    );
    if (exact.isNotEmpty) return exact.first;

    final byGoal = standardPrograms.where(
      (p) => p['goal'] == goal && p['premium'] != true,
    );
    if (byGoal.isNotEmpty) return byGoal.first;

    final byLevel = standardPrograms.where(
      (p) => p['level'] == level && p['premium'] != true,
    );
    if (byLevel.isNotEmpty) return byLevel.first;

    return standardPrograms.first;
  }

  // ─── Materialisation ───────────────────────────────────────────────────────

  static Future<GeneratedProgram> _materialise(
    Map<String, dynamic> program,
    List<Exercise> allExercises,
  ) async {
    final notFound = <String>[];
    final created = <Workout>[];
    // workout.id → exercises chosen for that workout, in DB insertion order.
    // Captured during _addExercisesTo so the review sheet can render the
    // "what's inside" expansion without an extra DB round-trip.
    final byWorkoutId = <String, List<GeneratedExerciseInfo>>{};
    final sections = program['sections'] as List?;

    if (sections != null && sections.isNotEmpty) {
      // Multi-section: first workout's id becomes the shared groupId.
      final first = sections.first as Map<String, dynamic>;
      final firstWorkout = await WorkoutService.createWorkout(
        first['name'] as String,
        (first['days'] as List).cast<int>(),
      );
      final groupId = firstWorkout.id;
      if (sections.length > 1) {
        await WorkoutService.setGroupId(firstWorkout.id, groupId);
      }
      await _addExercisesTo(firstWorkout.id, first['exercises'] as List,
          allExercises, notFound, byWorkoutId);
      created.add(firstWorkout);

      for (final s in sections.skip(1)) {
        final sec = s as Map<String, dynamic>;
        final w = await WorkoutService.createWorkout(
          sec['name'] as String,
          (sec['days'] as List).cast<int>(),
          groupId: groupId,
        );
        await _addExercisesTo(
            w.id, sec['exercises'] as List, allExercises, notFound, byWorkoutId);
        created.add(w);
      }
    } else {
      // Single workout
      final w = await WorkoutService.createWorkout(
        program['name'] as String,
        (program['days'] as List).cast<int>(),
      );
      await _addExercisesTo(w.id, program['exercises'] as List, allExercises,
          notFound, byWorkoutId);
      created.add(w);
    }

    return GeneratedProgram(
      workouts: created,
      programName: program['name'] as String,
      notFoundExercises: notFound,
      exercisesByWorkoutId: byWorkoutId,
    );
  }

  static Future<void> _addExercisesTo(
    String workoutId,
    List exercises,
    List<Exercise> allExercises,
    List<String> notFound,
    Map<String, List<GeneratedExerciseInfo>> byWorkoutId,
  ) async {
    final bucket = byWorkoutId.putIfAbsent(workoutId, () => []);
    for (final ex in exercises) {
      final name = ex['name'] as String;
      final found = _findExercise(name, allExercises);
      if (found == null) {
        notFound.add(name);
        continue;
      }
      bucket.add(GeneratedExerciseInfo(
        name: found.nameRu?.isNotEmpty == true ? found.nameRu! : found.name,
        sets: ex['sets'] as int? ?? 3,
        reps: ex['reps'] as String? ?? '8-12',
      ));
      await WorkoutService.addExerciseToWorkout(
        workoutId,
        found.id,
        sets: ex['sets'] as int? ?? 3,
        repsRange: ex['reps'] as String? ?? '8-12',
        restSeconds: ex['rest'] as int? ?? 90,
      );
    }
  }

  /// Same fuzzy matching strategy as standard_workouts_screen — kept in sync.
  static Exercise? _findExercise(String name, List<Exercise> exercises) {
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

    final words =
        q.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
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

  // ─── Vocabulary normalisation ──────────────────────────────────────────────

  /// Maps loose goal strings (legacy onboarding values, capitalisation) to the
  /// canonical set used in [standardPrograms].
  static String? _normalisedGoal(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    const valid = {'general', 'weight_loss', 'mass_gain', 'strength', 'endurance'};
    if (valid.contains(v)) return v;
    // Synonyms commonly seen in older profile entries
    if (v == 'muscle' || v == 'hypertrophy') return 'mass_gain';
    if (v == 'fat_loss' || v == 'cut') return 'weight_loss';
    return null;
  }

  static String? _normalisedLevel(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    const valid = {'beginner', 'intermediate', 'advanced'};
    return valid.contains(v) ? v : null;
  }
}
