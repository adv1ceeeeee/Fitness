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
  String _inputMode = 'weighted';
  String _equipment = 'barbell';
  bool _saving = false;

  static const _categories = [
    ('chest', 'Грудь'),
    ('back', 'Спина'),
    ('shoulders', 'Плечи'),
    ('arms', 'Руки'),
    ('legs', 'Ноги'),
    ('cardio', 'Кардио'),
    ('core', 'Пресс'),
  ];

  static const _inputModes = [
    ('weighted', 'С отягощением'),
    ('bodyweight', 'Вес тела'),
    ('cardio', 'Кардио'),
  ];

  static const _equipmentTypes = [
    ('barbell', 'Штанга'),
    ('dumbbell', 'Гантели'),
    ('cable', 'Блок'),
    ('machine', 'Тренажёр'),
    ('bodyweight', 'Вес тела'),
    ('other', 'Другое'),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// Sync default input mode + equipment when the category changes, so
  /// creating a cardio exercise auto-selects cardio-friendly values.
  void _onCategoryChanged(String key) {
    setState(() {
      _category = key;
      if (key == 'cardio') {
        _inputMode = 'cardio';
        _equipment = 'other';
      } else if (_inputMode == 'cardio') {
        _inputMode = 'weighted';
        _equipment = 'barbell';
      }
    });
  }

  void _onInputModeChanged(String key) {
    setState(() {
      _inputMode = key;
      if (key == 'bodyweight') {
        _equipment = 'bodyweight';
      } else if (key == 'cardio') {
        _equipment = 'other';
      } else if (_equipment == 'bodyweight') {
        _equipment = 'barbell';
      }
    });
  }

  /// Returns true if the string contains at least one Cyrillic character.
  bool _looksCyrillic(String s) => RegExp(r'[\u0400-\u04FF]').hasMatch(s);

  Future<void> _save() async {
    final rawName = _nameCtrl.text.trim();
    if (rawName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название упражнения')),
      );
      return;
    }

    // If the user typed in Russian, route the text into name_ru and keep
    // `name` equal to the same string so DB joins/searches still work.
    final isCyrillic = _looksCyrillic(rawName);
    final nameForDb = rawName;
    final nameRuForDb = isCyrillic ? rawName : null;

    setState(() => _saving = true);
    try {
      final exercise = await ExerciseService.createExercise(
        name: nameForDb,
        nameRu: nameRuForDb,
        category: _category,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        inputMode: _inputMode,
        equipmentType: _equipment,
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

  Widget _chipGroup({
    required String selectedKey,
    required List<(String, String)> items,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((pair) {
        final (key, label) = pair;
        final selected = selectedKey == key;
        return ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onSelected(key),
          selectedColor: AppColors.accent.withValues(alpha: 0.2),
          labelStyle: TextStyle(
            color: selected ? AppColors.accent : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
          backgroundColor: AppColors.card,
          side: BorderSide(
            color: selected ? AppColors.accent : Colors.transparent,
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );

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
          _sectionLabel('Название'),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Например: Болгарские выпады'),
          ),
          const SizedBox(height: 20),
          _sectionLabel('Группа мышц'),
          _chipGroup(
            selectedKey: _category,
            items: _categories,
            onSelected: _onCategoryChanged,
          ),
          const SizedBox(height: 20),
          _sectionLabel('Тип ввода'),
          _chipGroup(
            selectedKey: _inputMode,
            items: _inputModes,
            onSelected: _onInputModeChanged,
          ),
          const SizedBox(height: 20),
          _sectionLabel('Оборудование'),
          _chipGroup(
            selectedKey: _equipment,
            items: _equipmentTypes,
            onSelected: (key) => setState(() => _equipment = key),
          ),
          const SizedBox(height: 20),
          _sectionLabel('Описание (необязательно)'),
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
