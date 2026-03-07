import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/data/standard_programs.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/exercise_service.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/workout_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  String? _gender;
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  String? _goal;
  DateTime _trainingStart = DateTime(DateTime.now().year - 1, DateTime.now().month);

  @override
  void dispose() {
    _pageController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;

    final now = DateTime.now();
    final months = (now.year - _trainingStart.year) * 12 +
        (now.month - _trainingStart.month);
    final level = months < 6
        ? 'beginner'
        : months < 24
            ? 'intermediate'
            : 'advanced';
    final startDateStr =
        '${_trainingStart.year}-${_trainingStart.month.toString().padLeft(2, '0')}-01';

    await ProfileService.updateProfile({
      'gender': _gender,
      'age': _ageController.text.isNotEmpty
          ? int.tryParse(_ageController.text)
          : null,
      'weight': _weightController.text.isNotEmpty
          ? double.tryParse(_weightController.text.replaceAll(',', '.'))
          : null,
      'goal': _goal,
      'level': level,
      'training_start_date': startDateStr,
    });

    EventLogger.onboardingCompleted(
      level: level,
      goal: _goal,
      gender: _gender,
    );

    if (!mounted) return;

    final shouldAdd = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _RecommendationSheet(
        program: standardPrograms[_recommendedIndex()],
      ),
    );

    if (shouldAdd == true && mounted) {
      await _addProgram(standardPrograms[_recommendedIndex()]);
    }

    if (mounted) context.go('/home');
  }

  int _recommendedIndex() {
    switch (_goal) {
      case 'strength':
        return 3;
      case 'weight_loss':
        return 1;
      case 'mass_gain':
        return 2;
      case 'endurance':
        return 1;
      default:
        return 0;
    }
  }

  Future<void> _addProgram(Map<String, dynamic> program) async {
    try {
      final exercises = await ExerciseService.getExercises();
      final workout = await WorkoutService.createWorkout(
        program['name'] as String,
        (program['days'] as List).cast<int>(),
      );
      for (final ex in program['exercises'] as List) {
        final name = ex['name'] as String;
        Exercise? found;
        try {
          found = exercises.firstWhere(
            (e) => e.name.toLowerCase().contains(name.toLowerCase()),
          );
        } catch (_) {}
        if (found != null) {
          await WorkoutService.addExerciseToWorkout(
            workout.id,
            found.id,
            sets: ex['sets'] as int? ?? 3,
            repsRange: ex['reps'] as String? ?? '8-12',
            restSeconds: ex['rest'] as int? ?? 90,
          );
        }
      }
    } catch (_) {}
  }

  void _skip() {
    EventLogger.onboardingSkipped();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: _skip,
            child: const Text('Пропустить', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _Page1(
                    gender: _gender,
                    onGenderChanged: (v) => setState(() => _gender = v),
                    ageController: _ageController,
                    weightController: _weightController,
                  ),
                  _Page2(
                    goal: _goal,
                    onGoalChanged: (v) => setState(() => _goal = v),
                  ),
                  _Page3(
                    trainingStart: _trainingStart,
                    onChanged: (v) => setState(() => _trainingStart = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == i
                          ? AppColors.accent
                          : AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    if (_currentPage < 2) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      _finish();
                    }
                  },
                  child: Text(_currentPage < 2 ? 'Далее' : 'Начать'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page1 extends StatelessWidget {
  final String? gender;
  final ValueChanged<String?> onGenderChanged;
  final TextEditingController ageController;
  final TextEditingController weightController;

  const _Page1({
    required this.gender,
    required this.onGenderChanged,
    required this.ageController,
    required this.weightController,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Твой пол, возраст, вес',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 32),
          const Text('Пол', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ChoiceChip(
                  label: 'Муж',
                  selected: gender == 'male',
                  onTap: () => onGenderChanged('male'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ChoiceChip(
                  label: 'Жен',
                  selected: gender == 'female',
                  onTap: () => onGenderChanged('female'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Возраст', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            controller: ageController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '25',
            ),
          ),
          const SizedBox(height: 24),
          const Text('Вес (кг)', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            controller: weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '75',
            ),
          ),
        ],
      ),
    );
  }
}

class _Page2 extends StatelessWidget {
  final String? goal;
  final ValueChanged<String?> onGoalChanged;

  const _Page2({required this.goal, required this.onGoalChanged});

  static const _goals = [
    ('strength', '💪', 'Сила'),
    ('weight_loss', '🔥', 'Похудение'),
    ('mass_gain', '📈', 'Набор массы'),
    ('endurance', '🏃', 'Выносливость'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Твоя главная цель',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 32),
          ..._goals.map((g) {
            final (value, emoji, label) = g;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GoalCard(
                emoji: emoji,
                label: label,
                selected: goal == value,
                onTap: () => onGoalChanged(value),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _Page3 extends StatefulWidget {
  final DateTime trainingStart;
  final ValueChanged<DateTime> onChanged;

  const _Page3({required this.trainingStart, required this.onChanged});

  @override
  State<_Page3> createState() => _Page3State();
}

class _Page3State extends State<_Page3> {
  static const _months = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];
  static final int _startYear = 1970;
  static final int _endYear = DateTime.now().year;

  late final FixedExtentScrollController _monthCtrl;
  late final FixedExtentScrollController _yearCtrl;

  int _selectedMonth = 1;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _selectedMonth = widget.trainingStart.month;
    _selectedYear = widget.trainingStart.year;
    _monthCtrl = FixedExtentScrollController(initialItem: _selectedMonth - 1);
    _yearCtrl = FixedExtentScrollController(initialItem: _selectedYear - _startYear);
  }

  @override
  void dispose() {
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(DateTime(_selectedYear, _selectedMonth));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = (_selectedYear < now.year)
        ? (now.year - _selectedYear) * 12 + (now.month - _selectedMonth)
        : (now.month - _selectedMonth).clamp(0, 12);
    final String experience;
    if (months < 1) {
      experience = 'Только начинаю';
    } else if (months < 12) {
      experience = 'Стаж: $months мес.';
    } else {
      final y = months ~/ 12;
      final m = months % 12;
      experience = m == 0 ? 'Стаж: $y л.' : 'Стаж: $y л. $m мес.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Когда начал тренироваться?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Выбери месяц и год начала тренировок',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),

          // Wheels
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                // Month wheel
                Expanded(
                  flex: 3,
                  child: CupertinoPicker(
                    scrollController: _monthCtrl,
                    itemExtent: 52,
                    backgroundColor: Colors.transparent,
                    onSelectedItemChanged: (i) {
                      _selectedMonth = i + 1;
                      _notify();
                    },
                    children: _months
                        .map((m) => Center(
                              child: Text(
                                m,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 17,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                // Year wheel
                Expanded(
                  flex: 2,
                  child: CupertinoPicker(
                    scrollController: _yearCtrl,
                    itemExtent: 52,
                    backgroundColor: Colors.transparent,
                    onSelectedItemChanged: (i) {
                      _selectedYear = _startYear + i;
                      _notify();
                    },
                    children: List.generate(
                      _endYear - _startYear + 1,
                      (i) => Center(
                        child: Text(
                          '${_startYear + i}',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              experience,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.3) : AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GoalCard({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.3) : AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.accent : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendationSheet extends StatelessWidget {
  final Map<String, dynamic> program;

  const _RecommendationSheet({required this.program});

  @override
  Widget build(BuildContext context) {
    final name = program['name'] as String;
    final days = (program['days'] as List).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Рекомендуем программу',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$days тренировок в неделю',
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Добавить программу'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Пропустить',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
