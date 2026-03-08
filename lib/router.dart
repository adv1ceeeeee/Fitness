import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

// ─────────────────────────────────────────────────────────────────────────────

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  static final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
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

      // ── All post-auth screens wrapped in MainShell (bottom nav always visible)
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainShell(
          location: state.matchedLocation,
          child: child,
        ),
        routes: [
          // Tab roots
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/workouts',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: WorkoutsScreen(),
            ),
          ),
          GoRoute(
            path: '/analytics',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AnalyticsScreen(),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProfileScreen(),
            ),
          ),

          // Secondary screens — bottom nav stays visible
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
          GoRoute(
            path: '/session/:sessionId',
            pageBuilder: (context, state) {
              final sessionId = state.pathParameters['sessionId']!;
              return _slideUpPage(
                  state, WorkoutSessionScreen(sessionId: sessionId));
            },
          ),
          GoRoute(
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
          GoRoute(
            path: '/workouts/create',
            pageBuilder: (context, state) =>
                _slideUpPage(state, const CreateWorkoutScreen()),
          ),
          GoRoute(
            path: '/workouts/:id/exercises',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id']!;
              return _slideUpPage(state, AddExercisesScreen(workoutId: id));
            },
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
        ],
      ),
    ],
  );
}
