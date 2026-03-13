import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

class ExportService {
  /// Exports all user training data as a flat CSV file (sets + metadata).
  static Future<void> exportCsv() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;

    final client = Supabase.instance.client;

    // Flat join: sets → workout_exercises → exercises + sessions → workouts
    final rows = await client
        .from('sets')
        .select(
          'set_number, weight, reps, rpe, completed, '
          'training_sessions!inner(date, duration_seconds, workout_id, '
          '  workouts(name)), '
          'workout_exercises!inner(exercises(name))',
        )
        .eq('training_sessions.user_id', userId)
        .order('training_sessions(date)', ascending: false);

    final buf = StringBuffer();
    buf.writeln('date,workout_name,exercise_name,set_number,weight_kg,reps,rpe,completed,session_duration_s');
    for (final r in rows) {
      final session = r['training_sessions'] as Map?;
      final workout = session?['workouts'] as Map?;
      final we = r['workout_exercises'] as Map?;
      final exercise = we?['exercises'] as Map?;
      buf.writeln([
        session?['date'] ?? '',
        _csvField(workout?['name'] ?? ''),
        _csvField(exercise?['name'] ?? ''),
        r['set_number'] ?? '',
        r['weight'] ?? '',
        r['reps'] ?? '',
        r['rpe'] ?? '',
        r['completed'] == true ? '1' : '0',
        session?['duration_seconds'] ?? '',
      ].join(','));
    }

    final bytes = Uint8List.fromList(utf8.encode(buf.toString()));
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);
    final fileName = 'sportwai_export_$dateStr.csv';

    await Share.shareXFiles(
      [XFile.fromData(bytes, name: fileName, mimeType: 'text/csv')],
      subject: 'Экспорт данных Sportify',
    );

    debugPrint('[ExportService] exported $fileName (${bytes.length} bytes)');
  }

  static String _csvField(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

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
      'app': 'Sportify',
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
      subject: 'Экспорт данных Sportify',
    );

    debugPrint('[ExportService] exported $fileName (${bytes.length} bytes)');
  }
}
