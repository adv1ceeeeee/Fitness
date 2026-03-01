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
    return Profile.fromJson(res as Map<String, dynamic>);
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

  static Future<void> createProfileOnSignUp(String userId, String? email) async {
    await _client.from('profiles').insert({
      'id': userId,
      'full_name': email?.split('@').first ?? 'User',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
