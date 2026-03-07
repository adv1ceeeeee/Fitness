import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/auth_service.dart';

class BodyMetricsService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> upsert({
    double? weightKg,
    double? bodyFatPct,
    double? neckCm,
    double? shouldersCm,
    double? chestCm,
    double? waistCm,
    double? rightArmCm,
    double? leftArmCm,
    double? rightForearmCm,
    double? leftForearmCm,
    double? hipsCm,
    double? leftThighCm,
    double? rightThighCm,
    double? rightCalfCm,
    double? leftCalfCm,
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
        if (neckCm != null) 'neck_cm': neckCm,
        if (shouldersCm != null) 'shoulders_cm': shouldersCm,
        if (chestCm != null) 'chest_cm': chestCm,
        if (waistCm != null) 'waist_cm': waistCm,
        if (rightArmCm != null) 'right_arm_cm': rightArmCm,
        if (leftArmCm != null) 'left_arm_cm': leftArmCm,
        if (rightForearmCm != null) 'right_forearm_cm': rightForearmCm,
        if (leftForearmCm != null) 'left_forearm_cm': leftForearmCm,
        if (hipsCm != null) 'hips_cm': hipsCm,
        if (leftThighCm != null) 'left_thigh_cm': leftThighCm,
        if (rightThighCm != null) 'right_thigh_cm': rightThighCm,
        if (rightCalfCm != null) 'right_calf_cm': rightCalfCm,
        if (leftCalfCm != null) 'left_calf_cm': leftCalfCm,
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
