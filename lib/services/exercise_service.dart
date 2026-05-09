import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/data/standard_programs.dart';
import 'package:sportwai/models/exercise.dart';
import 'package:sportwai/services/app_cache.dart';

class ExerciseService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const _lightColumns = '''
id,name,name_ru,category,image_url,is_standard,user_id,gif_url
''';

  static const _detailColumns = '''
id,name,name_ru,category,description,description_ru,image_url,is_standard,user_id,gif_url
''';

  static String _cacheKey({
    required String? userId,
    required bool includeDetails,
    required bool includeFavorites,
  }) {
    final cacheVersion = includeDetails ? 'v5_full' : 'v5_light';
    final favoritesSuffix = includeFavorites ? '_fav' : '';
    return 'exercises_all_$cacheVersion$favoritesSuffix:${userId ?? 'anon'}';
  }

  static String? _encodeExercises(List<Exercise> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<Exercise> _decodeExercises(String? cached) => cached == null
      ? []
      : (jsonDecode(cached) as List)
          .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
          .toList();

  static bool isLocalFallbackExercise(Exercise exercise) =>
      exercise.id.startsWith('local_standard:');

  static List<Exercise> getLocalFallbackExercises() {
    final names = <String>{};

    void collectExercises(List exercises) {
      for (final item in exercises) {
        final map = item as Map<String, dynamic>;
        final name = map['name'] as String?;
        if (name != null && name.trim().isNotEmpty) names.add(name.trim());
      }
    }

    for (final program in standardPrograms) {
      final sections = program['sections'] as List?;
      if (sections != null) {
        for (final section in sections) {
          collectExercises(
              (section as Map<String, dynamic>)['exercises'] as List);
        }
      } else {
        collectExercises(program['exercises'] as List);
      }
    }

    final list = [
      for (final name in names)
        Exercise(
          id: 'local_standard:${base64Url.encode(utf8.encode(name))}',
          name: name,
          category: _inferCategory(name),
          isStandard: true,
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  static Future<Exercise?> resolveExercise(Exercise exercise) async {
    if (!isLocalFallbackExercise(exercise)) return exercise;
    final matches = await _fetchExercises(
      userId: _client.auth.currentUser?.id,
      search: exercise.name,
      includeDetails: false,
    );
    final query = _normalize(exercise.name);
    for (final candidate in matches) {
      if (_normalize(candidate.name) == query ||
          _normalize(candidate.nameRu ?? '') == query) {
        return candidate;
      }
    }
    return matches.isNotEmpty ? matches.first : null;
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll('ё', 'е').trim();

  static String _inferCategory(String name) {
    final n = _normalize(name);
    bool has(List<String> parts) => parts.any(n.contains);

    if (has([
      'бег',
      'велосипед',
      'эллипс',
      'гребн',
      'берпи',
      'альпинист',
      'джампинг',
      'скакал',
      'плав',
      'hiit',
      'ходьба',
      'бокс',
      'зумба',
      'кардио'
    ])) {
      return 'cardio';
    }
    if (has([
      'планк',
      'скручив',
      'пресс',
      'вакуум',
      'ножниц',
      'подъем ног',
      'подъём ног',
      'колесо',
      'твист',
      'дровосек'
    ])) {
      return 'core';
    }
    if (has([
      'присед',
      'ног',
      'выпад',
      'ягод',
      'икр',
      'нос',
      'гак',
      'гудморнинг',
      'трастер'
    ])) {
      return 'legs';
    }
    if (has([
      'плеч',
      'махи',
      'арнольд',
      'военный',
      'стоя',
      'лендмайн',
      'турецкий',
      'толчок гири'
    ])) {
      return 'shoulders';
    }
    if (has([
      'бицеп',
      'трицеп',
      'француз',
      'сгибан',
      'разгибан',
      'кикбэк',
      'обратные отжимания'
    ])) {
      return 'arms';
    }
    if (has([
      'подтяг',
      'тяга',
      'шраг',
      'гипер',
      'становая',
      'лодочка',
      'фермер',
      'рывок'
    ])) {
      return 'back';
    }
    if (has(
        ['жим', 'груд', 'отжим', 'пек', 'развод', 'кроссовер', 'пуловер'])) {
      return 'chest';
    }
    return 'chest';
  }

  static Future<List<Exercise>> getExercises({
    String? search,
    bool favoritesOnly = false,
    bool includeDetails = false,
    bool includeFavorites = false,
  }) async {
    final userId = _client.auth.currentUser?.id;
    final shouldIncludeFavorites = includeFavorites || favoritesOnly;

    // Searched/filtered requests bypass cache (dynamic results).
    if (search != null && search.isNotEmpty) {
      return _fetchExercises(
        userId: userId,
        search: search,
        favoritesOnly: favoritesOnly,
        includeDetails: includeDetails,
        includeFavorites: shouldIncludeFavorites,
      );
    }

    // Full list is cached per user (stale-while-revalidate, 15 min TTL).
    final all = await AppCache.get<List<Exercise>>(
      key: _cacheKey(
        userId: userId,
        includeDetails: includeDetails,
        includeFavorites: shouldIncludeFavorites,
      ),
      ttl: const Duration(days: 1),
      fetch: () => _fetchExercises(
        userId: userId,
        includeDetails: includeDetails,
        includeFavorites: shouldIncludeFavorites,
      ),
      encode: _encodeExercises,
      decode: _decodeExercises,
    );

    if (favoritesOnly) return all.where((e) => e.isFavorite).toList();
    return all;
  }

  static Future<List<Exercise>> getCachedExercises({
    bool includeDetails = false,
    bool includeFavorites = false,
  }) async {
    final userId = _client.auth.currentUser?.id;
    return await AppCache.peek<List<Exercise>>(
          key: _cacheKey(
            userId: userId,
            includeDetails: includeDetails,
            includeFavorites: includeFavorites,
          ),
          decode: (cached) => _decodeExercises(cached),
        ) ??
        const <Exercise>[];
  }

  static Future<List<Exercise>> _fetchExercises({
    required String? userId,
    String? search,
    bool favoritesOnly = false,
    bool includeDetails = false,
    bool includeFavorites = false,
  }) async {
    final columns = includeDetails ? _detailColumns : _lightColumns;

    var query = _client.from('exercises').select(columns);
    query = userId == null
        ? query.eq('is_standard', true)
        : query.or('is_standard.eq.true,user_id.eq.$userId');

    if (search != null && search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }

    final results = await Future.wait([
      query.order('name'),
      if (userId != null && includeFavorites)
        _client
            .from('user_favorite_exercises')
            .select('exercise_id')
            .eq('user_id', userId)
      else
        Future<List<dynamic>>.value(const []),
    ]);
    final res = results[0];
    final favoriteRows = results[1];
    final favoriteIds = favoriteRows
        .map((row) => (row as Map)['exercise_id'] as String?)
        .whereType<String>()
        .toSet();

    final exercises = res.map((e) {
      final map = e as Map<String, dynamic>;
      return Exercise.fromJson({
        ...map,
        'is_favorite': favoriteIds.contains(map['id'] as String?),
      });
    }).toList();

    if (favoritesOnly) return exercises.where((e) => e.isFavorite).toList();
    return exercises;
  }

  static Future<Set<String>> getFavoriteExerciseIds() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const {};
    final rows = await _client
        .from('user_favorite_exercises')
        .select('exercise_id')
        .eq('user_id', userId);
    return (rows as List)
        .map((row) => (row as Map)['exercise_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  static Future<Exercise?> getExercise(
    String id, {
    bool includeDetails = true,
  }) async {
    final userId = _client.auth.currentUser?.id;
    final columns = includeDetails ? _detailColumns : _lightColumns;
    final results = await Future.wait<dynamic>([
      _client.from('exercises').select(columns).eq('id', id).maybeSingle(),
      if (userId != null)
        _client
            .from('user_favorite_exercises')
            .select('exercise_id')
            .eq('user_id', userId)
            .eq('exercise_id', id)
      else
        Future<List<dynamic>>.value(const []),
    ]);
    final row = results[0] as Map<String, dynamic>?;
    if (row == null) return null;
    final favoriteRows = results[1] as List;
    return Exercise.fromJson({
      ...row,
      'is_favorite': favoriteRows.isNotEmpty,
    });
  }

  static Future<Exercise> createExercise({
    required String name,
    required String category,
    String? description,
    String? nameRu,
    String? inputMode,
    String? equipmentType,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final trimmedName = name.trim();
    final trimmedDesc = description?.trim();
    final trimmedNameRu = nameRu?.trim();

    final res = await _client
        .from('exercises')
        .insert({
          'name': trimmedName,
          'category': category,
          if (trimmedNameRu != null && trimmedNameRu.isNotEmpty)
            'name_ru': trimmedNameRu,
          if (trimmedDesc != null && trimmedDesc.isNotEmpty)
            'description': trimmedDesc,
          if (inputMode != null) 'input_mode': inputMode,
          if (equipmentType != null) 'equipment_type': equipmentType,
          'is_standard': false,
          'user_id': userId,
        })
        .select()
        .single();

    await AppCache.invalidatePrefix('exercises_all_');
    return Exercise.fromJson(res);
  }

  static Future<void> deleteExercise(String id) async {
    await _client.from('exercises').delete().eq('id', id);
    await AppCache.invalidatePrefix('exercises_all_');
  }

  /// Updates a user-owned exercise. Only non-null fields are touched; a null
  /// parameter means "leave as is". RLS policies ensure users can only edit
  /// exercises they own.
  static Future<Exercise> updateExercise({
    required String id,
    String? name,
    String? nameRu,
    String? category,
    String? description,
    String? inputMode,
    String? equipmentType,
  }) async {
    final patch = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (nameRu != null)
        'name_ru': nameRu.trim().isEmpty ? null : nameRu.trim(),
      if (category != null) 'category': category,
      if (description != null)
        'description': description.trim().isEmpty ? null : description.trim(),
      if (inputMode != null) 'input_mode': inputMode,
      if (equipmentType != null) 'equipment_type': equipmentType,
    };
    if (patch.isEmpty) {
      throw ArgumentError('updateExercise called with no fields to update');
    }
    final res = await _client
        .from('exercises')
        .update(patch)
        .eq('id', id)
        .select()
        .single();
    await AppCache.invalidatePrefix('exercises_all_');
    return Exercise.fromJson(res);
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
    await AppCache.invalidatePrefix('exercises_all_');
  }
}
