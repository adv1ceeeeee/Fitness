import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/providers/settings_provider.dart';
import 'package:sportwai/screens/profile/edit_profile_screen.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/biometric_service.dart';
import 'package:sportwai/services/body_metrics_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/export_service.dart';
import 'package:sportwai/services/notification_service.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/workout_service.dart';
import 'package:sportwai/widgets/avatar_widget.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Profile? _profile;
  int _totalWorkouts = 0;
  int _yearWorkouts = 0;
  int _monthWorkouts = 0;
  int _weekWorkouts = 0;
  int _bestStreak = 0;
  Map<String, dynamic>? _latestMetrics;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  int _notifHour = 8;
  int _notifMinute = 0;
  String _notifMode = 'fixed'; // 'fixed' | 'before'
  int _notifMinutesBefore = 30;
  int _weeklyWorkoutGoal = 0; // 0 = not set
  bool _deloadActive = false;
  bool _weighInEnabled = false;
  int _weighInWeekday = 0; // 0=Пн…6=Вс
  int _weighInHour = 9;
  int _weighInMinute = 0;
  int _restDayNotifHour = 9;
  int _restDayNotifMinute = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadStats();
    _loadMetrics();
    _loadBiometric();
    _loadNotifTime();
    _loadExtraPrefs();
  }

  Future<void> _loadNotifTime() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _notifHour = prefs.getInt('notif_hour') ?? 8;
        _notifMinute = prefs.getInt('notif_minute') ?? 0;
        _notifMode = prefs.getString('notif_mode') ?? 'fixed';
        _notifMinutesBefore = prefs.getInt('notif_minutes_before') ?? 30;
      });
    }
  }

  Future<void> _loadExtraPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _weeklyWorkoutGoal = prefs.getInt('weekly_workout_goal') ?? 0;
        _deloadActive = prefs.getBool('deload_active') ?? false;
        _weighInEnabled = prefs.getBool('weigh_in_notif_enabled') ?? false;
        _weighInWeekday = prefs.getInt('weigh_in_weekday') ?? 0;
        _weighInHour = prefs.getInt('weigh_in_hour') ?? 9;
        _weighInMinute = prefs.getInt('weigh_in_minute') ?? 0;
        _restDayNotifHour = prefs.getInt('rest_day_notif_hour') ?? 9;
        _restDayNotifMinute = prefs.getInt('rest_day_notif_minute') ?? 0;
      });
    }
  }

  Future<void> _setWeeklyGoal(int goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('weekly_workout_goal', goal);
    if (mounted) setState(() => _weeklyWorkoutGoal = goal);
  }

  Future<void> _toggleDeload(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('deload_active', value);
    if (mounted) setState(() => _deloadActive = value);
  }

  Future<void> _toggleWeighIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weigh_in_notif_enabled', value);
    if (mounted) setState(() => _weighInEnabled = value);
    if (value) {
      await NotificationService.scheduleWeighInReminder(
        weekday: _weighInWeekday, hour: _weighInHour, minute: _weighInMinute,
      );
    } else {
      await NotificationService.cancelWeighInReminder();
    }
  }

  Future<void> _pickWeighInTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _weighInHour, minute: _weighInMinute),
    );
    if (picked == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('weigh_in_hour', picked.hour);
    await prefs.setInt('weigh_in_minute', picked.minute);
    setState(() { _weighInHour = picked.hour; _weighInMinute = picked.minute; });
    if (_weighInEnabled) {
      await NotificationService.scheduleWeighInReminder(
        weekday: _weighInWeekday, hour: picked.hour, minute: picked.minute,
      );
    }
  }

  Future<void> _pickRestDayNotifTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _restDayNotifHour, minute: _restDayNotifMinute),
    );
    if (picked == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('rest_day_notif_hour', picked.hour);
    await prefs.setInt('rest_day_notif_minute', picked.minute);
    setState(() {
      _restDayNotifHour = picked.hour;
      _restDayNotifMinute = picked.minute;
    });
    // Re-schedule rest day notifications with new time
    final workouts = await WorkoutService.getMyWorkouts();
    final restDays = workouts.expand((w) => w.restDays).toSet().toList();
    if (restDays.isNotEmpty) {
      await NotificationService.scheduleRestDayReminders(
          restDays, hour: picked.hour, minute: picked.minute);
    }
  }

  String _weekdayName(int day) {
    const names = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return names[day.clamp(0, 6)];
  }

  Future<void> _changeWeighInDay(int weekday) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('weigh_in_weekday', weekday);
    if (mounted) setState(() => _weighInWeekday = weekday);
    if (_weighInEnabled) {
      await NotificationService.scheduleWeighInReminder(
        weekday: weekday, hour: _weighInHour, minute: _weighInMinute,
      );
    }
  }

  Future<void> _pickNotifTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _notifHour, minute: _notifMinute),
    );
    if (picked == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_hour', picked.hour);
    await prefs.setInt('notif_minute', picked.minute);
    if (mounted) setState(() { _notifHour = picked.hour; _notifMinute = picked.minute; });
    final enabled = ref.read(notificationsEnabledProvider);
    if (enabled) {
      final workouts = await WorkoutService.getMyWorkouts();
      final days = workouts.expand((w) => w.days).toList();
      await NotificationService.scheduleWorkoutReminders(
        days, hour: picked.hour, minute: picked.minute,
      );
    }
  }

  Future<void> _changeNotifMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_mode', mode);
    if (mounted) setState(() => _notifMode = mode);
    final enabled = ref.read(notificationsEnabledProvider);
    if (!enabled) return;
    if (mode == 'fixed') {
      final workouts = await WorkoutService.getMyWorkouts();
      final days = workouts.expand((w) => w.days).toList();
      await NotificationService.scheduleWorkoutReminders(
        days, hour: _notifHour, minute: _notifMinute,
      );
    } else {
      // 'before' mode — weekly reminders don't apply, cancel them
      await NotificationService.cancelAll();
    }
  }

  Future<void> _changeMinutesBefore(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_minutes_before', minutes);
    if (mounted) setState(() => _notifMinutesBefore = minutes);
  }

  Future<void> _loadBiometric() async {
    final available = await BiometricService.isAvailable();
    final enabled = await BiometricService.isEnabled();
    if (mounted) setState(() { _biometricAvailable = available; _biometricEnabled = enabled; });
  }

  Future<void> _toggleBiometric(bool value) async {
    await BiometricService.setEnabled(value);
    if (mounted) setState(() => _biometricEnabled = value);
  }

  Future<void> _loadProfile() async {
    final p = await ProfileService.getProfile();
    if (mounted) setState(() => _profile = p);
  }

  Future<void> _loadStats() async {
    final results = await Future.wait([
      AnalyticsService.getTotalWorkouts(),
      AnalyticsService.getWorkoutsThisYear(),
      AnalyticsService.getWorkoutsThisMonth(),
      AnalyticsService.getWorkoutsThisWeek(),
      AnalyticsService.getBestStreak(),
    ]);
    if (mounted) {
      setState(() {
        _totalWorkouts = results[0];
        _yearWorkouts = results[1];
        _monthWorkouts = results[2];
        _weekWorkouts = results[3];
        _bestStreak = results[4];
      });
    }
  }

  Future<void> _loadMetrics() async {
    final m = await BodyMetricsService.getLatest();
    if (mounted) setState(() => _latestMetrics = m);
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

  Future<void> _toggleNotifications(bool enabled) async {
    if (enabled) {
      final granted = await NotificationService.requestPermission();
      if (!granted) return;
      final workouts = await WorkoutService.getMyWorkouts();
      final days = workouts.expand((w) => w.days).toList();
      await NotificationService.scheduleWorkoutReminders(days);
    } else {
      await NotificationService.cancelAll();
    }
    EventLogger.notificationToggled(enabled: enabled);
    await ref.read(notificationsEnabledProvider.notifier).setEnabled(enabled);
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

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Удалить аккаунт?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Все данные будут удалены безвозвратно: тренировки, история, метрики.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AuthService.deleteAccount();
      if (mounted) router.go('/');
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось удалить аккаунт. Попробуйте позже.')),
      );
    }
  }

  void _showExportSheet(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Формат экспорта',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _ExportBtn(
              icon: Icons.data_object,
              label: 'JSON',
              subtitle: 'Полный дамп всех данных',
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  EventLogger.exportTriggered(format: 'json');
                  await ExportService.exportData();
                } catch (_) {
                  messenger.showSnackBar(const SnackBar(
                      content: Text('Не удалось экспортировать данные')));
                }
              },
            ),
            const SizedBox(height: 8),
            _ExportBtn(
              icon: Icons.table_chart_outlined,
              label: 'CSV',
              subtitle: 'Таблица подходов для Excel / Google Sheets',
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  EventLogger.exportTriggered(format: 'csv');
                  await ExportService.exportCsv();
                } catch (_) {
                  messenger.showSnackBar(const SnackBar(
                      content: Text('Не удалось экспортировать данные')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).padding.bottom + 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Аватар + имя
              Center(
                child: Column(
                  children: [
                    AvatarWidget(
                      avatarUrl: _profile?.avatarUrl,
                      radius: 50,
                      fallbackLetter: _avatarLetter,
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
              _StatCard(label: 'Тренировок всего', value: '$_totalWorkouts'),
              _StatCard(label: 'За последний год', value: '$_yearWorkouts'),
              _StatCard(label: 'За последний месяц', value: '$_monthWorkouts'),
              _StatCard(label: 'За последнюю неделю', value: '$_weekWorkouts'),
              _StatCard(label: 'Лучший стрик', value: '$_bestStreak дней'),
              const SizedBox(height: 24),

              // Настройки
              const _SectionTitle('Настройки'),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.push('/body-metrics'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Параметры тела',
                              style: TextStyle(color: AppColors.textPrimary)),
                          Row(
                            children: [
                              Text(
                                _latestMetrics?['weight_kg'] != null
                                    ? '${(_latestMetrics!['weight_kg'] as num).toStringAsFixed(1)} кг'
                                    : 'Не указано',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right,
                                  color: AppColors.textSecondary, size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _SettingsRow(
                label: 'Единицы веса',
                trailing: Builder(builder: (context) {
                  final useKg = ref.watch(useKgProvider);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChoiceChip(
                        label: const Text('кг'),
                        selected: useKg,
                        onSelected: (_) =>
                            ref.read(useKgProvider.notifier).setUseKg(true),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('фунты'),
                        selected: !useKg,
                        onSelected: (_) =>
                            ref.read(useKgProvider.notifier).setUseKg(false),
                      ),
                    ],
                  );
                }),
              ),
              _SettingsRow(
                label: 'Единицы длины',
                trailing: Builder(builder: (context) {
                  final useCm = ref.watch(useCmProvider);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChoiceChip(
                        label: const Text('см'),
                        selected: useCm,
                        onSelected: (_) =>
                            ref.read(useCmProvider.notifier).setUseCm(true),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('дюймы'),
                        selected: !useCm,
                        onSelected: (_) =>
                            ref.read(useCmProvider.notifier).setUseCm(false),
                      ),
                    ],
                  );
                }),
              ),
              _SettingsRow(
                label: 'Уведомления',
                trailing: Builder(builder: (context) {
                  final enabled = ref.watch(notificationsEnabledProvider);
                  return Switch(
                    value: enabled,
                    onChanged: _toggleNotifications,
                  );
                }),
              ),
              Builder(builder: (context) {
                final enabled = ref.watch(notificationsEnabledProvider);
                if (!enabled) return const SizedBox();
                final h = _notifHour.toString().padLeft(2, '0');
                final m = _notifMinute.toString().padLeft(2, '0');
                final modeLabel = _notifMode == 'fixed'
                    ? 'В заданное время'
                    : 'До начала тренировки';
                return Column(
                  children: [
                    _SettingsRow(
                      label: 'Режим напоминания',
                      trailing: PopupMenuButton<String>(
                        onSelected: _changeNotifMode,
                        color: AppColors.card,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'fixed',
                            child: Text('В заданное время'),
                          ),
                          PopupMenuItem(
                            value: 'before',
                            child: Text('До начала тренировки'),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                modeLabel,
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down,
                                  color: AppColors.accent, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_notifMode == 'fixed')
                      _SettingsRow(
                        label: 'Время напоминания',
                        trailing: GestureDetector(
                          onTap: _pickNotifTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$h:$m',
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      _SettingsRow(
                        label: 'За сколько минут',
                        trailing: PopupMenuButton<int>(
                          onSelected: _changeMinutesBefore,
                          color: AppColors.card,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          itemBuilder: (_) => [15, 30, 45, 60, 90, 120]
                              .map((v) => PopupMenuItem(
                                    value: v,
                                    child: Text('$v мин'),
                                  ))
                              .toList(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$_notifMinutesBefore мин',
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_drop_down,
                                    color: AppColors.accent, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }),
              // ── Цель по тренировкам в неделю ───────────────────────────
              _SettingsRow(
                label: 'Цель: тренировок в неделю',
                trailing: PopupMenuButton<int>(
                  onSelected: _setWeeklyGoal,
                  color: AppColors.card,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 0, child: Text('Не задана')),
                    ...List.generate(7, (i) => PopupMenuItem(
                      value: i + 1,
                      child: Text('${i + 1}'),
                    )),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _weeklyWorkoutGoal == 0 ? 'Не задана' : '$_weeklyWorkoutGoal',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down,
                            color: AppColors.accent, size: 18),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Деload-неделя ───────────────────────────────────────────
              _SettingsRow(
                label: 'Деload-неделя (−40% веса)',
                trailing: Switch(
                  value: _deloadActive,
                  onChanged: _toggleDeload,
                ),
              ),

              // ── Уведомление в дни отдыха ────────────────────────────────
              _SettingsRow(
                label: 'Уведомление в дни отдыха',
                trailing: GestureDetector(
                  onTap: _pickRestDayNotifTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A454).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hotel_rounded,
                            color: Color(0xFFD4A454), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '${_restDayNotifHour.toString().padLeft(2, '0')}:${_restDayNotifMinute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Color(0xFFD4A454),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Напоминание о взвешивании ───────────────────────────────
              _SettingsRow(
                label: 'Напоминание о взвешивании',
                trailing: Switch(
                  value: _weighInEnabled,
                  onChanged: _toggleWeighIn,
                ),
              ),
              if (_weighInEnabled) ...[
                _SettingsRow(
                  label: 'День взвешивания',
                  trailing: PopupMenuButton<int>(
                    onSelected: _changeWeighInDay,
                    color: AppColors.card,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 0, child: Text('Понедельник')),
                      PopupMenuItem(value: 1, child: Text('Вторник')),
                      PopupMenuItem(value: 2, child: Text('Среда')),
                      PopupMenuItem(value: 3, child: Text('Четверг')),
                      PopupMenuItem(value: 4, child: Text('Пятница')),
                      PopupMenuItem(value: 5, child: Text('Суббота')),
                      PopupMenuItem(value: 6, child: Text('Воскресенье')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _weekdayName(_weighInWeekday),
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down,
                              color: AppColors.accent, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                _SettingsRow(
                  label: 'Время взвешивания',
                  trailing: GestureDetector(
                    onTap: _pickWeighInTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_weighInHour.toString().padLeft(2, '0')}:${_weighInMinute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              if (_biometricAvailable)
                _SettingsRow(
                  label: 'Вход по биометрии',
                  trailing: Switch(
                    value: _biometricEnabled,
                    onChanged: _toggleBiometric,
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
              const SizedBox(height: 16),
              Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push('/calculators'),
                  child: const ListTile(
                    leading: Icon(Icons.calculate_outlined, color: AppColors.accent),
                    title: Text(
                      'Калькуляторы',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                    subtitle: Text(
                      '1ПМ и блины',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showExportSheet(context),
                  child: const ListTile(
                    leading: Icon(Icons.download, color: AppColors.accent),
                    title: Text(
                      'Экспорт данных',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                    subtitle: Text(
                      'Сохранить все тренировки и метрики',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDeleteAccount(context),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Удалить аккаунт'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    final router = GoRouter.of(context);
                    EventLogger.userLoggedOut();
                    await AuthService.signOut();
                    if (mounted) router.go('/');
                  },
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Выйти', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
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

class _ExportBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ExportBtn({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accent, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
