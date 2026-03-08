import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

class ExportService {
  /// Exports all user training data as a JSON file shared via share_plus.
  static Future<void> exportData() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;

    final client = Supabase.instance.client;

    // Fetch everything in parallel
    final results = await Future.wait([
      client
          .from('workouts')
          .select('*, workout_exercises(*, exercises(name, category))')
          .eq('user_id', userId)
          .order('created_at'),
      client
          .from('training_sessions')
          .select('*, sets(*)')
          .eq('user_id', userId)
          .order('date', ascending: false),
      client
          .from('body_metrics')
          .select()
          .eq('user_id', userId)
          .order('date', ascending: false),
      client
          .from('wellness_logs')
          .select()
          .eq('user_id', userId)
          .order('date', ascending: false),
    ]);

    final payload = {
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'SportWAI',
      'version': 1,
      'workouts': results[0],
      'training_sessions': results[1],
      'body_metrics': results[2],
      'wellness_logs': results[3],
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));

    final dateStr = DateTime.now()
        .toIso8601String()
        .substring(0, 10); // yyyy-MM-dd
    final fileName = 'sportwai_export_$dateStr.json';

    final xfile = XFile.fromData(
      bytes,
      name: fileName,
      mimeType: 'application/json',
    );

    await Share.shareXFiles(
      [xfile],
      subject: 'Экспорт данных SportWAI',
    );

    debugPrint('[ExportService] exported $fileName (${bytes.length} bytes)');
  }
}
