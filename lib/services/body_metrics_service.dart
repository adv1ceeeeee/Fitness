import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/auth_service.dart';

class BodyMetricsService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> upsert({
    double? weightKg,
    double? bodyFatPct,
    double? waistCm,
    DateTime? date,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    final dateStr = (date ?? DateTime.now()).toIso8601String().split('T')[0];

    await _client.from('body_metrics').upsert(
      {
        'user_id': userId,
        'date': dateStr,
        if (weightKg != null) 'weight_kg': weightKg,
        if (bodyFatPct != null) 'body_fat_pct': bodyFatPct,
        if (waistCm != null) 'waist_cm': waistCm,
      },
      onConflict: 'user_id,date',
    );
  }

  static Future<Map<String, dynamic>?> getLatest() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    return await _client
        .from('body_metrics')
        .select()
        .eq('user_id', userId)
        .order('date', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> getHistory() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    final fromStr = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String()
        .split('T')[0];

    final res = await _client
        .from('body_metrics')
        .select()
        .eq('user_id', userId)
        .gte('date', fromStr)
        .order('date', ascending: true);

    return (res as List).cast<Map<String, dynamic>>();
  }
}
