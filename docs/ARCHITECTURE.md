# Sportify — Developer Architecture Guide

> Обзорный документ для разработчиков. Остальные тематические доки:
> [FEATURES.md](FEATURES.md) · [DATABASE.md](DATABASE.md) · [RecSys.md](RecSys.md) · [ANALYTICS.md](ANALYTICS.md) · [CHANGELOG.md](CHANGELOG.md) · [BACKLOG.md](BACKLOG.md)

---

## Что такое Sportify

Мобильное приложение для планирования и отслеживания силовых тренировок.
Целевая аудитория — любители, которые тренируются 2–5 раз в неделю.

**Основные возможности:**
- Программы тренировок (циклические / разовые сессии)
- Активная сессия — таймер отдыха, RPE, прогресс-бар
- Рекомендательная система (RecSys) — прогрессия нагрузки, деload, плато
- Аналитика — стрик, объём, личные рекорды, корреляция сна и результатов
- Метрики тела — вес, обхваты, 3D-просмотр силуэта
- Wellness-журнал — сон, стресс, энергия, болезненность мышц

---

## Стек

| Слой | Технология | Версия |
|---|---|---|
| UI | Flutter + Dart | 3.41.x / SDK ^3.5.0 |
| State | flutter_riverpod (StateNotifier) | ^2.5.1 |
| Navigation | go_router (StatefulShellRoute) | ^14.2.0 |
| Backend | Supabase (Postgres + Auth + RLS) | supabase_flutter ^2.8.0 |
| Push | Firebase Messaging | ^15.1.3 |
| Local notifs | flutter_local_notifications | ^18.0.1 |
| Crash reporting | Sentry | sentry_flutter ^8.13.2 |
| Charts | fl_chart | ^0.69.0 |
| Calendar | table_calendar | ^3.1.0 |
| Local storage | SharedPreferences + flutter_secure_storage | ^2.2.2 / ^9.2.2 |
| Offline queue | собственный OfflineQueueService | — |
| Cache | собственный AppCache (stale-while-revalidate) | — |
| Calorie model | MET-based estimateSetKcal | — |
| Tests | flutter_test | 514 тестов |
| CI | GitHub Actions | `.github/workflows/ci.yml` |

---

## Структура проекта

```
lib/
├── config/
│   ├── app_config.dart       # Секреты через String.fromEnvironment
│   └── theme.dart            # AppColors, AppTheme (dark/light), ResponsiveContext
├── data/
│   └── standard_programs.dart  # 14 стандартных программ (встроены в бинарник)
├── models/                   # Immutable data classes с fromJson/toJson
│   ├── exercise.dart
│   ├── profile.dart
│   ├── set_record.dart
│   ├── training_session.dart
│   ├── workout.dart
│   └── workout_exercise.dart
├── providers/                # Riverpod providers
│   ├── active_session_provider.dart  # sessionId + startTime текущей сессии
│   ├── connectivity_provider.dart
│   └── settings_provider.dart        # themeMode, useKg, useCm, dumbbell increment
├── screens/
│   ├── analytics/
│   ├── auth/
│   ├── calendar/
│   ├── home/
│   ├── onboarding/
│   ├── profile/
│   ├── workouts/
│   ├── workout_session/
│   └── main_shell.dart       # Bottom-nav shell + FAB «Начать тренировку»
├── services/
│   └── (27 сервисов, см. ниже)
├── utils/
│   └── retry.dart
├── widgets/
│   ├── avatar_widget.dart
│   ├── pin_pad.dart
│   └── skeleton.dart
├── main.dart
└── router.dart
supabase/
├── migrations/               # 053 миграций, нумерация 001–054+
└── tests/
    └── rls_policies.sql      # pgTAP RLS-тесты (нужен Docker)
test/
├── models/
├── providers/
├── services/
├── features/
└── widget_test.dart
docs/
├── ARCHITECTURE.md           # этот файл
├── FEATURES.md
├── DATABASE.md
├── RecSys.md
├── ANALYTICS.md
├── MONETIZATION.md
├── CHANGELOG.md
└── BACKLOG.md
```

---

## Навигация (router.dart)

GoRouter с `StatefulShellRoute` — 4 постоянные вкладки (состояние сохраняется при переключении):

