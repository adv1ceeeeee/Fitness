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
      final isOnboarding = state.matchedLocation == '/onboarding';

      if (!isAuth && !isAuthRoute) {
        return '/';
      }
      if (isAuth && isAuthRoute && state.matchedLocation == '/') {
        return '/onboarding-check';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/onboarding-check',
        builder: (context, state) => const OnboardingCheckScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainShell(
          location: state.matchedLocation,
          child: child,
        ),
        routes: [
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
          GoRoute(
            path: '/session/:sessionId',
            builder: (context, state) {
              final sessionId = state.pathParameters['sessionId']!;
              return WorkoutSessionScreen(sessionId: sessionId);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/calendar',
        builder: (context, state) => const CalendarScreen(),
      ),
      GoRoute(
        path: '/session-summary',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return SessionSummaryScreen(
            sessionId: extra['sessionId'] as String,
            workoutId: extra['workoutId'] as String,
            durationSeconds: extra['durationSeconds'] as int,
          );
        },
      ),
      GoRoute(
        path: '/pin-setup',
        builder: (context, state) => const PinSetupScreen(),
      ),
      GoRoute(
        path: '/pin-login',
        builder: (context, state) => const PinLoginScreen(),
      ),
      GoRoute(
        path: '/workouts/create',
        builder: (context, state) => const CreateWorkoutScreen(),
      ),
      GoRoute(
        path: '/workouts/:id/exercises',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return AddExercisesScreen(workoutId: id);
        },
      ),
      GoRoute(
        path: '/today',
        builder: (context, state) => const TodayScreen(),
      ),
    ],
  );
}
