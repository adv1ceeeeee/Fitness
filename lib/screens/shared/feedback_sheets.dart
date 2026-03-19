import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/feedback_service.dart';

// ─── NPS bottom sheet ─────────────────────────────────────────────────────────

/// Shows the NPS survey in a bottom sheet.
/// Handles score saving, in_app_review prompt, and negative-score comment flow.
Future<void> showNpsSheet(BuildContext context) async {
  await FeedbackService.markNpsShown();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _NpsSheet(),
  );
}

class _NpsSheet extends StatefulWidget {
  const _NpsSheet();
  @override
  State<_NpsSheet> createState() => _NpsSheetState();
}

class _NpsSheetState extends State<_NpsSheet> {
  int? _selected;
  bool _showComment = false;
  final _commentCtrl = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    final score = _selected!;
    final comment = _commentCtrl.text.trim();

    await FeedbackService.submitNps(score, comment: comment.isEmpty ? null : comment);
    EventLogger.npsScore(score: score, comment: comment.isEmpty ? null : comment);

    setState(() => _submitted = true);

    // Give a moment to show the "спасибо" state, then close and maybe open review
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).pop();

    if (score >= 9) {
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_rounded, color: AppColors.accent, size: 40),
            SizedBox(height: 12),
            Text(
              'Спасибо за оценку!',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Оцени приложение',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Насколько вероятно, что ты порекомендуешь SportWAI другу?',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // 0–10 score row
          Row(
            children: List.generate(11, (i) {
              final selected = _selected == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selected = i;
                    _showComment = i <= 6;
                  }),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accent
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$i',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Вряд ли', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              Text('Точно да!', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),

          // Comment field (for detractors)
          if (_showComment) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Что нам улучшить? (необязательно)',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selected != null ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.surface,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Отправить', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Позже',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Micro-survey bottom sheet ────────────────────────────────────────────────

/// Shows "what's missing" micro-survey in a bottom sheet.
Future<void> showMicroSurveySheet(BuildContext context) async {
  await FeedbackService.markMicroSurveyShown();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _MicroSurveySheet(),
  );
}

class _MicroSurveySheet extends StatefulWidget {
  const _MicroSurveySheet();
  @override
  State<_MicroSurveySheet> createState() => _MicroSurveySheetState();
}

class _MicroSurveySheetState extends State<_MicroSurveySheet> {
  static const _options = [
    ('nutrition',   'Питание / КБЖУ',                  Icons.restaurant_rounded),
    ('more_progs',  'Готовые программы от тренеров',   Icons.fitness_center_rounded),
    ('social',      'Соцфункции (друзья, соревнования)',Icons.people_rounded),
    ('wearable',    'Интеграция с часами / трекером',   Icons.watch_rounded),
    ('ok',          'Всё устраивает',                   Icons.thumb_up_rounded),
  ];

  bool _submitted = false;

  Future<void> _submit(String feature) async {
    setState(() => _submitted = true);
    await FeedbackService.submitFeatureRequest(feature);
    EventLogger.featureRequest(feature: feature);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 40),
            SizedBox(height: 12),
            Text(
              'Учтём, спасибо!',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Чего не хватает?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Выбери одно — это займёт 5 секунд',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ..._options.map((opt) {
            final (key, label, icon) = opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _submit(key),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: AppColors.accent, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        label,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Screen thumbs widget ─────────────────────────────────────────────────────

/// Small thumbs-up / thumbs-down widget for AppBar actions.
/// Pass [screen] identifier (e.g. 'exercise_history', 'calculators').
class ScreenThumbsWidget extends StatefulWidget {
  final String screen;
  const ScreenThumbsWidget({super.key, required this.screen});

  @override
  State<ScreenThumbsWidget> createState() => _ScreenThumbsWidgetState();
}

class _ScreenThumbsWidgetState extends State<ScreenThumbsWidget> {
  int? _voted;

  Future<void> _vote(int v) async {
    if (_voted != null) return;
    setState(() => _voted = v);

    // If thumbs down → show comment dialog
    String? comment;
    if (v == -1 && mounted) {
      comment = await _showCommentDialog();
    }

    await FeedbackService.submitScreenFeedback(
      widget.screen, v, comment: comment);
    EventLogger.screenFeedback(screen: widget.screen, vote: v);

    if (mounted && v == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Спасибо! Рады, что полезно 🙌'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<String?> _showCommentDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Что не так?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Напиши, что улучшить...',
            hintStyle: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Пропустить',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Отправить',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_voted != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          _voted == 1 ? Icons.thumb_up_rounded : Icons.thumb_down_rounded,
          color: AppColors.accent,
          size: 20,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => _vote(1),
          icon: const Icon(Icons.thumb_up_outlined, size: 20),
          tooltip: 'Полезно',
          color: AppColors.textSecondary,
        ),
        IconButton(
          onPressed: () => _vote(-1),
          icon: const Icon(Icons.thumb_down_outlined, size: 20),
          tooltip: 'Не полезно',
          color: AppColors.textSecondary,
        ),
      ],
    );
  }
}
