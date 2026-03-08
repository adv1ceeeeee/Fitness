import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/services/auth_service.dart';

class ProfileService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<Profile?> getProfile() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    final res = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (res == null) return null;
    return Profile.fromJson(res);
  }

  static Future<Profile> createProfile(Profile profile) async {
    await _client.from('profiles').upsert(profile.toJson());
    return profile;
  }

  static Future<void> updateProfile(Map<String, dynamic> updates) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;

    await _client.from('profiles').update({
      ...updates,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Проверяет, свободен ли ник (не занят другим пользователем).
  static Future<bool> isNicknameAvailable(String nickname) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return false;

    final res = await _client
        .from('profiles')
        .select('id')
        .ilike('nickname', nickname.trim())
        .neq('id', userId)
        .maybeSingle();

    return res == null;
  }

  /// Обновляет email: сохраняет в profiles и инициирует смену в Supabase Auth.
  static Future<void> updateEmail(String newEmail) async {
    await AuthService.updateAuthEmail(newEmail);
    await updateProfile({'email': newEmail});
  }

  /// Загружает аватарку в Supabase Storage и возвращает публичный URL.
  /// Требует bucket "avatars" с публичным доступом в Supabase Dashboard.
  static Future<String> uploadAvatar(Uint8List bytes) async {
    final userId = AuthService.currentUser!.id;
    final path = '$userId.jpg';

    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );

    return _client.storage.from('avatars').getPublicUrl(path);
  }
}
