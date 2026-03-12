import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/exercise_service.dart';

class CreateExerciseScreen extends StatefulWidget {
  const CreateExerciseScreen({super.key});

  @override
  State<CreateExerciseScreen> createState() => _CreateExerciseScreenState();
}

class _CreateExerciseScreenState extends State<CreateExerciseScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'chest';
  bool _saving = false;

  static const _categories = [
    ('chest', 'Грудь'),
    ('back', 'Спина'),
    ('shoulders', 'Плечи'),
    ('arms', 'Руки'),
    ('legs', 'Ноги'),
    ('cardio', 'Кардио'),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название упражнения')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final exercise = await ExerciseService.createExercise(
        name: name,
        category: _category,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(exercise);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось создать упражнение')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новое упражнение'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Создать',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Название',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Например: Болгарские выпады'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Группа мышц',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((pair) {
              final (key, label) = pair;
              final selected = _category == key;
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => setState(() => _category = key),
                selectedColor: AppColors.accent.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
                backgroundColor: AppColors.card,
                side: BorderSide(
                  color: selected ? AppColors.accent : Colors.transparent,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          const Text(
            'Описание (необязательно)',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Техника выполнения, заметки...'),
          ),
        ],
      ),
    );
  }
}
