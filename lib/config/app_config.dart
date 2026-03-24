/// Конфигурация приложения.
///
/// Секреты передаются через --dart-define-from-file при сборке:
///   flutter run --dart-define-from-file=.dart_define
///
/// Для локальной разработки скопируй .dart_define.example → .dart_define
/// и заполни значения. Файл .dart_define добавлен в .gitignore.
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// DSN для Sentry. Пустая строка — crash reporting отключён.
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// API-ключ DaData для автодополнения городов (dadata.ru).
  static const String dadataApiKey = String.fromEnvironment('DADATA_API_KEY');

  /// true только в production-сборках (--dart-define=DART_DEFINE_PRODUCTION=true).
  static const bool isProduction = bool.fromEnvironment(
    'DART_DEFINE_PRODUCTION',
    defaultValue: false,
  );
}
