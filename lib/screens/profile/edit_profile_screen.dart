import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/services/city_service.dart';
import 'package:sportwai/services/profile_service.dart';

class EditProfileScreen extends StatefulWidget {
  final Profile profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _middleNameCtrl;
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _birthDateCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;

  String? _gender;
  bool _isLoading = false;
  bool _emailChanged = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _firstNameCtrl = TextEditingController(text: p.firstName ?? '');
    _lastNameCtrl = TextEditingController(text: p.lastName ?? '');
    _middleNameCtrl = TextEditingController(text: p.middleName ?? '');
    _nicknameCtrl = TextEditingController(text: p.nickname ?? '');
    _birthDateCtrl = TextEditingController(
      text: p.birthDate != null ? _formatDate(p.birthDate!) : '',
    );
    _cityCtrl = TextEditingController(text: p.city ?? '');
    _emailCtrl = TextEditingController(text: p.email ?? '');
    _phoneCtrl = TextEditingController(text: p.phone ?? '');
    _gender = p.gender;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _nicknameCtrl.dispose();
    _birthDateCtrl.dispose();
    _cityCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  DateTime? _parseDate(String input) {
    final parts = input.trim().split('.');
    if (parts.length != 3) return null;
    final dd = int.tryParse(parts[0]);
    final mm = int.tryParse(parts[1]);
    final yyyy = int.tryParse(parts[2]);
    if (dd == null || mm == null || yyyy == null) return null;
    if (yyyy < 1900 || yyyy > DateTime.now().year) return null;
    try {
      final d = DateTime(yyyy, mm, dd);
      if (d.year != yyyy || d.month != mm || d.day != dd) return null;
      return d;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickDate() async {
    final initial = _parseDate(_birthDateCtrl.text) ??
        DateTime(1990);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('ru'),
    );
    if (picked != null) {
      _birthDateCtrl.text = _formatDate(picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final nickname = _nicknameCtrl.text.trim();
    if (nickname != (widget.profile.nickname ?? '')) {
      final available = await ProfileService.isNicknameAvailable(nickname);
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Этот ник уже занят')),
          );
        }
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final firstName = _firstNameCtrl.text.trim();
      final lastName = _lastNameCtrl.text.trim();
      final fullName = [firstName, lastName]
          .where((s) => s.isNotEmpty)
          .join(' ')
          .trim();

      final updates = <String, dynamic>{
        'first_name': firstName.isEmpty ? null : firstName,
        'last_name': lastName.isEmpty ? null : lastName,
        'middle_name':
            _middleNameCtrl.text.trim().isEmpty ? null : _middleNameCtrl.text.trim(),
        'full_name': fullName.isEmpty ? null : fullName,
        'nickname': nickname.isEmpty ? null : nickname,
        'gender': _gender,
        'birth_date': _birthDateCtrl.text.trim().isNotEmpty
            ? _parseDate(_birthDateCtrl.text.trim())
                ?.toIso8601String()
                .split('T')[0]
            : null,
        'city': _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      };

      final newEmail = _emailCtrl.text.trim();
      final oldEmail = widget.profile.email ?? '';

      if (newEmail.isNotEmpty && newEmail != oldEmail) {
        // Обновляем email через Supabase Auth (требует подтверждения)
        await ProfileService.updateEmail(newEmail);
        _emailChanged = true;
        updates['email'] = newEmail;
      } else {
        await ProfileService.updateProfile(updates);
      }

      if (_emailChanged && updates.isNotEmpty) {
        await ProfileService.updateProfile(updates);
      }

      if (mounted) {
        if (_emailChanged) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Профиль сохранён. Подтвердите новый email: $newEmail',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Профиль сохранён')),
          );
        }
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать профиль'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text(
                'Сохранить',
                style: TextStyle(color: AppColors.accent, fontSize: 16),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- ФИО ---
                const _SectionLabel('Личные данные'),
                _field(
                  controller: _firstNameCtrl,
                  label: 'Имя',
                  icon: Icons.person_outline,
                  capitalize: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _lastNameCtrl,
                  label: 'Фамилия',
                  icon: Icons.person_outline,
                  capitalize: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _middleNameCtrl,
                  label: 'Отчество',
                  icon: Icons.person_outline,
                  capitalize: TextCapitalization.words,
                ),
                const SizedBox(height: 12),

                // --- Логин / ник ---
                const _SectionLabel('Учётная запись'),
                TextFormField(
                  controller: _nicknameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Логин (ник)',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Введите ник';
                    if (!RegExp(r'^[a-zA-Z0-9_\.]{3,32}$').hasMatch(v.trim())) {
                      return '3–32 символа: a-z, 0-9, _, .';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // --- Пол ---
                const _SectionLabel('Пол'),
                Row(
                  children: [
                    Expanded(
                      child: _GenderChip(
                        label: 'М',
                        fullLabel: 'Мужской',
                        selected: _gender == 'male',
                        onTap: () => setState(() => _gender = 'male'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _GenderChip(
                        label: 'Ж',
                        fullLabel: 'Женский',
                        selected: _gender == 'female',
                        onTap: () => setState(() => _gender = 'female'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // --- Дата рождения ---
                const _SectionLabel('Дата рождения'),
                TextFormField(
                  controller: _birthDateCtrl,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: 'ДД.ММ.ГГГГ',
                    prefixIcon: const Icon(Icons.cake_outlined),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: _pickDate,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (_parseDate(v.trim()) == null) return 'Формат: ДД.ММ.ГГГГ';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // --- Город ---
                const _SectionLabel('Город проживания'),
                TypeAheadField<String>(
                  controller: _cityCtrl,
                  suggestionsCallback: CityService.suggest,
                  builder: (context, controller, focusNode) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Город',
                        prefixIcon: Icon(Icons.location_city_outlined),
                        hintText: 'Начните вводить название',
                      ),
                    );
                  },
                  itemBuilder: (context, city) => ListTile(
                    leading: const Icon(Icons.location_on_outlined,
                        color: AppColors.textSecondary),
                    title: Text(
                      city,
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                  ),
                  onSelected: (city) => _cityCtrl.text = city,
                  emptyBuilder: (context) => const SizedBox.shrink(),
                  loadingBuilder: (context) => const SizedBox(
                    height: 48,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // --- Контакты ---
                const _SectionLabel('Контакты'),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    hintText: 'example@mail.com',
                    helperText: 'Смена email потребует подтверждения',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (!v.contains('@') || !v.contains('.')) {
                      return 'Некорректный email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _phoneCtrl,
                  label: 'Номер телефона',
                  icon: Icons.phone_outlined,
                  keyboard: TextInputType.phone,
                  hint: '+7 999 123-45-67',
                ),
                const SizedBox(height: 32),

                // --- Кнопки ---
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    TextCapitalization capitalize = TextCapitalization.none,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      textCapitalization: capitalize,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label;
  final String fullLabel;
  final bool selected;
  final VoidCallback onTap;

  const _GenderChip({
    required this.label,
    required this.fullLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.2) : AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? Border.all(color: AppColors.accent, width: 1.5)
                : null,
          ),
          child: Text(
            '$label  $fullLabel',
            style: TextStyle(
              fontSize: 15,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
