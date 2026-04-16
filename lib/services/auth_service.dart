import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/exercise_service.dart';
import 'package:sportwai/services/image_cache_manager.dart';
import 'package:sportwai/services/profile_service.dart';
import 'package:sportwai/services/training_service.dart';
import 'package:sportwai/services/workout_service.dart';

class AuthService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Warm up frequently-used caches immediately after sign-in so the first
  /// screen (Home) opens without waiting on network. Fire-and-forget: errors
  /// are swallowed — the UI still falls back to normal fetches.
  static void prefetchOnLogin() {
    Future.wait([
      WorkoutService.getMyWorkouts(),
      ProfileService.getProfile(),
      ExerciseService.getExercises(),
      TrainingService.getTodayWorkout(),
      TrainingService.getDaysSinceLastWorkout(),
    ]).catchError((e) {
      if (kDebugMode) debugPrint('[AuthService.prefetchOnLogin] error: $e');
      return <dynamic>[];
    });
  }

  /// Wipe per-user caches so that data never leaks across accounts.
  /// Called from [signOut] / [deleteAccount].
  static Future<void> _clearUserCaches() async {
    await Future.wait([
      WorkoutService.clearAllCaches(),
      TrainingService.clearAllCaches(),
      AppImageCacheManager.clearAll(),
    ]);
  }

  static User? get currentUser => _client.auth.currentUser;

  /// Генерирует внутренний email из ника.
  /// Используется при регистрации и входе по нику.
  /// ВАЖНО: в настройках Supabase нужно отключить подтверждение email
  /// (Auth → Configuration → Email → Confirm email: OFF).
  static String nicknameToEmail(String nickname) =>
      '${nickname.toLowerCase().trim()}@sportwai.app';

  /// Регистрация по нику + паролю.
  static Future<AuthResponse> signUpByNickname(
    String nickname,
    String password,
  ) {
    return _client.auth.signUp(
      email: nicknameToEmail(nickname),
      password: password,
      data: {'nickname': nickname.toLowerCase().trim()},
    );
  }

  static Future<AuthResponse> signUp(
    String email,
    String password, {
    Map<String, dynamic>? data,
  }) {
    return _client.auth.signUp(email: email, password: password, data: data);
  }

  static Future<AuthResponse> signIn(String email, String password) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> resendSignupConfirmationEmail(String email) {
    return _client.auth.resend(type: OtpType.signup, email: email);
  }

  /// Обновить email в Supabase Auth (потребует подтверждения на новый адрес).
  static Future<void> updateAuthEmail(String newEmail) async {
    await _client.auth.updateUser(UserAttributes(email: newEmail));
  }

  static Future<void> signOut() async {
    await _clearUserCaches();
    await _client.auth.signOut();
  }

  /// Permanently deletes the current user account and all associated data.
  /// Calls the `delete-account` Edge Function which uses the admin client.
  static Future<void> deleteAccount() async {
    await _client.functions.invoke('delete-account', method: HttpMethod.post);
    await _clearUserCaches();
    await _client.auth.signOut();
  }

  static Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;
}
