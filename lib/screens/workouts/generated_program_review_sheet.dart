import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/program_generator_service.dart';

enum GeneratedProgramAction { save, regenerate, cancel }

/// Bottom sheet shown right after program generation finishes. Lets the user
/// review what was created, then decide whether to keep it, throw it away
/// and generate another draft, or just cancel and delete it.
class GeneratedProgramReviewSheet extends StatelessWidget {
  const GeneratedProgramReviewSheet({super.key, required this.result});

  final GeneratedProgram result;

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  static Future<GeneratedProgramAction?> show(
      BuildContext context, GeneratedProgram result) {
    return showModalBottomSheet<GeneratedProgramAction>(
      context: context,
      backgroundColor: AppColors.card,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GeneratedProgramReviewSheet(result: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysSummary = result.workouts
        .expand((w) => w.days)
        .toSet()
        .toList()
      ..sort();

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
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
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.programName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${result.workouts.length} ${_pluralDays(result.workouts.length)} · '
            '${daysSummary.map((d) => _dayLabels[d]).join(', ')}',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          // Section list (collapsed: just names + days)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: result.workouts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final w = result.workouts[i];
                final dayStr = w.days.map((d) => _dayLabels[d]).join(', ');
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.fitness_center_rounded,
                            color: AppColors.accent, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              w.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (dayStr.isNotEmpty)
                              Text(
                                dayStr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (result.notFoundExercises.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                'Не нашли в каталоге: ${result.notFoundExercises.join(", ")}.\n'
                'Их можно добавить вручную в редакторе.',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFFFB74D),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(GeneratedProgramAction.save),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Сохранить и редактировать'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: AppColors.accent,
                    side: BorderSide(
                      color: AppColors.accent.withValues(alpha: 0.5),
                    ),
                  ),
                  onPressed: () => Navigator.of(context)
                      .pop(GeneratedProgramAction.regenerate),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Перегенерировать'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: AppColors.error,
                  ),
                  onPressed: () => Navigator.of(context)
                      .pop(GeneratedProgramAction.cancel),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Отменить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _pluralDays(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'день';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'дня';
    return 'дней';
  }
}
