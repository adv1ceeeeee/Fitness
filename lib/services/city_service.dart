import 'package:supabase_flutter/supabase_flutter.dart';

class CityService {
  /// Возвращает список предложений городов по запросу через Edge Function.
  /// Ключ DaData хранится на сервере (Supabase secret), не в бинарнике.
  static Future<List<String>> suggest(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'suggest-city',
        body: {'query': query},
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null) return [];
      final suggestions = data['suggestions'] as List<dynamic>? ?? [];
      return suggestions
          .map((s) => (s as Map<String, dynamic>)['value'] as String)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
