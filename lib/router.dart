import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/screens/auth/welcome_screen.dart';
import 'package:sportwai/screens/auth/login_screen.dart';
import 'package:sportwai/screens/auth/register_screen.dart';
import 'package:sportwai/screens/onboarding/onboarding_screen.dart';
import 'package:sportwai/screens/home/home_screen.dart';
import 'package:sportwai/screens/workouts/workouts_screen.dart';
import 'package:sportwai/screens/workouts/create_workout_screen.dart';
import 'package:sportwai/screens/workouts/add_exercises_screen.dart';
import 'package:sportwai/screens/workout_session/today_screen.dart';
import 'package:sportwai/screens/workout_session/workout_session_screen.dart';
import 'package:sportwai/screens/profile/profile_screen.dart';
import 'package:sportwai/screens/analytics/analytics_screen.dart';
import 'package:sportwai/screens/auth/pin_setup_screen.dart';
import 'package:sportwai/screens/auth/pin_login_screen.dart';
import 'package:sportwai/screens/calendar/calendar_screen.dart';
import 'package:sportwai/screens/workout_session/session_summary_screen.dart';
import 'package:sportwai/screens/main_shell.dart';
import 'package:sportwai/screens/onboarding/onboarding_check_screen.dart';
import 'package:sportwai/screens/history/history_screen.dart';
import 'package:sportwai/screens/profile/body_metrics_screen.dart';
import 'package:sportwai/screens/analytics/personal_records_screen.dart';
import 'package:sportwai/screens/tools/calculators_screen.dart';
import 'package:sportwai/screens/analytics/exercise_history_screen.dart';
import 'package:sportwai/screens/profile/feedback_screen.dart';
import 'package:sportwai/models/exercise.dart';

// ── Transition helpers ────────────────────────────────────────────────────────

CustomTransitionPage<void> _slideUpPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.07),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
      child: child,
    ),
  );
}

// ─── Analytics observer ───────────────────────────────────────────────────────

class _ScreenViewObserver extends NavigatorObserver {
  String? _currentScreen;
  DateTime? _enteredAt;

  void _flush() {
    final screen = _currentScreen;
    final entered = _enteredAt;
    if (screen != null && entered != null) {
      final secs = DateTime.now().difference(entered).inSeconds;
      if (secs > 0) EventLogger.screenLeave(screen, durationSeconds: secs);
    }
    _currentScreen = null;
    _enteredAt = null;
  }

  void _enter(String? name) {
    if (name == null || name.isEmpty) return;
    EventLogger.screenView(name);
    _currentScreen = name;
    _enteredAt = DateTime.now();
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _flush();
    _enter(route.settings.name);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _flush();
    _enter(previousRoute?.settings.name);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _flush();
    _enter(newRoute?.settings.name);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _homeKey = GlobalKey<NavigatorState>(debugLabel: 'home');
  static final _workoutsKey = GlobalKey<NavigatorState>(debugLabel: 'workouts');
  static final _analyticsKey = GlobalKey<NavigatorState>(debugLabel: 'analytics');
  static final _profileKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

  static final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    observers: [_ScreenViewObserver()],
    initialLocation: '/',
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isAuth = session != null;
      final isAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/register') ||
          state.matchedLocation == '/';
      if (!isAuth && !isAuthRoute) {
        return '/';
      }
      if (isAuth && isAuthRoute && state.matchedLocation == '/') {
        return '/onboarding-check';
      }
      return null;
    },
    routes: [
      // ── Session screens (above shell — no bottom nav) ──────────────────────
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/session/:sessionId',
        pageBuilder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return _slideUpPage(state, WorkoutSessionScreen(sessionId: sessionId));
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/session-summary',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return _slideUpPage(
            state,
            SessionSummaryScreen(
              sessionId: extra['sessionId'] as String,
              workoutId: extra['workoutId'] as String,
              durationSeconds: extra['durationSeconds'] as int,
            ),
          );
        },
      ),

      // ── Auth & onboarding (no bottom nav) ─────────────────────────────────
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _fadePage(state, const WelcomeScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadePage(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) => _fadePage(state, const RegisterScreen()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _fadePage(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: '/onboarding-check',
        pageBuilder: (context, state) => _fadePage(state, const OnboardingCheckScreen()),
      ),
      GoRoute(
        path: '/pin-setup',
        pageBuilder: (context, state) => _fadePage(state, const PinSetupScreen()),
      ),
      GoRoute(
        path: '/pin-login',
        pageBuilder: (context, state) => _fadePage(state, const PinLoginScreen()),
      ),

      // ── All post-auth screens wrapped in MainShell (persistent tabs via StatefulShellRoute)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => MainShell(
          navigationShell: navigationShell,
        ),
        branches: [
          // ── Tab 0: Главная
          StatefulShellBranch(
            navigatorKey: _homeKey,
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: HomeScreen(),
                ),
              ),
              GoRoute(
                path: '/calendar',
                pageBuilder: (context, state) =>
                    _slideUpPage(state, const CalendarScreen()),
              ),
              GoRoute(
                path: '/today',
                pageBuilder: (context, state) =>
                    _slideUpPage(state, const TodayScreen()),
              ),
            ],
          ),

          // ── Tab 1: Программы
          StatefulShellBranch(
            navigatorKey: _workoutsKey,
            routes: [
              GoRoute(
                path: '/workouts',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: WorkoutsScreen(),
                ),
              ),
              GoRoute(
                path: '/workouts/create',
                pageBuilder: (context, state) =>
                    _slideUpPage(state, const CreateWorkoutScreen()),
              ),
              GoRoute(
                path: '/workouts/:id/exercises',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  final extra = state.extra as Map<String, dynamic>?;
                  return _slideUpPage(
                    state,
                    AddExercisesScreen(
                      workoutId: id,
                      pendingSectionIds:
                          (extra?['pendingIds'] as List?)?.cast<String>() ?? [],
                      sectionIndex: extra?['sectionIndex'] as int? ?? 0,
                      totalSections: extra?['totalSections'] as int? ?? 1,
                    ),
                  );
                },
              ),
            ],
          ),

          // ── Tab 2: Аналитика
          StatefulShellBranch(
            navigatorKey: _analyticsKey,
            routes: [
              GoRoute(
                path: '/analytics',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: AnalyticsScreen(),
                ),
              ),
              GoRoute(
                path: '/body-metrics',
                pageBuilder: (context, state) =>
                    _slideUpPage(state, const BodyMetricsScreen()),
              ),
              GoRoute(
                path: '/history',
                pageBuilder: (context, state) =>
                    _slideUpPage(state, const HistoryScreen()),
              ),
              GoRoute(
                path: '/records',
                pageBuilder: (context, state) =>
                    _slideUpPage(state, const PersonalRecordsScreen()),
              ),
              GoRoute(
                path: '/calculators',
                pageBuilder: (context, state) =>
                    _slideUpPage(state, const CalculatorsScreen()),
              ),
              GoRoute(
                path: '/exercise/:id/history',
                pageBuilder: (context, state) {
                  final exercise = state.extra as Exercise;
                  return _slideUpPage(
                      state, ExerciseHistoryScreen(exercise: exercise));
                },
              ),
            ],
          ),

          // ── Tab 3: Профиль
          StatefulShellBranch(
            navigatorKey: _profileKey,
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: ProfileScreen(),
                ),
              ),
              GoRoute(
                path: '/feedback',
                pageBuilder: (context, state) =>
                    _slideUpPage(state, const FeedbackScreen()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