| Вкладка | Корневой маршрут | Дочерние маршруты |
|---|---|---|
| Главная | `/home` | `/calendar`, `/today` |
| Программы | `/workouts` | `/workouts/create`, `/workouts/:id/exercises` |
| Аналитика | `/analytics` | `/body-metrics`, `/history`, `/records`, `/calculators`, `/exercise/:id/history` |
| Профиль | `/profile` | `/feedback` |

**Отдельные маршруты (вне табов):**
- `/session/:sessionId` — активная тренировка (`WorkoutSessionScreen`)
- `/session-summary` — итоги сессии (`SessionSummaryScreen`)
- Онбординг: `/onboarding`, `/onboarding-check`, `/pin-setup`, `/pin-login`
- Авторизация: `/` (welcome), `/login`, `/register`

**GoRouter observer** автоматически логирует `screen_view` события с длительностью просмотра через `EventLogger`.

---

## Секреты и конфигурация

Секреты передаются через `--dart-define` при сборке. **В коде нет хардкода** — только `String.fromEnvironment(...)` с дефолтными значениями для dev-сборки.

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=SENTRY_DSN=https://...@sentry.io/... \
  --dart-define=DART_DEFINE_PRODUCTION=true
```

В `ci.yml` секреты приходят из GitHub Secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SENTRY_DSN`.

Для VSCode добавь `.vscode/launch.json`:
```json
{
  "configurations": [{
    "name": "Dev",
    "request": "launch",
    "type": "dart",
    "args": [
      "--dart-define=SUPABASE_URL=...",
      "--dart-define=SUPABASE_ANON_KEY=..."
    ]
  }]
}
```

---

## Запуск

```bash
flutter pub get
flutter test            # 514 тестов — должны все проходить перед коммитом
flutter run             # дефолтная dev-конфигурация (Supabase прод-БД)
```

---

## Сервисы (lib/services/)

### Данные и аналитика

| Сервис | Что делает |
|---|---|
| `training_service.dart` | Сессии, подходы (`saveSet` с `repsTarget`, `kcalEstimated`), `createSession` (снимок стрика) |
| `workout_service.dart` | CRUD для программ и упражнений в программе |
| `exercise_service.dart` | Каталог упражнений, поиск, пагинация |
| `analytics_service.dart` | Всё что считается: стрик, объём, личные рекорды, энергия, баланс мышц, корреляция сна |
| `wellness_service.dart` | Upsert `wellness_logs` (сон, стресс, энергия, качество сна, болезненность) |
| `body_metrics_service.dart` | История метрик тела (вес, обхваты, % жира) |
| `profile_service.dart` | Профиль пользователя, цель, параметры тела |
| `achievement_service.dart` | Достижения (вычисляются из данных аналитики) |

### RecSys и UserState

| Сервис | Что делает |
|---|---|
| `recsys_service.dart` | Алгоритмы: `evaluateProgression`, `evaluateWellness`, `evaluateMuscleBalance`, `evaluateDeload`, `evaluatePlateau`, `evaluateWellnessCorrelation`, `computeEnergyStart` |
| `user_state_service.dart` | **Единый источник истины для RecSys.** `UserStateService.computeUserState()` запускает 8 sub-calls параллельно, вычисляет все рекомендации из одного снапшота. Кеш 30 мин. |

> **Важно:** `UserState` — это единственное место, из которого читают `energyState`, `wellnessRec`, `userGoal`, `rpeCalibrationOffset`. Никакой прямой вызов `getEnergyState()` снаружи `UserStateService`.

### Инфраструктура

| Сервис | Что делает |
|---|---|
| `app_cache.dart` | Stale-while-revalidate кеш над SharedPreferences. `AppCache.get(key, ttl, fetch, encode, decode)`. При ошибке фонового рефетча — возвращает устаревшее значение, не крашится. |
| `offline_queue_service.dart` | При ошибке `saveSet` — кладёт в очередь и ретраит при восстановлении сети |
| `event_logger.dart` | Батчевая запись аналитических событий в `user_events`. Flush при `onPause`/`onDetach`. |
| `local_storage.dart` | `AppStorage` — типизированный singleton над SharedPreferences (настройки, onboarding флаги, черновики сессий) |
| `notification_service.dart` | Локальные уведомления + логирование в `push_notification_logs`. Поддерживает tap-handler (переход к сессии). |
| `version_service.dart` | Проверка минимальной версии из `app_config` → undismissable диалог обновления |
| `pin_service.dart` | PIN-аутентификация через `flutter_secure_storage` |
| `auth_service.dart` | Тонкая обёртка над Supabase Auth |

---

