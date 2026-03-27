import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/profile.dart';
import 'package:sportwai/services/app_cache.dart';
import 'package:sportwai/services/auth_service.dart';

class ProfileService {
  static SupabaseClient get _client => Supabase.instance.client;

  static String _cacheKey(String userId) => 'profile:$userId';

  static const _allowedProfileFields = {
    'nickname', 'full_name', 'gender', 'goal', 'level', 'birth_date',
    'weight_kg', 'height_cm', 'training_start_date', 'avatar_url', 'email',
  };

  static const _maxAvatarBytes = 5 * 1024 * 1024; // 5 MB

  static Future<Profile?> getProfile() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    return AppCache.get<Profile?>(
      key: _cacheKey(userId),
      ttl: const Duration(minutes: 10),
      fetch: () async {
        final res = await _client
            .from('profiles')
            .select()
            .eq('id', userId)
            .maybeSingle();
        if (res == null) return null;
        return Profile.fromJson(res);
      },
      encode: (p) => p == null ? null : jsonEncode(p.toJson()),
      decode: (s) {
        if (s == null) return null;
        try {
          return Profile.fromJson(jsonDecode(s) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      },
    );
  }

  static Future<Profile> createProfile(Profile profile) async {
    await _client.from('profiles').upsert(profile.toJson());
    final userId = AuthService.currentUser?.id;
    if (userId != null) await AppCache.invalidate(_cacheKey(userId));
    return profile;
  }

  static Future<void> updateProfile(Map<String, dynamic> updates) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;

    final safe = {
      for (final e in updates.entries)
        if (_allowedProfileFields.contains(e.key)) e.key: e.value,
    };
    if (safe.isEmpty) return;

    await _client.from('profiles').update({
      ...safe,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);

    // Invalidate so next read fetches fresh data
    await AppCache.invalidate(_cacheKey(userId));
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
    if (bytes.length > _maxAvatarBytes) {
      throw Exception('Файл слишком большой (максимум 5 МБ)');
    }
    // JPEG magic bytes: FF D8 FF
    if (bytes.length < 3 ||
        bytes[0] != 0xFF ||
        bytes[1] != 0xD8 ||
        bytes[2] != 0xFF) {
      throw Exception('Недопустимый формат файла. Загружайте только JPEG.');
    }

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
