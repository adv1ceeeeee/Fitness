import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/services/app_cache.dart';

class ExerciseService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<Exercise>> getExercises({
    String? search,
    bool favoritesOnly = false,
  }) async {
    final userId = _client.auth.currentUser?.id;

    // Searched/filtered requests bypass cache (dynamic results).
    if (search != null && search.isNotEmpty) {
      return _fetchExercises(userId: userId, search: search,
          favoritesOnly: favoritesOnly);
    }

    // Full list is cached per user (stale-while-revalidate, 15 min TTL).
    final cacheKey = 'exercises_all:${userId ?? 'anon'}';
    final all = await AppCache.get<List<Exercise>>(
      key: cacheKey,
      ttl: const Duration(minutes: 15),
      fetch: () => _fetchExercises(userId: userId),
      encode: (list) => jsonEncode(list.map((e) => e.toJson()).toList()),
      decode: (s) => s == null
          ? []
          : (jsonDecode(s) as List)
              .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
              .toList(),
    );

    if (favoritesOnly) return all.where((e) => e.isFavorite).toList();
    return all;
  }

  static Future<List<Exercise>> _fetchExercises({
    required String? userId,
    String? search,
    bool favoritesOnly = false,
  }) async {
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

    if (favoritesOnly) return exercises.where((e) => e.isFavorite).toList();
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

    await AppCache.invalidatePrefix('exercises_all:');
    return Exercise.fromJson(res);
  }

  static Future<void> deleteExercise(String id) async {
    await _client.from('exercises').delete().eq('id', id);
    await AppCache.invalidatePrefix('exercises_all:');
  }

  /// Returns best estimated 1RM (Epley: w*(1+r/30)) per exercise_id
  /// for the current user. Only completed non-warmup sets with weight > 0.
  static Future<Map<String, double>> getBest1RMs() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};
    try {
      final rows = await _client
          .from('sets')
          .select('weight, reps, workout_exercises!inner(exercise_id)')
          .eq('completed', true)
          .eq('is_warmup', false)
          .gt('weight', 0);
      final result = <String, double>{};
      for (final r in rows as List) {
        final exId = (r['workout_exercises'] as Map)['exercise_id'] as String?;
        if (exId == null) continue;
        final w = (r['weight'] as num?)?.toDouble() ?? 0;
        final rep = (r['reps'] as num?)?.toDouble() ?? 0;
        if (w <= 0 || rep <= 0) continue;
        final orm = w * (1 + rep / 30.0);
        if ((result[exId] ?? 0) < orm) result[exId] = orm;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Returns usage count (number of completed sets) per exercise_id.
  static Future<Map<String, int>> getPopularity() async {
    try {
      final rows = await _client
          .from('sets')
          .select('workout_exercises!inner(exercise_id)')
          .eq('completed', true);
      final result = <String, int>{};
      for (final r in rows as List) {
        final exId = (r['workout_exercises'] as Map)['exercise_id'] as String?;
        if (exId == null) continue;
        result[exId] = (result[exId] ?? 0) + 1;
      }
      return result;
    } catch (_) {
      return {};
    }
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
    // Invalidate so next open reflects updated isFavorite flags.
    await AppCache.invalidate('exercises_all:$userId');
  }
}
