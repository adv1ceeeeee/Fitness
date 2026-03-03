import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static SupabaseClient get _client => Supabase.instance.client;

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
      data: {'nickname': nickname},
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

  static Future<void> signOut() {
    return _client.auth.signOut();
  }

  static Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;
}
