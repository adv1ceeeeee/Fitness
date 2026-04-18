import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/services/exercise_service.dart';

class CreateExerciseScreen extends StatefulWidget {
  /// When non-null, the screen opens in edit mode and pre-fills every field.
  final Exercise? existing;

  const CreateExerciseScreen({super.key, this.existing});

  @override
  State<CreateExerciseScreen> createState() => _CreateExerciseScreenState();
}

class _CreateExerciseScreenState extends State<CreateExerciseScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late String _category;
  late String _inputMode;
  late String _equipment;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

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
  void initState() {
    super.initState();
    final ex = widget.existing;
    _nameCtrl = TextEditingController(text: ex?.displayName ?? '');
    _descCtrl = TextEditingController(
        text: ex?.descriptionRu ?? ex?.description ?? '');
    _category = ex?.category ?? 'chest';

    // Prefer the explicit DB input_mode; fall back to derived mode so edit
    // mode reflects what the user actually sees in the session.
    final modeEnum = ex?.effectiveInputMode ?? ExerciseInputMode.weighted;
    _inputMode = ex?.inputMode ?? _modeToKey(modeEnum);
    _equipment = ex?.equipmentType ?? 'barbell';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  static String _modeToKey(ExerciseInputMode m) {
    switch (m) {
      case ExerciseInputMode.weighted:
        return 'weighted';
      case ExerciseInputMode.bodyweight:
        return 'bodyweight';
      case ExerciseInputMode.cardio:
        return 'cardio';
    }
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
    final nameRuForDb = isCyrillic ? rawName : '';

    setState(() => _saving = true);
    try {
      final desc = _descCtrl.text.trim();
      final exercise = _isEdit
          ? await ExerciseService.updateExercise(
              id: widget.existing!.id,
              name: nameForDb,
              nameRu: nameRuForDb,
              category: _category,
              description: desc,
              inputMode: _inputMode,
              equipmentType: _equipment,
            )
          : await ExerciseService.createExercise(
              name: nameForDb,
              nameRu: nameRuForDb.isEmpty ? null : nameRuForDb,
              category: _category,
              description: desc.isEmpty ? null : desc,
              inputMode: _inputMode,
              equipmentType: _equipment,
            );
      if (mounted) Navigator.of(context).pop(exercise);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit
                ? 'Не удалось сохранить изменения'
                : 'Не удалось создать упражнение'),
          ),
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
        title: Text(_isEdit ? 'Изменить упражнение' : 'Новое упражнение'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isEdit ? 'Сохранить' : 'Создать',
                    style: const TextStyle(
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
            autofocus: !_isEdit,
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
