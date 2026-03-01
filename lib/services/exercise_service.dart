import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/models/exercise.dart';

class ExerciseService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<Exercise>> getExercises({String? search}) async {
    var query = _client.from('exercises').select().eq('is_standard', true);

    if (search != null && search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }

    final res = await query.order('name');
    return (res as List)
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
