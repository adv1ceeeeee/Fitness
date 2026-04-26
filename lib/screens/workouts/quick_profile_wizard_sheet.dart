import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/services/profile_service.dart';

/// Result returned to the caller — null if the user dismissed the sheet.
class QuickProfileResult {
  final String goal;
  final String level;
  const QuickProfileResult({required this.goal, required this.level});
}

/// Bottom sheet shown before generating a program when the profile is missing
/// goal/level. Two simple chip pickers, then "Сгенерировать". Saves the answers
/// back to the profile so the user only fills them once.
class QuickProfileWizardSheet extends StatefulWidget {
  const QuickProfileWizardSheet({super.key, required this.profile});

  final Profile? profile;

  static Future<QuickProfileResult?> show(
      BuildContext context, Profile? profile) {
    return showModalBottomSheet<QuickProfileResult>(
      context: context,
      backgroundColor: AppColors.card,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => QuickProfileWizardSheet(profile: profile),
    );
  }

  @override
  State<QuickProfileWizardSheet> createState() =>
      _QuickProfileWizardSheetState();
}

class _QuickProfileWizardSheetState extends State<QuickProfileWizardSheet> {
  String? _goal;
  String? _level;
  bool _saving = false;

  static const _goals = [
    ('mass_gain', '📈', 'Набор массы'),
    ('weight_loss', '🔥', 'Похудение'),
    ('strength', '💪', 'Сила'),
    ('endurance', '🏃', 'Выносливость'),
    ('general', '✨', 'Общая форма'),
  ];

  static const _levels = [
    ('beginner', 'Начинающий', '< 6 месяцев'),
    ('intermediate', 'Средний', '6 мес – 2 года'),
    ('advanced', 'Продвинутый', '2+ года'),
  ];

  @override
  void initState() {
    super.initState();
    _goal = widget.profile?.goal;
    _level = widget.profile?.level;
  }

  bool get _canSubmit => _goal != null && _level != null && !_saving;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final goal = _goal!;
    final level = _level!;
    try {
      final updates = <String, dynamic>{};
      if (widget.profile?.goal != goal) updates['goal'] = goal;
      if (widget.profile?.level != level) updates['level'] = level;
      if (updates.isNotEmpty) {
        await ProfileService.updateProfile(updates);
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        QuickProfileResult(goal: goal, level: level),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить, попробуйте ещё раз')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Подберём программу под вас',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ответьте на 2 вопроса — это сохранится в профиль.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Ваша цель',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _goals
                .map((g) => _ChoiceChip(
                      selected: _goal == g.$1,
                      label: '${g.$2}  ${g.$3}',
                      onTap: () => setState(() => _goal = g.$1),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          const Text(
            'Ваш уровень',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Column(
            children: _levels
                .map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LevelTile(
                        title: l.$2,
                        hint: l.$3,
                        selected: _level == l.$1,
                        onTap: () => setState(() => _level = l.$1),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сгенерировать программу'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.accent.withValues(alpha: 0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accent : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.accent.withValues(alpha: 0.15)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accent : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color:
                            selected ? AppColors.accent : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? AppColors.accent : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
