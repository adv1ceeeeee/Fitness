import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/profile_service.dart';

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
  String? _level;

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

    await ProfileService.updateProfile({
      'gender': _gender,
      'age': _ageController.text.isNotEmpty
          ? int.tryParse(_ageController.text)
          : null,
      'weight': _weightController.text.isNotEmpty
          ? double.tryParse(_weightController.text.replaceAll(',', '.'))
          : null,
      'goal': _goal,
      'level': _level,
    });

    if (mounted) context.go('/home');
  }

  void _skip() {
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
                    level: _level,
                    onLevelChanged: (v) => setState(() => _level = v),
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
                          : AppColors.textSecondary.withOpacity(0.5),
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

class _Page3 extends StatelessWidget {
  final String? level;
  final ValueChanged<String?> onLevelChanged;

  const _Page3({required this.level, required this.onLevelChanged});

  static const _levels = [
    ('beginner', 'Новичок'),
    ('intermediate', 'Любитель'),
    ('advanced', 'Продвинутый'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Твой уровень',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 32),
          ..._levels.map((l) {
            final (value, label) = l;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ChoiceChip(
                label: label,
                selected: level == value,
                onTap: () => onLevelChanged(value),
              ),
            );
          }),
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
      color: selected ? AppColors.accent.withOpacity(0.3) : AppColors.card,
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
      color: selected ? AppColors.accent.withOpacity(0.3) : AppColors.card,
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
