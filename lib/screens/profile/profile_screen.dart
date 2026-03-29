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
import 'package:sportwai/services/local_storage.dart';
import 'package:sportwai/services/notification_service.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/workout_service.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:sportwai/widgets/avatar_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Profile? _profile;
  bool _uploadingAvatar = false;
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
  DateTime? _deloadWeekStart; // null = current week
  bool _weighInEnabled = false;
  Set<int> _weighInWeekdays = {0}; // 0=Пн…6=Вс, multi-select
  int _weighInHour = 9;
  int _weighInMinute = 0;
  int _restDayNotifHour = 9;
  int _restDayNotifMinute = 0;
  bool _weeklySummaryEnabled = true;

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
        final deloadTs = prefs.getInt('deload_week_start');
        _deloadWeekStart = deloadTs != null
            ? DateTime.fromMillisecondsSinceEpoch(deloadTs)
            : null;
        _weighInEnabled = prefs.getBool('weigh_in_notif_enabled') ?? false;
        _weeklySummaryEnabled = AppStorage.weeklySummaryEnabled;
        // Migrate: old single-day key → new list key
        final legacyDay = prefs.getInt('weigh_in_weekday');
        final savedList = prefs.getStringList('weigh_in_weekdays');
        if (savedList != null) {
          _weighInWeekdays = savedList.map(int.parse).toSet();
        } else if (legacyDay != null) {
          _weighInWeekdays = {legacyDay};
        } else {
          _weighInWeekdays = {0};
        }
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

  static DateTime _weekMonday([DateTime? from]) {
    final d = from ?? DateTime.now();
    return DateTime(d.year, d.month, d.day)
        .subtract(Duration(days: d.weekday - 1));
  }

  String _deloadWeekLabel() {
    final mon = _deloadWeekStart ?? _weekMonday();
    final sun = mon.add(const Duration(days: 6));
    const months = ['янв','фев','мар','апр','май','июн',
                    'июл','авг','сен','окт','ноя','дек'];
    if (mon.month == sun.month) {
      return '${mon.day}–${sun.day} ${months[mon.month - 1]}';
    }
    return '${mon.day} ${months[mon.month - 1]} – ${sun.day} ${months[sun.month - 1]}';
  }

  Future<void> _pickDeloadWeek() async {
    final initial = _deloadWeekStart ?? _weekMonday();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 28)),
      lastDate: DateTime.now().add(const Duration(days: 28)),
      helpText: 'Выберите любой день недели',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accent,
            surface: AppColors.card,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final mon = _weekMonday(picked);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('deload_week_start', mon.millisecondsSinceEpoch);
    setState(() => _deloadWeekStart = mon);
  }

  Future<void> _toggleDeload(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('deload_active', value);
    if (value && _deloadWeekStart == null) {
      final mon = _weekMonday();
      await prefs.setInt('deload_week_start', mon.millisecondsSinceEpoch);
      if (mounted) setState(() { _deloadActive = value; _deloadWeekStart = mon; });
    } else {
      if (!value) {
        await prefs.remove('deload_week_start');
        if (mounted) setState(() { _deloadActive = value; _deloadWeekStart = null; });
      } else {
        if (mounted) setState(() => _deloadActive = value);
      }
    }
    EventLogger.deloadToggled(enabled: value);
  }

  Future<void> _toggleWeeklySummary(bool value) async {
    await AppStorage.setWeeklySummaryEnabled(value);
    if (mounted) setState(() => _weeklySummaryEnabled = value);
    if (value) {
      NotificationService.refreshWeeklySummary();
    } else {
      await NotificationService.cancelWeeklySummary();
    }
  }

  Future<void> _toggleWeighIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weigh_in_notif_enabled', value);
    if (mounted) setState(() => _weighInEnabled = value);
    if (value) {
      await NotificationService.scheduleWeighInReminders(
        _weighInWeekdays.toList(), hour: _weighInHour, minute: _weighInMinute,
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
      await NotificationService.scheduleWeighInReminders(
        _weighInWeekdays.toList(), hour: picked.hour, minute: picked.minute,
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

  Future<void> _toggleWeighInDay(int weekday) async {
    final next = Set<int>.from(_weighInWeekdays);
    if (next.contains(weekday)) {
      next.remove(weekday);
      if (next.isEmpty) return; // always keep at least one day
    } else {
      next.add(weekday);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'weigh_in_weekdays', next.map((d) => '$d').toList());
    if (mounted) setState(() => _weighInWeekdays = next);
    if (_weighInEnabled) {
      await NotificationService.scheduleWeighInReminders(
        next.toList(), hour: _weighInHour, minute: _weighInMinute,
      );
    }
  }

  Future<void> _toggleWeighInEveryDay() async {
    final allDays = {0, 1, 2, 3, 4, 5, 6};
    final next = _weighInWeekdays.length == 7 ? {0} : allDays;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'weigh_in_weekdays', next.map((d) => '$d').toList());
    if (mounted) setState(() => _weighInWeekdays = next);
    if (_weighInEnabled) {
      await NotificationService.scheduleWeighInReminders(
        next.toList(), hour: _weighInHour, minute: _weighInMinute,
      );
    }
  }

  /// Builds a day→workoutName map from all workouts for richer notification text.
  static Map<int, String> _dayToNameMap(List<dynamic> workouts) {
    final map = <int, String>{};
    for (final w in workouts) {
      for (final day in (w.days as List<int>)) {
        map.putIfAbsent(day, () => w.name as String);
      }
    }
    return map;
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
        days,
        hour: picked.hour,
        minute: picked.minute,
        dayToName: _dayToNameMap(workouts),
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
        days,
        hour: _notifHour,
        minute: _notifMinute,
        dayToName: _dayToNameMap(workouts),
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

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  Future<void> _pickAndUploadAvatar() async {
    XFile? file;

    if (_isDesktop) {
      const typeGroup = XTypeGroup(
        label: 'Изображения',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      final picked = await openFile(acceptedTypeGroups: [typeGroup]);
      file = picked;
    } else {
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    }

    if (file == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await ProfileService.uploadAvatar(bytes);
      await ProfileService.updateProfile({'avatar_url': url});
      await _loadProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить фото')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
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
      await NotificationService.scheduleWorkoutReminders(
        days,
        dayToName: _dayToNameMap(workouts),
      );
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
                    GestureDetector(
                      onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          _uploadingAvatar
                              ? const CircleAvatar(
                                  radius: 50,
                                  backgroundColor: AppColors.card,
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppColors.accent,
                                    ),
                                  ),
                                )
                              : AvatarWidget(
                                  avatarUrl: _profile?.avatarUrl,
                                  radius: 50,
                                  fallbackLetter: _avatarLetter,
                                ),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.background,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ],
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
              _StatCard(label: 'Тренировок всего', value: '$_totalWorkouts'),
              _StatCard(label: 'За последний год', value: '$_yearWorkouts'),
              _StatCard(label: 'За последний месяц', value: '$_monthWorkouts'),
              _StatCard(label: 'За последнюю неделю', value: '$_weekWorkouts'),
              _StatCard(label: 'Лучший стрик', value: '$_bestStreak дней'),
              const SizedBox(height: 24),

              // Настройки
              const _SectionTitle('Настройки'),

              // ── Общие ────────────────────────────────────────────────────
              _SettingsGroup(
                title: 'Общие',
                rows: [
                  _SettingsRow(
                    label: 'Параметры тела',
                    trailing: GestureDetector(
                      onTap: () => context.push('/body-metrics'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _latestMetrics?['weight_kg'] != null
                                ? '${(_latestMetrics!['weight_kg'] as num).toStringAsFixed(1)} кг'
                                : 'Не указано',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 14),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right,
                              color: AppColors.textSecondary, size: 18),
                        ],
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
                    label: 'Шаг гантельного ряда',
                    subtitle: 'Минимальный шаг при добавлении веса',
                    last: true,
                    trailing: Builder(builder: (context) {
                      final inc   = ref.watch(dumbbellIncrementProvider);
                      final useKg = ref.watch(useKgProvider);
                      final opts  = _dumbbellOptions(useKg);
                      final cur   = opts.firstWhere(
                        (o) => (o.kg - inc).abs() < 0.01,
                        orElse: () => opts.first,
                      );
                      return PopupMenuButton<double>(
                        onSelected: (v) => ref
                            .read(dumbbellIncrementProvider.notifier)
                            .setIncrement(v),
                        color: AppColors.card,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        itemBuilder: (_) => opts
                            .map((o) => PopupMenuItem(
                                  value: o.kg,
                                  child: Text(o.label),
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
                                cur.label,
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
                      );
                    }),
                  ),
                ],
              ),

              // ── Тренировки ───────────────────────────────────────────────
              _SettingsGroup(
                title: 'Тренировки',
                rows: [
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
                  // Deload row with week selector
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          height: 56,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Деload-неделя (−40% веса)',
                                        style: TextStyle(color: AppColors.textPrimary)),
                                    if (_deloadActive)
                                      GestureDetector(
                                        onTap: _pickDeloadWeek,
                                        child: Text(
                                          'Неделя: ${_deloadWeekLabel()} · изменить',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.accent,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Switch(
                                value: _deloadActive,
                                onChanged: _toggleDeload,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // ── Уведомления ──────────────────────────────────────────────
              Builder(builder: (context) {
                final notifEnabled = ref.watch(notificationsEnabledProvider);
                final h = _notifHour.toString().padLeft(2, '0');
                final m = _notifMinute.toString().padLeft(2, '0');
                final modeLabel = _notifMode == 'fixed'
                    ? 'В заданное время'
                    : 'До начала';
                return _SettingsGroup(
                  title: 'Уведомления',
                  rows: [
                    _SettingsRow(
                      label: 'Уведомления о тренировках',
                      trailing: Switch(
                        value: notifEnabled,
                        onChanged: _toggleNotifications,
                      ),
                    ),
                    if (notifEnabled) ...[
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
                    _SettingsRow(
                      label: 'Напоминание о взвешивании',
                      last: !_weighInEnabled,
                      trailing: Switch(
                        value: _weighInEnabled,
                        onChanged: _toggleWeighIn,
                      ),
                    ),
                    if (_weighInEnabled) ...[
                      // ── День(и) взвешивания ───────────────────────────────
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('День взвешивания',
                                    style: TextStyle(
                                        color: AppColors.textPrimary)),
                                const SizedBox(height: 10),
                                // "Каждый день" toggle chip
                                GestureDetector(
                                  onTap: _toggleWeighInEveryDay,
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _weighInWeekdays.length == 7
                                          ? AppColors.accent
                                          : AppColors.surface,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Каждый день',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _weighInWeekdays.length == 7
                                            ? Colors.white
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Individual day chips
                                Row(
                                  children: List.generate(7, (i) {
                                    final selected =
                                        _weighInWeekdays.contains(i);
                                    return Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                            right: i < 6 ? 6 : 0),
                                        child: GestureDetector(
                                          onTap: () => _toggleWeighInDay(i),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? AppColors.accent
                                                  : AppColors.surface,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              _weekdayName(i),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: selected
                                                    ? Colors.white
                                                    : AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        ],
                      ),
                      _SettingsRow(
                        label: 'Время взвешивания',
                        last: true,
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
                      _SettingsRow(
                        label: 'Итог недели (воскресенье)',
                        last: true,
                        trailing: Switch(
                          value: _weeklySummaryEnabled,
                          onChanged: _toggleWeeklySummary,
                        ),
                      ),
                  ],
                );
              }),

              // ── Безопасность ─────────────────────────────────────────────
              if (_biometricAvailable)
                _SettingsGroup(
                  title: 'Безопасность',
                  rows: [
                    _SettingsRow(
                      label: 'Вход по биометрии',
                      last: true,
                      trailing: Switch(
                        value: _biometricEnabled,
                        onChanged: _toggleBiometric,
                      ),
                    ),
                  ],
                ),

              // ── Инструменты ──────────────────────────────────────────────
              _SettingsGroup(
                title: 'Инструменты',
                rows: [
                  const _SettingsRow(
                    label: 'Пригласить тренера',
                    trailing: Icon(Icons.chevron_right,
                        color: AppColors.textSecondary, size: 18),
                  ),
                  _SettingsRow(
                    label: 'Калькуляторы',
                    trailing: GestureDetector(
                      onTap: () => context.push('/calculators'),
                      child: const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary, size: 18),
                    ),
                  ),
                  _SettingsRow(
                    label: 'Обратная связь',
                    trailing: GestureDetector(
                      onTap: () => context.push('/feedback'),
                      child: const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary, size: 18),
                    ),
                  ),
                  _SettingsRow(
                    label: 'Экспорт данных',
                    last: true,
                    trailing: GestureDetector(
                      onTap: () => _showExportSheet(context),
                      child: const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary, size: 18),
                    ),
                  ),
                ],
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
  final String? subtitle;
  final Widget trailing;
  final bool last;

  const _SettingsRow({
    required this.label,
    required this.trailing,
    this.subtitle,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: subtitle != null ? 10 : 0),
          child: subtitle != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label,
                              style: const TextStyle(color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(subtitle!,
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    trailing,
                  ],
                )
              : SizedBox(
                  height: 56,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(label,
                            style: const TextStyle(color: AppColors.textPrimary)),
                      ),
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  ),
                ),
        ),
        if (!last)
          const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> rows;

  const _SettingsGroup({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          child: Column(children: rows),
        ),
        const SizedBox(height: 16),
      ],
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

// ─── Dumbbell increment options ───────────────────────────────────────────────

class _IncrementOption {
  final String label;
  /// Value always stored in kg.
  final double kg;
  const _IncrementOption(this.label, this.kg);
}

/// Returns the set of selectable dumbbell-increment options for the given unit.
/// kg values are the canonical storage values; lbs values are converted exactly.
List<_IncrementOption> _dumbbellOptions(bool useKg) {
  if (useKg) {
    return const [
      _IncrementOption('0.5 кг', 0.5),
      _IncrementOption('1 кг',   1.0),
      _IncrementOption('2 кг',   2.0),
      _IncrementOption('2.5 кг', 2.5),
      _IncrementOption('5 кг',   5.0),
    ];
  }
  // lbs options: 1.25 / 2.5 / 5 / 10 lbs, stored as kg (1 lb = 0.453592 kg)
  return const [
    _IncrementOption('1.25 lbs', 0.567),   // 1.25 × 0.453592
    _IncrementOption('2.5 lbs',  1.134),   // 2.5  × 0.453592
    _IncrementOption('5 lbs',    2.268),   // 5    × 0.453592
    _IncrementOption('10 lbs',   4.536),   // 10   × 0.453592
  ];
}
