import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Проверяет минимальную поддерживаемую версию приложения.
///
/// Значение `min_version` хранится в таблице `app_config` в Supabase.
/// Если текущая версия ниже — показывает неотключаемый диалог обновления.
class VersionService {
  VersionService._();

  /// Проверить версию и при необходимости показать диалог обновления.
  /// Возвращает `true` если версия актуальна (можно продолжать).
  static Future<bool> checkAndPrompt(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version; // e.g. '1.2.3'

      final result = await Supabase.instance.client
          .from('app_config')
          .select('value')
          .eq('key', 'min_version')
          .maybeSingle();

      if (result == null) return true; // таблица пуста — ок

      final minVersion = result['value'] as String;
      if (_compare(current, minVersion) >= 0) return true;

      // Получить URL магазина
      final storeResult = await Supabase.instance.client
          .from('app_config')
          .select('key, value')
          .inFilter('key', ['store_url_android', 'store_url_ios'])
          .order('key');

      final storeUrls = {
        for (final row in (storeResult as List))
          row['key'] as String: row['value'] as String,
      };

      if (context.mounted) {
        await _showForceUpdateDialog(
          context,
          minVersion: minVersion,
          storeUrls: storeUrls,
        );
      }
      return false;
    } catch (e) {
      debugPrint('[VersionService] check failed: $e');
      return true; // при ошибке сети не блокируем
    }
  }

  static Future<void> _showForceUpdateDialog(
    BuildContext context, {
    required String minVersion,
    required Map<String, String> storeUrls,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Требуется обновление'),
          content: Text(
            'Версия приложения устарела. '
            'Пожалуйста, обновите до версии $minVersion или новее.',
          ),
          actions: [
            if (storeUrls['store_url_android'] != null)
              TextButton(
                onPressed: () => _openUrl(storeUrls['store_url_android']!),
                child: const Text('Google Play'),
              ),
            if (storeUrls['store_url_ios'] != null)
              TextButton(
                onPressed: () => _openUrl(storeUrls['store_url_ios']!),
                child: const Text('App Store'),
              ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Сравнивает semver строки. Возвращает >=0 если a >= b.
  static int _compare(String a, String b) {
    final av = _parts(a);
    final bv = _parts(b);
    for (int i = 0; i < 3; i++) {
      final diff = av[i] - bv[i];
      if (diff != 0) return diff;
    }
    return 0;
  }

  static List<int> _parts(String v) {
    final parts = v.split('.');
    return List.generate(3, (i) => int.tryParse(parts.elementAtOrNull(i) ?? '0') ?? 0);
  }
}
