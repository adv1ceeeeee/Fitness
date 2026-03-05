import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
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
      extendBody: true, // body renders behind the glass bottom bar
      body: widget.child,
      floatingActionButton: _PlayStopFab(location: widget.location),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _GlassNavBar(
        currentIndex: _currentIndex,
        onTap: _onTap,
      ),
    );
  }
}

// ─── Glass navigation bar ────────────────────────────────────────────────────

class _GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _GlassNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          color: const Color(0xCC000000),
          child: SizedBox(
            height: 56 + bottomPadding,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      icon: CupertinoIcons.house,
                      activeIcon: CupertinoIcons.house_fill,
                      label: 'Главная',
                      isSelected: currentIndex == 0,
                      onTap: () => onTap(0),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: CupertinoIcons.flame,
                      activeIcon: CupertinoIcons.flame_fill,
                      label: 'Программы',
                      isSelected: currentIndex == 1,
                      onTap: () => onTap(1),
                    ),
                  ),
                  const SizedBox(width: 76), // FAB center space
                  Expanded(
                    child: _NavItem(
                      icon: CupertinoIcons.chart_bar,
                      activeIcon: CupertinoIcons.chart_bar_fill,
                      label: 'Аналитика',
                      isSelected: currentIndex == 2,
                      onTap: () => onTap(2),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: CupertinoIcons.person,
                      activeIcon: CupertinoIcons.person_fill,
                      label: 'Профиль',
                      isSelected: currentIndex == 3,
                      onTap: () => onTap(3),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
  void initState() {
    super.initState();
    _checkOpenSession();
  }

  Future<void> _checkOpenSession() async {
    // Only recover if no session is already active in provider
    if (ref.read(activeSessionProvider).isActive) return;
    final open = await TrainingService.getOpenSession();
    if (open == null || !mounted) return;
    final sessionId = open['id'] as String;
    final workoutId = open['workout_id'] as String;
    final workoutName =
        (open['workouts'] as Map<String, dynamic>?)?['name'] as String? ??
            'Тренировка';
    final createdAt = DateTime.tryParse(open['created_at'] as String? ?? '');
    ref.read(activeSessionProvider.notifier).start(
          sessionId: sessionId,
          workoutId: workoutId,
          workoutName: workoutName,
          startTime: createdAt,
        );
    _startTicker();
  }

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

    final session = await TrainingService.getOrCreateTodaySession(workout.id);
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
    final sessionId = state.sessionId!;
    final workoutId = state.workoutId!;

    _stopTicker();
    // Stop provider immediately so a second tap cannot push another summary screen.
    ref.read(activeSessionProvider.notifier).stop();

    context.push(
      '/session-summary',
      extra: {
        'sessionId': sessionId,
        'workoutId': workoutId,
        'durationSeconds': durationSeconds,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider);
    final isActive = session.isActive;

    if (isActive && _ticker == null) _startTicker();
    if (!isActive && _ticker != null) _stopTicker();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: FloatingActionButton(
            heroTag: 'playStopFab',
            onPressed: isActive ? _onStopTap : _onPlayTap,
            backgroundColor:
                isActive ? AppColors.error : AppColors.accent,
            elevation: 0,
            shape: const CircleBorder(),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive
                    ? CupertinoIcons.stop_fill
                    : CupertinoIcons.play_fill,
                key: ValueKey(isActive),
                color: Colors.white,
                size: 26,
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
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              isSelected ? activeIcon : icon,
              key: ValueKey(isSelected),
              size: 24,
              color: isSelected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.w400,
              color:
                  isSelected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          // iOS-style selection dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: isSelected ? 4 : 0,
            height: isSelected ? 4 : 0,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
