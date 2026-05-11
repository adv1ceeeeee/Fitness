import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/models/workout.dart';
import 'package:sportwai/models/workout_exercise.dart';
import 'package:sportwai/providers/active_session_provider.dart';
import 'package:sportwai/providers/connectivity_provider.dart';
import 'package:sportwai/screens/workout_session/free_workout_screen.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/notification_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/version_service.dart';
import 'package:sportwai/services/recsys_service.dart';
import 'package:sportwai/services/wellness_service.dart';
import 'package:sportwai/services/workout_service.dart';

class MainShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({
    super.key,
    required this.navigationShell,
  });

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _routes = ['/home', '/workouts', '/analytics', '/profile'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) VersionService.checkAndPrompt(context);
    });
  }

  void _onTap(int index) {
    HapticFeedback.selectionClick();
    if (index == widget.navigationShell.currentIndex) {
      // Same tab tapped — pop to branch root
      context.go(_routes[index]);
    } else {
      // Switch tab — preserve branch navigation stack
      widget.navigationShell.goBranch(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.isOnline;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      extendBody: true, // body renders behind the glass bottom bar
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: isOnline ? 0 : 28,
            color: const Color(0xFFFF9500),
            child: isOnline
                ? const SizedBox.shrink()
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, size: 14, color: Colors.black87),
                      SizedBox(width: 6),
                      Text(
                        'Нет соединения — данные могут быть устаревшими',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
          Expanded(child: widget.navigationShell),
        ],
      ),
      floatingActionButton: keyboardOpen ? null : const _PlayStopFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _GlassNavBar(
        currentIndex: widget.navigationShell.currentIndex,
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
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xBB000000),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
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
  const _PlayStopFab();

  @override
  ConsumerState<_PlayStopFab> createState() => _PlayStopFabState();
}

