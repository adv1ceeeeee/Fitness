import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/auth_service.dart';

class WellnessService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> upsert({
    double? sleepHours,
    int? stress,
    int? energy,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    final today = DateTime.now().toIso8601String().split('T')[0];

    await _client.from('wellness_logs').upsert(
      {
        'user_id': userId,
        'date': today,
        if (sleepHours != null) 'sleep_hours': sleepHours,
        if (stress != null) 'stress': stress,
        if (energy != null) 'energy': energy,
      },
      onConflict: 'user_id,date',
    );
  }

  static Future<Map<String, dynamic>?> getTodayLog() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;
    final today = DateTime.now().toIso8601String().split('T')[0];

    return await _client
        .from('wellness_logs')
        .select()
        .eq('user_id', userId)
        .eq('date', today)
        .maybeSingle();
  }
}
