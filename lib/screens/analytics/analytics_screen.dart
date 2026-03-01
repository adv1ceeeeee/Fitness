import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/services/analytics_service.dart';
import 'package:sportwai/services/profile_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Profile? _profile;
  int _totalWorkouts = 0;
  int _bestStreak = 0;
  int _workoutsThisWeek = 0;
  double _volumeThisWeek = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await ProfileService.getProfile();
    final total = await AnalyticsService.getTotalWorkouts();
    final streak = await AnalyticsService.getBestStreak();
    final weekCount = await AnalyticsService.getWorkoutsThisWeek();
    final volume = await AnalyticsService.getVolumeThisWeek();

    if (mounted) {
      setState(() {
        _profile = profile;
        _totalWorkouts = total;
        _bestStreak = streak;
        _workoutsThisWeek = weekCount;
        _volumeThisWeek = volume;
        _loading = false;
      });
    }
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
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final name = _profile?.fullName?.split(' ').first ?? 'Атлет';
    final goal = _profile?.goal;

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
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Твоя цель: ${_goalDisplay(goal)}',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                _StreakCard(
                  streak: _bestStreak,
                  totalWorkouts: _totalWorkouts,
                ),
                const SizedBox(height: 24),
                Text(
                  'Статистика за неделю',
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
                      child: _StatBox(
                        label: 'Тренировок',
                        value: '$_workoutsThisWeek',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatBox(
                        label: 'Объём (кг)',
                        value: _volumeThisWeek.toStringAsFixed(0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  'Поделиться прогрессом',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Скоро: генерация картинки для шеринга')),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Icon(Icons.share, color: AppColors.accent, size: 32),
                          const SizedBox(width: 16),
                          Text(
                            'Создать картинку с достижениями',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final int streak;
  final int totalWorkouts;

  const _StreakCard({
    required this.streak,
    required this.totalWorkouts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('🔥', style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Text(
                'Стрик: $streak дней',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Тренировок всего: $totalWorkouts',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