class _PlayStopFabState extends ConsumerState<_PlayStopFab> {
  Timer? _ticker;
  bool _starting = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _RecoverySheet(
          workoutName: workoutName,
          createdAt: createdAt,
          onResume: () {
            Navigator.pop(ctx);
            ref.read(activeSessionProvider.notifier).start(
                  sessionId: sessionId,
                  workoutId: workoutId,
                  workoutName: workoutName,
                  startTime: createdAt,
                );
            _startTicker();
            context.push('/session/$sessionId');
          },
          onRestart: () async {
            Navigator.pop(ctx);
            await TrainingService.deleteSession(sessionId);
            final newSession =
                await TrainingService.getOrCreateTodaySession(workoutId);
            if (!mounted || newSession == null) return;
            ref.read(activeSessionProvider.notifier).start(
                  sessionId: newSession.id,
                  workoutId: workoutId,
                  workoutName: workoutName,
                );
            _startTicker();
            context.push('/session/${newSession.id}');
          },
          onDismiss: () => Navigator.pop(ctx),
        ),
      );
    });
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

  void _openFreeWorkout() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FreeWorkoutScreen(
        onStart: (sessionId, workoutId, workoutName) {
          Navigator.of(context).pop(); // close FreeWorkoutScreen
          ref.read(activeSessionProvider.notifier).start(
                sessionId: sessionId,
                workoutId: workoutId,
                workoutName: workoutName,
              );
          EventLogger.workoutStarted(
            workoutId: workoutId,
            workoutName: workoutName,
            sessionId: sessionId,
          );
          NotificationService.cancelInactivityReminder();
          _startTicker();
          context.push('/session/$sessionId');
        },
      ),
    ));
  }

  Future<bool> _showWellnessWarning(WellnessRec rec) async {
    final (color, icon) = switch (rec.severity) {
      RecSeverity.critical => (const Color(0xFFFF453A), Icons.warning_rounded),
      RecSeverity.warning => (
          const Color(0xFFFF9F0A),
          Icons.info_outline_rounded
        ),
      RecSeverity.info => (AppColors.accent, Icons.info_outline_rounded),
    };
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                rec.title,
                style: TextStyle(
                    color: color, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Text(
          rec.message,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отменить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Всё равно начать'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _onPlayTap() async {
    if (_starting) return;
    setState(() => _starting = true);

    final cyclicWorkoutFuture = TrainingService.getTodayWorkout()
        .timeout(const Duration(seconds: 5))
        .catchError((_) => null);
    final todaySessionsFuture = TrainingService.getTodayIncompleteSessions()
        .timeout(const Duration(seconds: 5))
        .catchError((_) => <Map<String, dynamic>>[]);
    final allWorkoutsFuture = WorkoutService.getMyWorkouts()
        .timeout(const Duration(seconds: 5))
        .catchError((_) => <Workout>[]);
    final wellnessFuture = WellnessService.getTodayLog()
        .timeout(const Duration(seconds: 3))
        .catchError((_) => null);

    final cyclicWorkout = await cyclicWorkoutFuture;
    final todaySessions = await todaySessionsFuture;
    final allWorkouts = await allWorkoutsFuture;
    final wellness = await wellnessFuture;
    if (!mounted) return;
    setState(() => _starting = false);

    final choices = <_WorkoutChoice>[];

    for (final s in todaySessions) {
      final name =
          (s['workouts'] as Map<String, dynamic>?)?['name'] as String? ??
              'Тренировка';
      choices.add(_WorkoutChoice(
        sessionId: s['id'] as String,
        workoutId: s['workout_id'] as String,
        workoutName: name,
        isCyclic: false,
      ));
    }

    if (cyclicWorkout != null &&
        !choices.any((c) => c.workoutId == cyclicWorkout.id)) {
      choices.add(_WorkoutChoice(
        workoutId: cyclicWorkout.id,
        workoutName: cyclicWorkout.name,
        isCyclic: true,
      ));
    }

    // Add all remaining user programs not yet in choices
    for (final w in allWorkouts) {
      if (!choices.any((c) => c.workoutId == w.id)) {
        choices.add(_WorkoutChoice(
          workoutId: w.id,
          workoutName: w.name,
          isCyclic: false,
        ));
      }
    }

    // ── Wellness check before starting ──────────────────────────────────────
    final rec = evaluateWellness(wellness);
    if (rec != null && mounted) {
      final proceed = await _showWellnessWarning(rec);
      if (!proceed || !mounted) return;
    }
    if (!mounted) return;

    // Show sheet (even if empty — user can pick free workout)
    if (choices.isEmpty) {
      _openFreeWorkout();
      return;
    }

    // Show sheet with workout choices + free workout option
    final result = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _StartChoiceSheet(
        choices: choices,
        onFreeWorkout: () => Navigator.pop(ctx, 'free'),
      ),
    );
    if (!mounted) return;
    if (result == 'free') {
      _openFreeWorkout();
      return;
    }
    if (result == null) return;
    final choice = result as _WorkoutChoice;

    final String finalSessionId;
    if (choice.sessionId != null) {
      finalSessionId = choice.sessionId!;
    } else {
      setState(() => _starting = true);
      unawaited(
        TrainingService.getWorkoutExercisesForToday(choice.workoutId)
            .timeout(const Duration(seconds: 6))
            .catchError((_) => <WorkoutExercise>[]),
      );
      final session =
          await TrainingService.getOrCreateTodaySession(choice.workoutId);
      if (!mounted || session == null) {
        if (mounted) setState(() => _starting = false);
        return;
      }
      finalSessionId = session.id;
    }

    ref.read(activeSessionProvider.notifier).start(
          sessionId: finalSessionId,
          workoutId: choice.workoutId,
          workoutName: choice.workoutName,
        );
    EventLogger.workoutStarted(
      workoutId: choice.workoutId,
      workoutName: choice.workoutName,
      sessionId: finalSessionId,
    );
    NotificationService.cancelInactivityReminder();
    _startTicker();
    if (mounted) setState(() => _starting = false);
    context.push('/session/$finalSessionId');
  }

  void _onStopTap() {
    final state = ref.read(activeSessionProvider);
    if (!state.isActive) return;
    // Обычный тап — диалог подтверждения
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Завершить тренировку?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          'Прошло ${state.elapsedFormatted}. Данные будут сохранены.',
          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Продолжить',
                style: TextStyle(color: Color(0xFF30D158))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Завершить',
                style: TextStyle(color: Color(0xFFFF453A))),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) _doStop();
    });
  }

  void _onStopLongPress() {
    HapticFeedback.heavyImpact();
    _doStop();
  }

  void _doStop() {
    final state = ref.read(activeSessionProvider);
    if (!state.isActive) return;

    final durationSeconds = state.elapsed.inSeconds;
    final sessionId = state.sessionId!;
    final workoutId = state.workoutId!;

    _stopTicker();
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
        GestureDetector(
          onLongPress: isActive ? _onStopLongPress : null,
          onTap: _starting ? null : (isActive ? _onStopTap : _onPlayTap),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isActive ? null : AppColors.accentGradient,
              color: isActive ? AppColors.error : null,
              boxShadow: [
                BoxShadow(
                  color: (isActive ? AppColors.error : AppColors.accent)
                      .withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _starting
                  ? const SizedBox(
                      key: ValueKey('starting'),
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Transform.translate(
                      offset: Offset(isActive ? 0 : 2, 0),
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

// ─── Workout choice model ─────────────────────────────────────────────────────

class _WorkoutChoice {
  final String? sessionId;
  final String workoutId;
  final String workoutName;
  final bool isCyclic;

  const _WorkoutChoice({
    this.sessionId,
    required this.workoutId,
    required this.workoutName,
    required this.isCyclic,
  });
}

// ─── Start choice sheet ───────────────────────────────────────────────────────

class _StartChoiceSheet extends StatelessWidget {
  final List<_WorkoutChoice> choices;
  final VoidCallback onFreeWorkout;

  const _StartChoiceSheet({
    required this.choices,
    required this.onFreeWorkout,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Text(
              'Какую тренировку начать?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              padding: EdgeInsets.fromLTRB(24, 0, 24, bottomPadding + 16),
              shrinkWrap: true,
              children: [
                ...choices.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: AppColors.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: AppColors.cardBorder, width: 1),
                      ),
                      child: InkWell(
                        onTap: () => Navigator.pop(context, c),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(
                                c.isCyclic
                                    ? Icons.calendar_month_outlined
                                    : Icons.fitness_center_outlined,
                                size: 20,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.workoutName,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      c.isCyclic
                                          ? 'По расписанию программы'
                                          : 'Программа тренировок',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  size: 18, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Free workout option
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: onFreeWorkout,
                      borderRadius: BorderRadius.circular(14),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.shuffle,
                                size: 20, color: AppColors.textSecondary),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Свободная тренировка',
                                      style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w500)),
                                  SizedBox(height: 2),
                                  Text('Выбрать упражнения вручную',
                                      style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right,
                                size: 18, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recovery sheet ───────────────────────────────────────────────────────────

class _RecoverySheet extends StatelessWidget {
  final String workoutName;
  final DateTime? createdAt;
  final VoidCallback onResume;
  final Future<void> Function() onRestart;
  final VoidCallback onDismiss;

  const _RecoverySheet({
    required this.workoutName,
    required this.createdAt,
    required this.onResume,
    required this.onRestart,
    required this.onDismiss,
  });

  String _timeAgo() {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt!);
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    return '${diff.inDays} дн назад';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fitness_center,
                    color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Незавершённая тренировка',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$workoutName · ${_timeAgo()}',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          GradientButton(
            onPressed: onResume,
            height: 50,
            child: const Text('Продолжить'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: onRestart,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.textSecondary),
              ),
              child: const Text('Начать заново'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: TextButton(
              onPressed: onDismiss,
              child: const Text('Отмена',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
        ],
      ),
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
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? AppColors.accent : AppColors.textSecondary,
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
