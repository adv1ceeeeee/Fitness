import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/wellness_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Profile? _profile;
  Workout? _todayWorkout;
  bool _loadingWorkout = true;
  bool _wellnessLogged = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ProfileService.getProfile();
    final w = await TrainingService.getTodayWorkout();
    final wellness = await WellnessService.getTodayLog();
    if (mounted) {
      setState(() {
        _profile = p;
        _todayWorkout = w;
        _loadingWorkout = false;
        _wellnessLogged = wellness != null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?.fullName?.split(' ').first ?? 'Атлет';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Привет, $name!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (!_wellnessLogged) ...[
                  const SizedBox(height: 24),
                  _WellnessCard(
                    onSaved: () => setState(() => _wellnessLogged = true),
                  ),
                ],
                const SizedBox(height: 24),
                _TodayCard(
                  workout: _todayWorkout,
                  loading: _loadingWorkout,
                  onTap: () => context.push('/today'),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Быстрые действия',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.fitness_center_rounded,
                        label: 'Мои программы',
                        onTap: () => context.go('/workouts'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.analytics_rounded,
                        label: 'Аналитика',
                        onTap: () => context.go('/analytics'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  icon: Icons.calendar_month_rounded,
                  label: 'Календарь тренировок',
                  onTap: () => context.push('/calendar'),
                  fullWidth: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final Workout? workout;
  final bool loading;
  final VoidCallback onTap;

  const _TodayCard({
    required this.workout,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasWorkout = workout != null;
    return Material(
      color: hasWorkout ? AppColors.card : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: hasWorkout ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hasWorkout
                      ? AppColors.accent.withValues(alpha: 0.2)
                      : AppColors.separator.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasWorkout
                      ? Icons.fitness_center_rounded
                      : Icons.today_rounded,
                  color: hasWorkout
                      ? AppColors.accent
                      : AppColors.textSecondary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: loading
                    ? const Text('Загрузка...',
                        style: TextStyle(color: AppColors.textSecondary))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasWorkout
                                ? workout!.name
                                : 'Сегодня тренировки нет',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: hasWorkout
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          if (hasWorkout) ...[
                            const SizedBox(height: 4),
                            const Text(
                              'Нажми, чтобы начать',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
              ),
              if (hasWorkout)
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Wellness check-in card ───────────────────────────────────────────────────

class _WellnessCard extends StatefulWidget {
  final VoidCallback onSaved;

  const _WellnessCard({required this.onSaved});

  @override
  State<_WellnessCard> createState() => _WellnessCardState();
}

class _WellnessCardState extends State<_WellnessCard> {
  double _sleep = 7;
  int _stress = 3;
  int _energy = 3;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await WellnessService.upsert(
      sleepHours: _sleep,
      stress: _stress,
      energy: _energy,
    );
    if (mounted) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Как самочувствие?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _SleepRow(
            value: _sleep,
            onChanged: (v) => setState(() => _sleep = v),
          ),
          const SizedBox(height: 12),
          _RatingRow(
            label: 'Стресс',
            value: _stress,
            onChanged: (v) => setState(() => _stress = v),
          ),
          const SizedBox(height: 12),
          _RatingRow(
            label: 'Энергия',
            value: _energy,
            onChanged: (v) => setState(() => _energy = v),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _RatingRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
        const SizedBox(width: 8),
        ...List.generate(5, (i) {
          final selected = i < value;
          return GestureDetector(
            onTap: () => onChanged(i + 1),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                selected ? Icons.star_rounded : Icons.star_outline_rounded,
                color: selected
                    ? AppColors.accent
                    : AppColors.textSecondary,
                size: 28,
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _SleepRow extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _SleepRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 72,
          child: Text(
            'Сон',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.surface,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accent.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: value,
              min: 4,
              max: 12,
              divisions: 16,
              onChanged: onChanged,
            ),
          ),
        ),
        Text(
          '${value.toStringAsFixed(1)}ч',
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool fullWidth;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: fullWidth
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 28, color: AppColors.accent),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Icon(icon, size: 32, color: AppColors.accent),
                    const SizedBox(height: 12),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
