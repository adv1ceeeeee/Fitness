import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/exercise.dart';

class ExerciseService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<Exercise>> getExercises({String? search}) async {
    final userId = _client.auth.currentUser?.id;
    // Fetch standard exercises + user's own custom exercises via RLS policy
    var query = _client.from('exercises').select();

    if (search != null && search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }

    final res = await query.order('name');
    return (res as List)
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .where((e) => e.isStandard || e.userId == userId)
        .toList();
  }

  static Future<Exercise> createExercise({
    required String name,
    required String category,
    String? description,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final res = await _client.from('exercises').insert({
      'name': name.trim(),
      'category': category,
      if (description != null && description.isNotEmpty)
        'description': description.trim(),
      'is_standard': false,
      'user_id': userId,
    }).select().single();

    return Exercise.fromJson(res);
  }

  static Future<void> deleteExercise(String id) async {
    await _client.from('exercises').delete().eq('id', id);
  }
}
