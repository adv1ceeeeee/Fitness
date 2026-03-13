import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/exercise.dart';

class ExerciseService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<Exercise>> getExercises({
    String? search,
    bool favoritesOnly = false,
  }) async {
    final userId = _client.auth.currentUser?.id;

    // Join with favorites to get is_favorite flag per user
    var query = _client.from('exercises').select(
          userId != null
              ? '*, user_favorite_exercises!left(user_id)'
              : '*',
        );

    if (search != null && search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }

    final res = await query.order('name');
    final exercises = (res as List).map((e) {
      final map = e as Map<String, dynamic>;
      // Determine isFavorite from the left-join result
      final favRows = map['user_favorite_exercises'] as List?;
      final isFav = favRows != null &&
          favRows.any((f) => (f as Map)['user_id'] == userId);
      return Exercise.fromJson({...map, 'is_favorite': isFav});
    }).where((e) => e.isStandard || e.userId == userId).toList();

    if (favoritesOnly) {
      return exercises.where((e) => e.isFavorite).toList();
    }
    return exercises;
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

  static Future<void> toggleFavorite(
    String exerciseId, {
    required bool add,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    if (add) {
      await _client.from('user_favorite_exercises').upsert({
        'user_id': userId,
        'exercise_id': exerciseId,
      });
    } else {
      await _client
          .from('user_favorite_exercises')
          .delete()
          .eq('user_id', userId)
          .eq('exercise_id', exerciseId);
    }
  }
}
