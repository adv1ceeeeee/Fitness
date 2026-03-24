/// Конфигурация приложения.
///
/// Секреты передаются через --dart-define при сборке:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ... \
///     --dart-define=SENTRY_DSN=https://...@sentry.io/... \
///     --dart-define=DART_DEFINE_PRODUCTION=true
///
/// В dev-сборках используются дефолтные значения (прод-БД).
/// Для отдельной dev-БД — создайте второй проект в Supabase и передайте его URL.
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bepukxvkutjqzyhoovyz.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJlcHVreHZrdXRqcXp5aG9vdnl6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIzNTc4NzgsImV4cCI6MjA4NzkzMzg3OH0.jcKlkeDR6tNmlyiB5ae1KVRDHsJHrB6M3U0EdGd0qMY',
  );

  /// DSN для Sentry. Пустая строка — crash reporting отключён.
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: 'https://802393f78a9b2147f46a20fac44d00b0@o4511061040037888.ingest.us.sentry.io/4511061041938432',
  );

  /// API-ключ DaData для автодополнения городов (dadata.ru).
  static const String dadataApiKey = String.fromEnvironment(
    'DADATA_API_KEY',
    defaultValue: 'YOUR_DADATA_API_KEY',
  );

  /// true только в production-сборках (--dart-define=DART_DEFINE_PRODUCTION=true).
  static const bool isProduction = bool.fromEnvironment(
    'DART_DEFINE_PRODUCTION',
    defaultValue: false,
  );
}
