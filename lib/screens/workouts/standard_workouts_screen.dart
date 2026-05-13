import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/data/standard_programs.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/exercise_service.dart';
import 'package:sportwai/services/workout_service.dart';
import 'package:sportwai/models/exercise.dart';

class StandardWorkoutsTab extends StatefulWidget {
  const StandardWorkoutsTab({super.key, this.onProgramAdded});

  final VoidCallback? onProgramAdded;

  @override
  State<StandardWorkoutsTab> createState() => _StandardWorkoutsTabState();
}

class _StandardWorkoutsTabState extends State<StandardWorkoutsTab> {
  List<Exercise> _exercises = [];
  bool _usingProgram = false;

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    try {
      final cached = await ExerciseService.getCachedExercises();
      if (mounted && cached.isNotEmpty) setState(() => _exercises = cached);
      final list = await ExerciseService.getExercises()
          .timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _exercises = list);
    } catch (_) {
      if (mounted && _exercises.isEmpty) {
        setState(
            () => _exercises = ExerciseService.getLocalFallbackExercises());
      }
    }
  }

  /// Returns exercises, loading them first if not yet loaded.
  Future<List<Exercise>> _ensureExercises() async {
    if (_exercises.isNotEmpty) return _exercises;
    final cached = await ExerciseService.getCachedExercises();
    if (cached.isNotEmpty) {
      if (mounted) setState(() => _exercises = cached);
      return cached;
    }
    try {
      final list = await ExerciseService.getExercises()
          .timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _exercises = list);
      return list;
    } catch (_) {
      final fallback = ExerciseService.getLocalFallbackExercises();
      if (mounted) setState(() => _exercises = fallback);
      return fallback;
    }
  }

  Exercise? _findExercise(String name, List<Exercise> exercises) {
    // Normalize: lowercase + ё→е for Russian text matching
    String n(String s) =>
        s.toLowerCase().replaceAll('ё', 'е').replaceAll('й', 'й');

    final q = n(name);

    // Helper: all candidate strings for an exercise (name + nameRu)
    List<String> candidates(Exercise e) => [
          n(e.name),
          if (e.nameRu != null) n(e.nameRu!),
        ];

    // 1. Exact match
    final exact = exercises.where((e) => candidates(e).any((c) => c == q));
    if (exact.isNotEmpty) return exact.first;

    // 2. Candidate contains full query
    final contains =
        exercises.where((e) => candidates(e).any((c) => c.contains(q)));
    if (contains.isNotEmpty) return contains.first;

    // 3. Full query contains candidate (shortened DB names)
    final contained =
        exercises.where((e) => candidates(e).any((c) => q.contains(c)));
    if (contained.isNotEmpty) return contained.first;

    // 4. Word-bag: all meaningful words from query appear in candidate
    final words = q.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    if (words.isNotEmpty) {
      final wordMatch = exercises.where((e) {
        final target = candidates(e).join(' ');
        return words.every((w) => target.contains(w));
      });
      if (wordMatch.isNotEmpty) return wordMatch.first;

      // 5. Partial word-bag: ≥60% of words match, ranked by match count
      final scored = exercises
          .map((e) {
            final target = candidates(e).join(' ');
            final count = words.where((w) => target.contains(w)).length;
            return (e, count);
          })
          .where((p) => p.$2 >= (words.length * 0.6).ceil())
          .toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));
      if (scored.isNotEmpty) return scored.first.$1;
    }

    return null;
  }

  /// Creates a single workout and adds its exercises.
  /// Returns list of exercise names that were NOT found in the catalog.
  Future<List<String>> _createSection(
    String name,
    List<int> days,
    List exercises,
    List<Exercise> allExercises, {
    String? groupId,
  }) async {
    final workout =
        await WorkoutService.createWorkout(name, days, groupId: groupId);
    final notFound = <String>[];
    for (final ex in exercises) {
      final exName = ex['name'] as String;
      final exercise = _findExercise(exName, allExercises);
      final resolved = exercise == null
          ? null
          : await ExerciseService.resolveExercise(exercise)
              .timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (resolved != null) {
        await WorkoutService.addExerciseToWorkout(
          workout.id,
          resolved.id,
          sets: ex['sets'] as int? ?? 3,
          repsRange: ex['reps'] as String? ?? '8-12',
          restSeconds: ex['rest'] as int? ?? 90,
        );
      } else {
        notFound.add(exName);
      }
    }
    return notFound;
  }

  Future<void> _useProgram(Map<String, dynamic> program) async {
    if (_usingProgram) return;
    setState(() => _usingProgram = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Добавляю программу...')),
    );
    try {
      // Ensure the exercise catalog is loaded before building the program.
      final allExercises = await _ensureExercises();

      final sections = program['sections'] as List?;
      final allNotFound = <String>[];

      if (sections != null && sections.isNotEmpty) {
        // Multi-section program: create first workout manually to get groupId,
        // then remaining sections share it.
        final firstSection = sections.first as Map<String, dynamic>;
        final firstWorkout = await WorkoutService.createWorkout(
          firstSection['name'] as String,
          (firstSection['days'] as List).cast<int>(),
        );
        final groupId = firstWorkout.id;

        if (sections.length > 1) {
          await WorkoutService.setGroupId(firstWorkout.id, groupId);
        }

        // Add exercises to first section, tracking not-found
        for (final ex in (firstSection['exercises'] as List)) {
          final exName = ex['name'] as String;
          final exercise = _findExercise(exName, allExercises);
          if (exercise != null) {
            await WorkoutService.addExerciseToWorkout(
              firstWorkout.id,
              exercise.id,
              sets: ex['sets'] as int? ?? 3,
              repsRange: ex['reps'] as String? ?? '8-12',
              restSeconds: ex['rest'] as int? ?? 90,
            );
          } else {
            allNotFound.add(exName);
          }
        }

        // Create remaining sections
        for (final s in sections.skip(1)) {
          final sec = s as Map<String, dynamic>;
          allNotFound.addAll(await _createSection(
            sec['name'] as String,
            (sec['days'] as List).cast<int>(),
            sec['exercises'] as List,
            allExercises,
            groupId: groupId,
          ));
        }
      } else {
        // Single workout program
        allNotFound.addAll(await _createSection(
          program['name'] as String,
          (program['days'] as List).cast<int>(),
          program['exercises'] as List,
          allExercises,
        ));
      }

      if (mounted) {
        EventLogger.standardProgramUsed(programName: program['name'] as String);
        if (allNotFound.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Программа "${program['name']}" добавлена в "Мои программы"'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Программа добавлена. Не найдено в каталоге: ${allNotFound.join(', ')}',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 8),
            ),
          );
        }
        widget.onProgramAdded?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _usingProgram = false);
    }
  }

  int _totalDays(Map<String, dynamic> program) {
    final sections = program['sections'] as List?;
    if (sections != null) {
      return sections.fold<int>(
          0, (sum, s) => sum + ((s as Map)['days'] as List).length);
    }
    return (program['days'] as List).length;
  }

  void _showPreview(Map<String, dynamic> program) {
    final sections = program['sections'] as List?;
    final isPremium = program['premium'] == true;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        program['name'] as String,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (isPremium)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFFFB800).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded,
                                size: 13, color: Color(0xFFFFB800)),
                            SizedBox(width: 4),
                            Text(
                              '\$5',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFFB800),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_totalDays(program)} дней в неделю',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    children: [
                      if (sections != null) ...[
                        for (final s in sections) ...[
                          const SizedBox(height: 8),
                          Text(
                            (s as Map)['name'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...(s['exercises'] as List).map((e) => Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 3, left: 8),
                                child: Text(
                                  '• ${e['name']} — ${e['sets']}×${e['reps']}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13),
                                ),
                              )),
                        ],
                      ] else ...[
                        const Text(
                          'Упражнения:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...(program['exercises'] as List).map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• ${e['name']} — ${e['sets']}×${e['reps']}',
                                style: const TextStyle(
                                    color: AppColors.textSecondary),
                              ),
                            )),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (_usingProgram) return;
                            if (isPremium) {
                              // Wait for the bottom-sheet pop animation to
                              // finish before pushing a new full-screen route.
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                _showPaymentModal(program);
                              });
                            } else {
                              _useProgram(program);
                            }
                          },
                          style: isPremium
                              ? ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFB800),
                                  foregroundColor: Colors.black,
                                )
                              : null,
                          child: Text(
                            isPremium
                                ? 'Купить за \$5'
                                : 'Использовать эту программу',
                          ),
                        ),
                      ),
                      SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPaymentModal(Map<String, dynamic> program) async {
    final result = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PaymentScreen(programName: program['name'] as String),
      ),
    );
    if (result == true) {
      await _useProgram(program);
    }
  }

  Widget _buildProgramCard(Map<String, dynamic> p) {
    final daysCount = _totalDays(p);
    final isMulti = p['sections'] != null;
    final isPremium = p['premium'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _showPreview(p),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isPremium
                        ? const Color(0xFFFFB800).withValues(alpha: 0.15)
                        : AppColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.list_alt_rounded,
                    color:
                        isPremium ? const Color(0xFFFFB800) : AppColors.accent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['name'] as String,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '$daysCount раза в неделю',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (isMulti) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${(p['sections'] as List).length} дня',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (isPremium)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded,
                            size: 11, color: Color(0xFFFFB800)),
                        SizedBox(width: 3),
                        Text(
                          'Pro',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFFB800),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final basic = standardPrograms.where((p) => p['premium'] != true).toList();
    final premium =
        standardPrograms.where((p) => p['premium'] == true).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).padding.bottom + 100),
      children: [
        // ── Готовые программы ─────────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Готовые программы',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        for (final p in basic) _buildProgramCard(p),

        // ── Продвинутые программы ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Row(
            children: [
              const Text(
                'Продвинутые программы',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded,
                        size: 11, color: Color(0xFFFFB800)),
                    SizedBox(width: 3),
                    Text(
                      'Pro',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFFB800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final p in premium) _buildProgramCard(p),
      ],
    );
  }
}

