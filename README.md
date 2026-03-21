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

- **873 упражнения** из free-exercise-db с русскими названиями, описаниями и GIF-анимацией
- **14 стандартных программ** с метаданными goal/level — онбординг подбирает программу под цель и опыт
- Создание программ тренировок с drag-and-drop, суперсетами, drop-сетами, разминкой
- Активная сессия: вес/повторения/RPE, таймер отдыха, автопрогрессия весов, deload
- История по упражнению: графики веса/объёма/1RM (Эпли), персональный рекорд
- Калькуляторы: 1ПМ (7 формул), блины (4 варианта + схема разминки NSCA/IPF), состав тела (BMI/LBM/FFMI)
- **Аналитика (4 таба):** Обзор · Тренировки · Тело · Инсайты
  - Месячный календарь активности, топ-5 упражнений по объёму, баланс мышц
  - Тренды самочувствия (сон, энергия, стресс), динамика замеров тела
  - Умные инсайты: лучший день для тренировки, тренд объёма, consistency score
- Замеры тела: анатомический силуэт, динамика 15 параметров
- Wellness-дневник: сон, стресс, энергия, качество сна, крепатура
- Фидбек-система: NPS, micro-survey, thumbs up/down, форма обратной связи
- Уведомления: напоминания по расписанию, inactivity reminder, итог недели
- Офлайн-режим: кеш тренировок, очередь сетов (OfflineQueueService)
- Экспорт данных: JSON / CSV

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

### 3. Запуск

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
├── data/           # Стандартные программы (14 шаблонов с goal/level)
├── models/         # Dart-модели с fromJson/toJson
├── providers/      # Riverpod providers (session, settings, connectivity)
├── screens/        # Экраны
│   ├── auth/           # Вход, регистрация, PIN
│   ├── onboarding/     # Онбординг с персонализацией программы
│   ├── home/           # Главная, wellness чек-ин
│   ├── workouts/       # Программы, каталог упражнений
│   ├── workout_session/# Активная сессия, итоги
│   ├── calendar/       # Планирование
│   ├── analytics/      # Статистика (4 таба + инсайты)
│   ├── profile/        # Профиль, замеры тела
│   └── tools/          # Калькуляторы
└── services/       # Слой данных (Supabase + устройство)
supabase/
├── migrations/     # 46 SQL-миграций
├── schema.sql      # Consolidated schema snapshot (таблицы, RLS, триггеры)
├── functions/      # Edge Functions
└── tests/          # RLS тесты (pgTAP)
docs/
├── FEATURES.md     # Полное описание функционала
├── DATABASE.md     # Справочник по схеме БД
├── ANALYTICS.md    # Аналитические возможности и ML
├── MONETIZATION.md # Стратегия монетизации
└── CHANGELOG.md    # История изменений
```

## База данных

46 миграций. Ключевые таблицы: `profiles`, `workouts`, `workout_exercises`, `exercises`, `training_sessions`, `sets`, `body_metrics`, `wellness_logs`, `personal_records`, `user_events`, `feedback`, `app_config`.

Подробнее — в [docs/DATABASE.md](docs/DATABASE.md) и [supabase/schema.sql](supabase/schema.sql).

## Документация

- [docs/FEATURES.md](docs/FEATURES.md) — полное описание функционала
- [docs/DATABASE.md](docs/DATABASE.md) — справочник по схеме БД для аналитиков
- [docs/ANALYTICS.md](docs/ANALYTICS.md) — аналитические возможности и ML
- [docs/MONETIZATION.md](docs/MONETIZATION.md) — стратегия монетизации
- [docs/CHANGELOG.md](docs/CHANGELOG.md) — история изменений
- [releases/](releases/) — тексты для App Store / Google Play / RuStore
