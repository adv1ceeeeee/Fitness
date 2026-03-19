# Sportify

Мобильное приложение для планирования и отслеживания силовых тренировок (iOS/Android).

## Стек

| Слой | Технология |
|---|---|
| Frontend | Flutter / Dart |
| Состояние | Riverpod (StateNotifierProvider) |
| Маршрутизация | GoRouter |
| Backend | Supabase (Auth, PostgreSQL, Storage, Edge Functions) |
| Аналитика ошибок | Sentry |
| Хранилище на устройстве | FlutterSecureStorage, SharedPreferences |

## Ключевые функции

- **873 упражнения** из free-exercise-db с русскими названиями и GIF-анимацией
- Создание программ тренировок с drag-and-drop, суперсетами, разминкой
- Активная сессия: вес/повторения/RPE, таймер отдыха, личные рекорды
- История по упражнению: графики веса/объёма/1RM (Эпли), персональный рекорд
- Калькуляторы: 1ПМ (7 формул), блины (4 варианта + схема разминки NSCA/IPF), состав тела (BMI/LBM/FFMI)
- Аналитика: стрик, объём за неделю, достижения, баланс мышц, экспорт JSON/CSV
- Замеры тела: анимированный силуэт, динамика параметров
- Уведомления: еженедельные напоминания по расписанию + разовые сессии
- Офлайн-режим: кеш тренировок, очередь событий

## Начало работы

### 1. Flutter

```bash
flutter pub get
```

### 2. Supabase

1. Создайте проект на [supabase.com](https://supabase.com)
2. Выполните все миграции из `supabase/migrations/` в порядке номеров
3. Задайте переменные окружения (см. `.vscode/launch.json`):
   - `SUPABASE_URL` — URL проекта
   - `SUPABASE_ANON_KEY` — anon key
   - `SENTRY_DSN` — DSN Sentry (опционально)

### 3. Edge Function

```bash
supabase functions deploy suggest-city
supabase secrets set DADATA_API_KEY=<ваш_ключ>
```

### 4. Запуск

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

## Тесты

```bash
flutter test
```

381 unit/widget тест. Покрывают: модели, провайдеры, сервисы (auth, pin, wellness, personal records), калькуляторы, MVP-фичи.

## Структура

```
lib/
├── config/         # Тема, роутер, конфиг (env vars)
├── data/           # Стандартные программы (4 шаблона)
├── models/         # Dart-модели с fromJson/toJson
├── providers/      # Riverpod providers (session, settings, connectivity)
├── screens/        # Экраны
│   ├── auth/           # Вход, регистрация, PIN
│   ├── onboarding/     # Онбординг (3 страницы)
│   ├── home/           # Главная, чек-ин, советы
│   ├── workouts/       # Программы, каталог упражнений
│   ├── workout_session/# Активная сессия, итоги
│   ├── calendar/       # Планирование
│   ├── analytics/      # Статистика, история упражнений
│   ├── profile/        # Профиль, замеры тела
│   └── tools/          # Калькуляторы
└── services/       # Слой данных (Supabase + устройство)
supabase/
├── migrations/     # 42 SQL-миграции
├── functions/      # Edge Functions (suggest-city)
└── tests/          # RLS тесты (pgTAP)
```

## База данных

42 миграции. Ключевые таблицы: `profiles`, `workouts`, `workout_exercises`, `exercises`, `training_sessions`, `sets`, `body_metrics`, `wellness_logs`, `personal_records`, `user_events`, `app_config`. Подробнее — в [FEATURES.md](FEATURES.md).

## Документация

- [FEATURES.md](FEATURES.md) — полное описание функционала
- [MONETIZATION.md](MONETIZATION.md) — стратегия монетизации
- [CHANGELOG.md](CHANGELOG.md) — история изменений
- [releases/](releases/) — тексты для App Store / Google Play
