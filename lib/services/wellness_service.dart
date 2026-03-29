import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/app_cache.dart';
import 'package:sportwai/services/auth_service.dart';

class WellnessService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> upsert({
    double? sleepHours,
    int? stress,
    int? energy,
    int? sleepQuality,
    int? soreness,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    final today = DateTime.now().toIso8601String().split('T')[0];

    sleepHours = sleepHours?.clamp(0.0, 24.0);
    stress = stress?.clamp(1, 10);
    energy = energy?.clamp(1, 10);
    sleepQuality = sleepQuality?.clamp(1, 5);
    soreness = soreness?.clamp(1, 5);

    await _client.from('wellness_logs').upsert(
      {
        'user_id': userId,
        'date': today,
        if (sleepHours != null) 'sleep_hours': sleepHours,
        if (stress != null) 'stress': stress,
        if (energy != null) 'energy': energy,
        if (sleepQuality != null) 'sleep_quality': sleepQuality,
        if (soreness != null) 'soreness': soreness,
      },
      onConflict: 'user_id,date',
    );
    // Wellness affects EnergyState and WellnessRec — bust unified UserState cache.
    await AppCache.invalidatePrefix('user_state:$userId');
    await AppCache.invalidatePrefix('energy_state:$userId');
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
