import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/screens/profile/edit_profile_screen.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _profile;
  bool _useKg = true;
  bool _darkTheme = true;
  bool _notifications = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final p = await ProfileService.getProfile();
    if (mounted) setState(() => _profile = p);
  }

  String get _displayName {
    final p = _profile;
    if (p == null) return AuthService.currentUser?.email ?? 'Пользователь';
    final parts = [p.firstName, p.lastName].where((s) => s != null && s.isNotEmpty);
    if (parts.isNotEmpty) return parts.join(' ');
    return p.nickname ?? AuthService.currentUser?.email ?? 'Пользователь';
  }

  String get _avatarLetter {
    final name = _displayName;
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String _genderLabel(String? g) {
    if (g == 'male') return 'Мужской';
    if (g == 'female') return 'Женский';
    return '—';
  }

  Future<void> _openEdit() async {
    if (_profile == null) return;
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(profile: _profile!),
      ),
    );
    if (updated == true) _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Аватар + имя
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.3),
                      child: Text(
                        _avatarLetter,
                        style: const TextStyle(
                          fontSize: 36,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _displayName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (_profile?.nickname != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '@${_profile!.nickname}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Личные данные
              _SectionHeader(
                title: 'Личные данные',
                onEdit: _profile != null ? _openEdit : null,
              ),
              _InfoCard(
                children: [
                  _InfoRow(label: 'Имя', value: _profile?.firstName),
                  _InfoRow(label: 'Фамилия', value: _profile?.lastName),
                  _InfoRow(label: 'Отчество', value: _profile?.middleName),
                  _InfoRow(label: 'Логин (ник)', value: _profile?.nickname),
                  _InfoRow(label: 'Пол', value: _genderLabel(_profile?.gender)),
                  _InfoRow(
                    label: 'Дата рождения',
                    value: _formatDate(_profile?.birthDate),
                  ),
                  _InfoRow(label: 'Город', value: _profile?.city),
                  _InfoRow(label: 'Email', value: _profile?.email),
                  _InfoRow(label: 'Телефон', value: _profile?.phone, last: true),
                ],
              ),
              if (_profile == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.hourglass_empty, size: 16),
                    label: const Text('Загрузка данных...'),
                  ),
                ),
              const SizedBox(height: 24),

              // Статистика
              const _SectionTitle('Статистика'),
              const _StatCard(label: 'Тренировок всего', value: '—'),
              const _StatCard(label: 'Лучший стрик', value: '— дней'),
              const SizedBox(height: 24),

              // Настройки
              const _SectionTitle('Настройки'),
              _SettingsRow(
                label: 'Единицы измерения',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChoiceChip(
                      label: const Text('кг'),
                      selected: _useKg,
                      onSelected: (_) => setState(() => _useKg = true),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('фунты'),
                      selected: !_useKg,
                      onSelected: (_) => setState(() => _useKg = false),
                    ),
                  ],
                ),
              ),
              _SettingsRow(
                label: 'Тёмная тема',
                trailing: Switch(
                  value: _darkTheme,
                  onChanged: (v) => setState(() => _darkTheme = v),
                ),
              ),
              _SettingsRow(
                label: 'Уведомления',
                trailing: Switch(
                  value: _notifications,
                  onChanged: (v) => setState(() => _notifications = v),
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                child: const ListTile(
                  leading: Icon(Icons.person_add, color: AppColors.accent),
                  title: Text(
                    'Пригласить тренера',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  subtitle: Text(
                    'Скоро тренеры смогут подключаться к твоим тренировкам!',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await AuthService.signOut();
                    if (mounted) context.go('/');
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Выйти'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Виджеты ────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onEdit;

  const _SectionHeader({required this.title, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (onEdit != null)
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Изменить'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool last;

  const _InfoRow({required this.label, this.value, this.last = false});

  @override
  Widget build(BuildContext context) {
    final text = (value == null || value!.isEmpty) ? '—' : value!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 130,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: text == '—'
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!last)
          const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(color: AppColors.textSecondary)),
              Text(value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final Widget trailing;

  const _SettingsRow({required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(color: AppColors.textPrimary)),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