## Ключевые паттерны

### AppCache (stale-while-revalidate)

```dart
return AppCache.get<MyType>(
  key: 'my_key:$userId',
  ttl: const Duration(minutes: 30),
  fetch: () => _fetchFromNetwork(),
  encode: (v) => jsonEncode(v.toJson()),
  decode: (raw) => raw == null ? defaultValue : MyType.fromJson(jsonDecode(raw)),
);
```

- Свежий кеш → возвращает немедленно, без сети
- Устаревший кеш → возвращает немедленно + фоновый рефетч
- Промах (cache miss) → ждёт сеть, кеширует
- Ошибка фонового рефетча → логирует, не крашится
- Инвалидация: `AppCache.invalidate(key)` или `AppCache.invalidatePrefix('prefix:')` — вызывается после записи данных

### RecSys / UserState

Все рекомендации всегда исходят из одного `UserState`, вычисленного единожды:

```
UserStateService.computeUserState()
  └─ Future.wait (8 параллельных вызовов, каждый с .catchError)
       ├─ WellnessService.getTodayLog()
       ├─ AnalyticsService.getEnergyState()   ← wellness-cap встроен
       ├─ ProfileService.getProfile()
       ├─ AnalyticsService.getRpeCalibrationOffset()
       ├─ AnalyticsService.getMuscleGroupBalance()
       ├─ AnalyticsService.getDeloadMetrics()
       ├─ AnalyticsService.getStagnantExercises()
       └─ AnalyticsService.getWellnessPerformanceCorrelation()
  └─ evaluateWellness / evaluateMuscleBalance / evaluatePlateau / ...
  └─ → UserState (cached 30 min under 'user_state:$userId')
```

Инвалидация `user_state:` происходит в:
- `WellnessService.saveTodayLog()` — после сохранения wellness
- `AnalyticsService.invalidateStatsCache()` — после завершения тренировки

### Модель энергии

`getEnergyState()` вычисляет `reserve` (0–100%):
1. Берёт `energy_end` из последней завершённой сессии
2. Применяет экспоненциальное восстановление за прошедшие часы (`computeEnergyStart`)
3. Применяет cap: `wellness.energy * 10` — чтобы "Пик (100%)" не показывался при низкой субъективной энергии

`EnergyState.bucket` (1=пик, 10=истощение) используется в `evaluateProgression` для корректировки порогов.

### Подходы и калории

`TrainingService.saveSet()` сохраняет `kcal_estimated` — вычисляется через `CalorieService.estimateSetKcal(category, reps, rpe)` (MET-based).

В `SessionSummaryScreen` при редактировании подхода `kcal_estimated` пересчитывается в `_apply()` и `_save()`, затем прокидывается в `TrainingService.updateSet()`.

### Офлайн-queue

```
TrainingService.saveSet()
  ├─ success → готово
  └─ error   → OfflineQueueService.enqueue(setData)
                 └─ на восстановлении сети → ретрай
```

### Обработка ошибок

- Сервисы: `try/catch`, `debugPrint`, никогда не крашат UI; `if (userId == null) return`
- `EventLogger` / `NotificationService._logScheduled`: fire-and-forget, ошибки молча игнорируются
- `UserStateService._fetch`: каждый из 8 sub-calls обёрнут в `.catchError` — один сломанный запрос не убивает весь `UserState`
- `AppCache`: ошибка фонового рефетча логируется в debug-режиме, не крашится

---

## База данных

Supabase/Postgres. 053 миграции в `supabase/migrations/`. Следующий номер: **054**.

Именование файлов: `NNN_topic.sql`, трёхзначный номер.

```bash
# Применить новую миграцию
supabase db push   # или вручную через psql/Dashboard
```

Ключевые таблицы:

| Таблица | Назначение |
|---|---|
| `profiles` | Профиль: goal, level, gender, birth_date, weight_kg, height_cm |
| `workouts` | Программы тренировок (дни, цикл, is_standard) |
| `workout_exercises` | Упражнения в программе: порядок, подходы, диапазон повторений |
| `exercises` | Каталог упражнений (name, name_ru, category, gif_url, equipment_type) |
| `training_sessions` | Сессии: date, completed, duration_seconds, session_rpe, streak_at_start, energy_end |
| `sets` | Подходы: weight, reps, reps_target, rpe, kcal_estimated, performed_at |
| `wellness_logs` | Дневник самочувствия: sleep_hours, stress 1–10, energy 1–10, sleep_quality 1–5, soreness 1–5 |
| `body_metrics` | Замеры тела: weight_kg, body_fat_pct + 13 обхватов |
| `personal_records` | Авто-триггер `fn_check_personal_record` на INSERT в sets |
| `user_goals_history` | Авто-триггер `fn_log_goal_change` на UPDATE profiles.goal |
| `weekly_volume` | VIEW: объём по группам мышц за неделю |
| `user_events` | Аналитические события (EventLogger) |
| `push_notification_logs` | История уведомлений + tap-события |
| `app_config` | Конфиг (min_version, store_url_android/ios) |
| `device_tokens` | FCM-токены |

