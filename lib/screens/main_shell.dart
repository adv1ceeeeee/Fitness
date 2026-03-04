import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/providers/active_session_provider.dart';
import 'package:sportwai/services/training_service.dart';

class MainShell extends ConsumerStatefulWidget {
  final String location;
  final Widget child;

  const MainShell({
    super.key,
    required this.location,
    required this.child,
  });

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  // 4 tabs: Home, Workouts — [FAB] — Analytics, Profile
  final _routes = ['/home', '/workouts', '/analytics', '/profile'];

  @override
  void initState() {
    super.initState();
    _syncIndex(widget.location);
  }

  @override
  void didUpdateWidget(MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _syncIndex(widget.location);
    }
  }

  void _syncIndex(String location) {
    final idx = _routes.indexOf(location);
    if (idx >= 0 && idx != _currentIndex) {
      setState(() => _currentIndex = idx);
    }
  }

  void _onTap(int index) {
    if (index != _currentIndex) {
      context.go(_routes[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      floatingActionButton: _PlayStopFab(location: widget.location),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.card,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        padding: EdgeInsets.zero,
        height: 60,
        child: Row(
          children: [
            Expanded(
              child: _NavItem(
                icon: Icons.home_rounded,
                label: 'Главная',
                isSelected: _currentIndex == 0,
                onTap: () => _onTap(0),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.fitness_center_rounded,
                label: 'Программы',
                isSelected: _currentIndex == 1,
                onTap: () => _onTap(1),
              ),
            ),
            const SizedBox(width: 80), // FAB notch space
            Expanded(
              child: _NavItem(
                icon: Icons.analytics_rounded,
                label: 'Аналитика',
                isSelected: _currentIndex == 2,
                onTap: () => _onTap(2),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.person_rounded,
                label: 'Профиль',
                isSelected: _currentIndex == 3,
                onTap: () => _onTap(3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Play / Stop FAB ─────────────────────────────────────────────────────────

class _PlayStopFab extends ConsumerStatefulWidget {
  final String location;

  const _PlayStopFab({required this.location});

  @override
  ConsumerState<_PlayStopFab> createState() => _PlayStopFabState();
}

class _PlayStopFabState extends ConsumerState<_PlayStopFab> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _onPlayTap() async {
    final workout = await TrainingService.getTodayWorkout();
    if (!mounted) return;

    if (workout == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сегодня тренировок нет. Добавьте программу.'),
        ),
      );
      return;
    }

    final session =
        await TrainingService.getOrCreateTodaySession(workout.id);
    if (!mounted || session == null) return;

    ref.read(activeSessionProvider.notifier).start(
          sessionId: session.id,
          workoutId: workout.id,
          workoutName: workout.name,
        );
    _startTicker();
    context.push('/session/${session.id}');
  }

  void _onStopTap() {
    final state = ref.read(activeSessionProvider);
    if (!state.isActive) return;

    final durationSeconds = state.elapsed.inSeconds;
    _stopTicker();

    context.push(
      '/session-summary',
      extra: {
        'sessionId': state.sessionId!,
        'workoutId': state.workoutId!,
        'durationSeconds': durationSeconds,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider);
    final isActive = session.isActive;

    // Sync ticker with provider state on rebuild
    if (isActive && _ticker == null) _startTicker();
    if (!isActive && _ticker != null) _stopTicker();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: FloatingActionButton(
            heroTag: 'playStopFab',
            onPressed: isActive ? _onStopTap : _onPlayTap,
            backgroundColor: isActive ? AppColors.error : AppColors.accent,
            elevation: 4,
            shape: const CircleBorder(),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? Icons.stop_rounded : Icons.play_arrow_rounded,
                key: ValueKey(isActive),
                color: Colors.black,
                size: 32,
              ),
            ),
          ),
        ),
        if (isActive) ...[
          const SizedBox(height: 2),
          Text(
            session.elapsedFormatted,
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Nav item ─────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: AnimatedScale(
              scale: isSelected ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: Icon(
                icon,
                size: 24,
                color: isSelected ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 10,
              color: isSelected ? AppColors.accent : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
            child: Text(label, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
