# Sportify

Мобильное приложение для отслеживания тренировок (iOS/Android).

## Стек

- **Frontend**: Flutter
- **Backend**: Supabase (Auth, Database, Storage)
- **Дизайн**: Тёмная тема, минималистичный стиль

## Начало работы

### 1. Установка Flutter

Убедитесь, что Flutter установлен: https://flutter.dev/docs/get-started/install

### 2. Настройка Supabase

1. Создайте проект на [supabase.com](https://supabase.com)
2. Выполните миграции из `supabase/migrations/` в SQL Editor
3. Скопируйте URL и anon key из Settings → API
4. Вставьте в `lib/config/app_config.dart`:

```dart
static const String supabaseUrl = 'https://xxx.supabase.co';
static const String supabaseAnonKey = 'your-anon-key';
```

### 3. Seed данных

Выполните `supabase/migrations/002_seed_data.sql` для добавления упражнений.

### 4. Запуск

```bash
flutter pub get
flutter run
```

## Структура проекта

```
lib/
├── config/         # Конфиг и тема
├── data/           # Стандартные программы
├── models/         # Модели данных
├── screens/        # Экраны приложения
│   ├── auth/       # Вход, регистрация
│   ├── onboarding/ # Онбординг
│   ├── home/       # Главная
│   ├── workouts/   # Программы тренировок
│   ├── workout_session/ # Выполнение тренировки
│   ├── profile/    # Профиль
│   └── analytics/  # Аналитика
└── services/       # Сервисы (Supabase)
```

## Функции MVP

- ✅ Регистрация и онбординг
- ✅ Создание программ тренировок
- ✅ Стандартные программы
- ✅ Выполнение тренировки (подходы, вес, отдых)
- ✅ Профиль и настройки
- ✅ Базовая аналитика