// ─── Payment Screen (mock) ────────────────────────────────────────────────────

class _PaymentScreen extends StatefulWidget {
  const _PaymentScreen({required this.programName});
  final String programName;

  @override
  State<_PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<_PaymentScreen> {
  int _selectedBank = 0;
  bool _loading = false;

  static const _banks = [
    _Bank('Сбербанк', '🟢'),
    _Bank('Тинькофф', '🟡'),
    _Bank('ВТБ', '🔵'),
    _Bank('Альфа-Банк', '🔴'),
  ];

  Future<void> _pay() async {
    setState(() => _loading = true);
    // Mock network delay
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text(
          'Оплата',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Order summary ──────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Программа тренировок',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.programName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Divider(height: 24, color: AppColors.separator),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Стоимость',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                            Text(
                              '\$5.00',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Bank selection ─────────────────────────────────────────
                  const Text(
                    'Выберите банк',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(_banks.length, (i) {
                    final bank = _banks[i];
                    final selected = _selectedBank == i;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedBank = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.accent.withValues(alpha: 0.12)
                                : AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? AppColors.accent
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(bank.emoji,
                                  style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  bank.name,
                                  style: TextStyle(
                                    color: selected
                                        ? AppColors.accent
                                        : AppColors.textPrimary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (selected)
                                const Icon(Icons.check_circle_rounded,
                                    color: AppColors.accent, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 16),

                  // ── Mock card number ───────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.credit_card_rounded,
                            color: AppColors.textSecondary, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '•••• •••• •••• 4242',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 15,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        Text(
                          '12/26',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Pay button ────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                24, 12, 24, MediaQuery.of(context).padding.bottom + 24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _loading ? null : _pay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  disabledBackgroundColor:
                      AppColors.accent.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Оплатить \$5',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bank {
  const _Bank(this.name, this.emoji);
  final String name;
  final String emoji;
}
