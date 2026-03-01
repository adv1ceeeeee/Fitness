import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/profile.dart';
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
    _loadSettings();
  }

  Future<void> _loadProfile() async {
    final p = await ProfileService.getProfile();
    if (mounted) setState(() => _profile = p);
  }

  void _loadSettings() {
    // TODO: load from SharedPreferences
  }

  static String _goalDisplay(String? goal) {
    const map = {
      'strength': 'Сила',
      'weight_loss': 'Похудение',
      'mass_gain': 'Набор массы',
      'endurance': 'Выносливость',
    };
    return map[goal ?? ''] ?? (goal ?? '—');
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?.fullName ?? AuthService.currentUser?.email ?? 'Пользователь';
    final weight = _profile?.weight;
    final goal = _profile?.goal;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: AppColors.accent.withOpacity(0.3),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 36,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (weight != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${weight.toStringAsFixed(1)} кг',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (goal != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Цель: ${_goalDisplay(goal)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _SectionTitle('Статистика'),
              _StatCard(
                label: 'Тренировок всего',
                value: '—',
              ),
              _StatCard(
                label: 'Лучший стрик',
                value: '— дней',
              ),
              const SizedBox(height: 24),
              _SectionTitle('Настройки'),
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
                child: ListTile(
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

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
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
              Text(
                label,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
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
              Text(
                label,
                style: TextStyle(color: AppColors.textPrimary),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
