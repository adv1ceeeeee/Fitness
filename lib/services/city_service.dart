import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sportwai/config/app_config.dart';

class CityService {
  static const _endpoint =
      'https://suggestions.dadata.ru/suggestions/api/4_1/rs/suggest/city';

  /// Возвращает список предложений городов по запросу.
  /// Требует действительный [AppConfig.dadataApiKey].
  static Future<List<String>> suggest(String query) async {
    if (query.trim().isEmpty) return [];

    if (AppConfig.dadataApiKey == 'YOUR_DADATA_API_KEY') {
      // Ключ не настроен — возвращаем пустой список
      return [];
    }

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Token ${AppConfig.dadataApiKey}',
            },
            body: jsonEncode({'query': query, 'count': 7}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = data['suggestions'] as List<dynamic>;
      return suggestions
          .map((s) => (s as Map<String, dynamic>)['value'] as String)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
