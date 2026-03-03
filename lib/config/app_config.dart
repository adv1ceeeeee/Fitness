/// Конфигурация приложения.
class AppConfig {
  static const String supabaseUrl = 'https://bepukxvkutjqzyhoovyz.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJlcHVreHZrdXRqcXp5aG9vdnl6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIzNTc4NzgsImV4cCI6MjA4NzkzMzg3OH0.jcKlkeDR6tNmlyiB5ae1KVRDHsJHrB6M3U0EdGd0qMY';

  /// API-ключ DaData для автодополнения городов.
  /// Получить бесплатно: https://dadata.ru (10 000 запросов/день)
  /// Вставьте сюда ваш токен после регистрации.
  static const String dadataApiKey = 'YOUR_DADATA_API_KEY';
}