Полная схема: [DATABASE.md](DATABASE.md)
RLS-политики: `supabase/tests/rls_policies.sql` (pgTAP, требует Docker)

---

## Тестирование

```
test/
├── models/            # exercise, profile, set_record, training_session, workout, workout_exercise
├── providers/         # active_session_provider, settings_provider
├── services/          # auth_service, calorie/exercise_params, pin_service,
│                        wellness_service, personal_records_dedup, recsys_wellness
├── features/          # mvp_features
└── widget_test.dart
```

```bash
flutter test            # все 514 тестов
flutter test --coverage # + lcov report
```

**Правила:**
- Перед каждым коммитом — `flutter test` (все должны проходить)
- `SharedPreferences.resetStatic()` перед `setMockInitialValues` в тестах
- RLS-тесты запускаются отдельно через pgTAP + Docker

---

## CI/CD

Файл: `.github/workflows/ci.yml`

```
push/PR → main, develop
  └─ Analyze & Test
       ├─ flutter analyze --fatal-infos
       ├─ flutter test --coverage
       └─ Upload coverage → Codecov

push → main (только)
  └─ Build Android AAB
       ├─ flutter build appbundle --release --obfuscate
       ├─ Upload artifact (7 дней)
       └─ Upload debug symbols (30 дней)
```

Сборка iOS — вручную через Xcode / App Store Connect (нет раннера macOS в CI).

---

## Версионирование

Формат: `MAJOR.MINOR.PATCH+BUILD` в `pubspec.yaml`.

Текущая версия: **1.9.0+24**

Подробные правила и процесс релиза: [releases/README.md](../releases/README.md)

Стор-тексты: `releases/vX.Y.Z/ru.txt` + `en.txt`
- App Store: ≤ 4000 символов
- Google Play: ≤ 500 символов

---

## EventLogger — события аналитики

Все события пишутся в `user_events` через `EventLogger`. Список:

```
app_opened, screen_view (авто через GoRouter), workout_started, workout_completed,
workout_abandoned, workout_abandoned_at, set_completed, personal_record,
rest_skipped, workout_created, workout_deleted, set_added, exercise_replaced,
body_metrics_saved, check_in_saved, session_rpe_logged, goal_set,
program_added, standard_program_used, auto_progress_suggestion_shown,
exercise_searched, export_triggered, notification_toggled, notification_tapped,
deload_toggled, pin_setup, onboarding_completed, onboarding_skipped,
user_logged_in, user_registered, user_logged_out, session_scheduled, session_skipped
```

---

## Локальное хранилище (AppStorage)

`lib/services/local_storage.dart` — типизированный singleton над SharedPreferences:

| Ключ | Тип | Назначение |
|---|---|---|
| `dumbbell_increment` | double | Шаг гантельного ряда (2.5, 4, 5 кг) |
| `use_kg` | bool | Единицы веса |
| `use_cm` | bool | Единицы длины |
| `theme_mode` | int | 0=system, 1=light, 2=dark |
| `notifications_enabled` | bool | — |
| `onboarding_done` | bool | — |
| `session_ex_idx_{sessionId}` | int | Последний индекс упражнения (для восстановления) |
| `draft_{sessionId}_{exIdx}` | String | JSON-черновик текущего подхода |

---

## Платформы

| Платформа | Статус |
|---|---|
| Android | Production |
| iOS | Production |
| Windows | Dev/тестирование (window_manager, фиксированный размер 500×850) |
| Web / macOS / Linux | Не поддерживаются |

Особенности Windows:
- `webview_flutter` не поддерживается → 3D-просмотр тела показывает плейсхолдер
- FCM/Firebase пропускается (`_isMobilePlatform` guard)
- `File` API доступен (shelf + shelf_static для локального HTTP-сервера)
