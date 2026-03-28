# SportWAI — Database Reference

> **Для аналитиков.** Полное описание схемы PostgreSQL (Supabase).
> Актуально на: 2026-03-28 · Последняя миграция: `053_energy_end.sql`

---

## Содержание

1. [Архитектура и соглашения](#архитектура-и-соглашения)
2. [Таблицы пользователей и профилей](#таблицы-пользователей-и-профилей)
3. [Тренировочный граф](#тренировочный-граф)
4. [Данные здоровья и тела](#данные-здоровья-и-тела)
5. [Аналитические таблицы](#аналитические-таблицы)
6. [Система обратной связи](#система-обратной-связи)
7. [Инфраструктура](#инфраструктура)
8. [Триггеры и функции](#триггеры-и-функции)
9. [Views](#views)
10. [RLS — политики доступа](#rls--политики-доступа)
11. [Индексы](#индексы)
12. [Полезные аналитические запросы](#полезные-аналитические-запросы)

---

## Архитектура и соглашения

- **Первичные ключи** — `UUID DEFAULT gen_random_uuid()`, кроме `profiles.id` (берётся из `auth.users.id`).
- **Временны́е метки** — `TIMESTAMPTZ` (UTC). Дата тренировки хранится как `DATE` (локальная, без TZ).
- **Мягкое удаление** не используется — все FK настроены на `ON DELETE CASCADE`.
- **RLS включён** на всех таблицах. Пользователь видит только свои данные. Аналитик работает через `service_role`.
- **Миграции** нумеруются последовательно: `NNN_description.sql` в `supabase/migrations/`.
- **Стандартные записи** (упражнения, программы от команды) имеют `is_standard = true` и `user_id = NULL`.

---

## Таблицы пользователей и профилей

### `profiles`

Расширяет `auth.users`. Одна строка на пользователя.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | Совпадает с `auth.users.id` |
| `full_name` | TEXT | Полное имя (устаревш., заменено на first/last) |
| `first_name` | TEXT | Имя |
| `last_name` | TEXT | Фамилия |
| `middle_name` | TEXT | Отчество |
| `nickname` | TEXT | Уникальный логин (lowercase, индекс) |
| `birth_date` | DATE | Дата рождения |
| `gender` | TEXT | `'male'` \| `'female'` \| `'other'` |
| `city` | TEXT | Город |
| `phone` | TEXT | Телефон |
| `email` | TEXT | Email (дублирует auth.users для удобства) |
| `avatar_url` | TEXT | URL аватара в Storage bucket `avatars` |
| `goal` | TEXT | Текущая цель: `'lose_weight'` \| `'gain_muscle'` \| `'maintain'` \| `'endurance'` \| … |
| `goal_metric` | TEXT | Метрика для отслеживания цели, напр. `'weight_kg'` |
| `goal_target` | NUMERIC | Целевое значение метрики |
| `goal_start` | TIMESTAMPTZ | Момент старта цели |
| `goal_targets_json` | JSONB | Расширенные цели: `{"weight_kg": {"target": 75, "start": "2026-01-01T…"}}` |
| `level` | TEXT | Уровень подготовки: `'beginner'` \| `'intermediate'` \| `'advanced'` |
| `weight_kg` | FLOAT | Текущий вес (устаревш., используй `weight_logs`) |
| `height_cm` | FLOAT | Рост (см) |
| `training_start_date` | DATE | Дата начала тренировок в приложении |
| `role` | TEXT | `'user'` \| `'trainer'` \| `'admin'` |
| `is_pro` | BOOLEAN | Быстрый флаг активной подписки (синхронизируется из `subscriptions`) |
| `pro_expires_at` | TIMESTAMPTZ | Дата истечения Pro (NULL = lifetime) |
| `created_at` | TIMESTAMPTZ | Дата регистрации |
| `updated_at` | TIMESTAMPTZ | Авто-обновляется триггером |

**Ограничения:** `nickname = lower(nickname)` (constraint), уникальный индекс по `lower(nickname)`.

---

### `subscriptions`

История подписок. Источник истины о Pro-статусе. `profiles.is_pro` — денормализованный быстрый флаг.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → profiles | |
| `plan` | TEXT | `'monthly'` \| `'annual'` \| `'lifetime'` \| `'trial'` |
| `status` | TEXT | `'active'` \| `'cancelled'` \| `'expired'` \| `'trial'` |
| `store` | TEXT | `'rustore'` \| `'google_play'` \| `'app_store'` \| `'promo'` |
| `store_subscription_id` | TEXT | ID чека магазина для серверной верификации |
| `amount_kopecks` | INTEGER | Сумма в копейках (0 для promo/trial) |
| `trial_ends_at` | TIMESTAMPTZ | |
| `current_period_start` | TIMESTAMPTZ | |
| `current_period_end` | TIMESTAMPTZ | NULL = lifetime |
| `cancelled_at` | TIMESTAMPTZ | |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | |

**Функция** `sync_pro_status(user_id)` — обновляет `profiles.is_pro` по активным подпискам. Вызывается webhook'ом.

---

### `device_tokens`

Токены push-уведомлений (FCM / APNs).

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → profiles | |
| `token` | TEXT | FCM / APNs token |
| `platform` | TEXT | `'ios'` \| `'android'` |
| `app_version` | TEXT | Версия приложения при регистрации токена |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | |

**Уникальность:** `(user_id, token)`.

---

## Тренировочный граф

```
exercises
  └── workout_exercises ──── workouts (programs)
                                 │
                        training_sessions (sessions)
                                 │
                              sets (set records)
                                 │
                        personal_records (auto via trigger)
```

### `exercises`

Каталог упражнений. Стандартные упражнения команды + кастомные пользователя.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `name` | TEXT | Название (английское / русское) |
| `name_ru` | TEXT | Русское название (добавлено в мигр. 041) |
| `category` | TEXT | Группа мышц: `'chest'` \| `'back'` \| `'shoulders'` \| `'arms'` \| `'legs'` \| `'cardio'` \| `'core'` |
| `description` | TEXT | Описание техники |
| `image_url` | TEXT | URL изображения |
| `gif_url` | TEXT | URL анимации техники (Storage bucket `exercise-gifs`) |
| `is_standard` | BOOLEAN | `true` = от команды, `false` = пользовательское |
| `is_bodyweight` | BOOLEAN | Упражнение с весом тела (без отягощений) |
| `user_id` | UUID FK → auth.users | NULL для стандартных; UUID владельца для кастомных |
| `created_at` | TIMESTAMPTZ | |

**RLS:** стандартные видны всем; кастомные — только владельцу.

---

### `workouts`

Программы тренировок. Одна программа = один цикл. Многосекционные программы объединяются по `group_id`.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → profiles | NULL для стандартных программ |
| `name` | TEXT | Название программы (не пустое) |
| `days` | INT[] | Дни цикла с тренировками: `[0,2,4]` (0=Пн…6=Вс) |
| `rest_days` | INT[] | Дни явного отдыха: `[1,3,5,6]` |
| `cycle_weeks` | INT | Длина цикла в неделях (по умолч. 8) |
| `is_standard` | BOOLEAN | Стандартная программа от команды |
| `group_id` | UUID | Объединяет несколько `workouts` в одну многосекционную программу |
| `warmup_minutes` | INT | Длительность разминки |
| `cooldown_minutes` | INT | Длительность заминки |
| `day_times` | JSONB | Время тренировки по дням: `{"0": "07:30", "2": "18:00"}` |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | |

---

### `workout_exercises`

Связь программы и упражнений. Каждая строка — упражнение внутри программы с настройками.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `workout_id` | UUID FK → workouts | |
| `exercise_id` | UUID FK → exercises | |
| `order` | INT | Порядок упражнения в программе |
| `sets` | INT | Плановое количество подходов |
| `reps_range` | TEXT | Диапазон повторений: `'8-12'`, `'5'`, `'AMRAP'` |
| `rest_seconds` | INT | Отдых между подходами (сек) |
| `target_weight` | FLOAT | Целевой вес (кг) |
| `target_rpe` | INT | Целевой RPE 0–10 |
| `duration_minutes` | INT | Для кардио: длительность вместо повторений |
| `superset_group` | INT | Упражнения с одинаковым ненулевым значением — суперсет |
| `is_drop_set` | BOOLEAN | Дроп-сет (снижение веса без отдыха) |
| `created_at` | TIMESTAMPTZ | |

---

### `training_sessions`

Сессия тренировки — плановая или завершённая.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → profiles | |
| `workout_id` | UUID FK → workouts | NULL для one-time sessions |
| `date` | DATE | Дата тренировки (локальная, без TZ) |
| `planned_time` | TIME | Запланированное время начала (для уведомлений) |
| `completed` | BOOLEAN | Тренировка завершена |
| `duration_seconds` | INT | Фактическая длительность (сек) |
| `session_rpe` | SMALLINT | Общая сложность сессии 1–10 |
| `kcal_total` | NUMERIC(8,2) | Суммарные калории за сессию (сумма `sets.kcal_estimated`) |
| `volume_kg` | NUMERIC(10,2) | Суммарный объём = Σ(вес × повторения) только рабочих подходов |
| `streak_at_start` | INT | Серия тренировок на момент создания сессии (снапшот) |
| `energy_end` | DOUBLE PRECISION | Уровень энергии (0–100) в конце сессии — чекпоинт энергетической модели RecSys |
| `notes` | TEXT | Заметки пользователя |
| `created_at` | TIMESTAMPTZ | |

**Паттерн:** `completed = false` + `workout_id = NULL` — одноразовая запланированная сессия в календаре.

---

### `sets`

Запись каждого выполненного подхода. Самая объёмная таблица.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `training_session_id` | UUID FK → training_sessions | |
| `workout_exercise_id` | UUID FK → workout_exercises | |
| `set_number` | INT | Номер подхода в рамках упражнения |
| `weight` | FLOAT | Вес (кг) > 0 если указан |
| `reps` | INT | Выполненных повторений > 0 если указан |
| `reps_target` | INT | Плановое количество повторений (для анализа выполнения) |
| `rpe` | INT | Сложность подхода 0–10 (Rate of Perceived Exertion) |
| `completed` | BOOLEAN | Подход выполнен |
| `is_warmup` | BOOLEAN | Разминочный подход (исключается из объёма) |
| `rest_seconds` | INT | Фактическое время отдыха после подхода |
| `kcal_estimated` | NUMERIC(6,2) | Оценка калорий (формула MET+RPE, считается на клиенте) |
| `performed_at` | TIMESTAMPTZ | Точный момент выполнения (UTC, для ML-анализа) |
| `created_at` | TIMESTAMPTZ | |

**Триггер:** `sets_personal_record_check` — автоматически пишет в `personal_records` при новом максимуме.

---

### `user_favorite_exercises`

Избранные упражнения пользователя.

| Колонка | Тип | Описание |
|---|---|---|
| `user_id` | UUID PK, FK → profiles | |
| `exercise_id` | UUID PK, FK → exercises | |
| `created_at` | TIMESTAMPTZ | |

PK = `(user_id, exercise_id)`.

---

## Данные здоровья и тела

### `body_metrics`

Замеры тела. Одна запись на пользователя в день (UNIQUE constraint).

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → profiles | |
| `date` | DATE | Дата замера |
| `weight_kg` | FLOAT | Вес (кг) |
| `body_fat_pct` | FLOAT | % жира |
| `neck_cm` | FLOAT | Обхват шеи |
| `shoulders_cm` | FLOAT | Обхват плеч |
| `chest_cm` | FLOAT | Обхват груди |
| `waist_cm` | FLOAT | Обхват талии |
| `right_arm_cm` | FLOAT | Правое плечо |
| `left_arm_cm` | FLOAT | Левое плечо |
| `right_forearm_cm` | FLOAT | Правое предплечье |
| `left_forearm_cm` | FLOAT | Левое предплечье |
| `hips_cm` | FLOAT | Обхват бёдер |
| `right_thigh_cm` | FLOAT | Правое бедро |
| `left_thigh_cm` | FLOAT | Левое бедро |
| `right_calf_cm` | FLOAT | Правая икра |
| `left_calf_cm` | FLOAT | Левая икра |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | Авто-обновляется триггером |

---

### `weight_logs`

Журнал взвешиваний — несколько записей в день (в отличие от `body_metrics`).

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → auth.users | |
| `weight_kg` | DECIMAL(5,2) | Вес (кг), точность 0.01 |
| `measured_at` | TIMESTAMPTZ | Момент взвешивания |
| `created_at` | TIMESTAMPTZ | |

---

### `wellness_logs`

Субъективные показатели самочувствия. Одна запись на пользователя в день.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → profiles | |
| `date` | DATE | |
| `sleep_hours` | FLOAT | Часов сна (0–24) |
| `sleep_quality` | SMALLINT | Качество сна 1–5 |
| `stress` | INT | Уровень стресса 1–10 |
| `energy` | INT | Уровень энергии 1–10 |
| `soreness` | SMALLINT | Мышечная боль 1–5 |
| `notes` | TEXT | Свободный комментарий |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | |

---

## Аналитические таблицы

### `user_events`

Append-only поток событий. Основная таблица для продуктовой аналитики.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → profiles | |
| `event` | TEXT | Название события (см. ниже) |
| `props` | JSONB | Метаданные события |
| `created_at` | TIMESTAMPTZ | |

**Каталог событий:**

| Событие | Описание | Ключевые props |
|---|---|---|
| `app_opened` | Открытие приложения | — |
| `screen_view` | Переход на экран | `screen` |
| `screen_leave` | Уход с экрана | `screen`, `duration_s` |
| `workout_started` | Начало тренировки | `workout_id` |
| `workout_completed` | Завершение тренировки | `workout_id`, `duration_s` |
| `workout_abandoned` | Прерывание тренировки | `workout_id` |
| `workout_abandoned_at` | На каком упражнении прервали | `exercise_index` |
| `set_completed` | Выполнен подход | `exercise_id`, `weight`, `reps` |
| `personal_record` | Новый личный рекорд | `exercise_id`, `weight_kg` |
| `rest_skipped` | Пропуск отдыха | `planned_seconds` |
| `workout_created` | Создана программа | — |
| `workout_deleted` | Удалена программа | — |
| `body_metrics_saved` | Сохранены замеры тела | — |
| `onboarding_completed` | Онбординг завершён | — |
| `onboarding_skipped` | Онбординг пропущен | — |
| `program_added` | Добавлена программа | `is_standard` |
| `standard_program_used` | Выбрана стандартная программа | `program_name` |
| `user_logged_in` | Вход | — |
| `user_registered` | Регистрация | — |
| `user_logged_out` | Выход | — |
| `session_scheduled` | Сессия запланирована | — |
| `session_skipped` | Сессия пропущена | — |
| `goal_set` | Установлена цель | `goal` |
| `export_triggered` | Экспорт данных | — |
| `notification_toggled` | Уведомления вкл/выкл | `enabled` |
| `notification_tapped` | Нажатие на уведомление | `notif_type` |
| `pin_setup` | Настройка PIN | — |
| `check_in_saved` | Сохранён check-in | — |
| `session_rpe_logged` | Оценка RPE после сессии | `rpe` |
| `exercise_searched` | Поиск упражнения | `query`, `results_count` |
| `deload_toggled` | Деload вкл/выкл | — |
| `set_added` | Добавлен внеплановый подход | — |
| `exercise_replaced` | Замена упражнения | `from_id`, `to_id` |
| `auto_progress_suggestion_shown` | Показана подсказка прогрессии | — |
| `streak_milestone` | Достигнута серия | `days` |
| `nps_score` | NPS оценка | `score`, `comment?` |
| `feature_request` | Запрос фичи (микро-опрос) | `feature` |
| `screen_feedback` | Thumbs up/down на экране | `screen`, `vote` |
| `churn_reason` | Причина оттока | `reason` |
| `feedback_submitted` | Отправлен feedback | `category` |

---

### `personal_records`

Автоматически пополняется триггером при каждом новом весовом максимуме.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → profiles | |
| `exercise_id` | UUID FK → exercises | |
| `weight_kg` | FLOAT | Рекордный вес > 0 |
| `reps` | INT | Повторения в рекордном подходе |
| `session_id` | UUID FK → training_sessions | Сессия достижения (SET NULL при удалении) |
| `achieved_at` | TIMESTAMPTZ | Момент достижения |

**Источник:** триггер `sets_personal_record_check` на INSERT в `sets`.

---

### `user_goals_history`

История изменений цели пользователя. Автоматически пополняется триггером.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → profiles | |
| `goal` | TEXT | Значение goal на момент изменения |
| `changed_at` | TIMESTAMPTZ | |

**Источник:** триггер `profiles_goal_change` на UPDATE profiles.

---

### `push_notification_logs`

Журнал отправленных уведомлений.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → profiles | |
| `notif_type` | TEXT | `'workout_reminder'` \| `'session'` \| `'inactivity'` \| `'weigh_in'` \| `'rest_day'` \| `'churn'` |
| `notif_id` | INT | OS-идентификатор уведомления |
| `scheduled_for` | TIMESTAMPTZ | NULL для еженедельных повторяющихся |
| `session_id` | UUID FK → training_sessions | Привязанная сессия (если есть) |
| `tapped_at` | TIMESTAMPTZ | Момент нажатия на уведомление |
| `created_at` | TIMESTAMPTZ | |

---

## Система обратной связи

### `feedback`

Все виды обратной связи от пользователей.

| Колонка | Тип | Описание |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → auth.users | |
| `category` | TEXT | `'nps'` \| `'micro_survey'` \| `'screen'` \| `'bug'` \| `'feature'` \| `'general'` |
| `rating` | SMALLINT | NPS: 0–10; thumbs: `1` (up) / `-1` (down) |
| `message` | TEXT | Свободный текст |
| `metadata` | JSONB | Контекст: `{"screen": "calculators"}`, `{"feature": "nutrition"}` и др. |
| `created_at` | TIMESTAMPTZ | |

**Категории:**

| category | Источник |
|---|---|
| `nps` | Оценка 0–10 после 3-й тренировки |
| `micro_survey` | Выбор "чего не хватает" через 7 дней |
| `screen` | Thumbs up/down на экранах (ExerciseHistory, Calculators) |
| `bug` | Форма обратной связи → тип "Ошибка" |
| `feature` | Форма обратной связи → тип "Идея" |
| `general` | Форма обратной связи → тип "Другое" |

---

## Инфраструктура

### `app_config`

Remote-конфигурация приложения. Доступна на чтение без авторизации.

| Колонка | Тип | Описание |
|---|---|---|
| `key` | TEXT PK | |
| `value` | TEXT | |

**Ключи:**

| key | Описание |
|---|---|
| `min_version` | Минимальная версия приложения (force update) |
| `store_url_android` | URL в Google Play |
| `store_url_ios` | URL в App Store |

---

## Триггеры и функции

| Триггер | Таблица | Событие | Функция | Что делает |
|---|---|---|---|---|
| `profiles_updated_at` | profiles | BEFORE UPDATE | `update_updated_at()` | Обновляет `updated_at = NOW()` |
| `workouts_updated_at` | workouts | BEFORE UPDATE | `update_updated_at()` | Обновляет `updated_at = NOW()` |
| `body_metrics_updated_at` | body_metrics | BEFORE UPDATE | `update_updated_at()` | Обновляет `updated_at = NOW()` |
| `wellness_logs_updated_at` | wellness_logs | BEFORE UPDATE | `update_updated_at()` | Обновляет `updated_at = NOW()` |
| `subscriptions_updated_at` | subscriptions | BEFORE UPDATE | `update_updated_at()` | Обновляет `updated_at = NOW()` |
| `sets_personal_record_check` | sets | AFTER INSERT | `fn_check_personal_record()` | Пишет в `personal_records` при новом максимуме |
| `profiles_goal_change` | profiles | AFTER UPDATE | `fn_log_goal_change()` | Пишет в `user_goals_history` при смене goal |

### `fn_check_personal_record()`

```
sets INSERT → completed=true AND weight > 0
  → ищет exercise_id через workout_exercises
  → ищет user_id через training_sessions
  → сравнивает с MAX(weight_kg) в personal_records
  → если новый максимум → INSERT в personal_records
```

### `fn_log_goal_change()`

```
profiles UPDATE → OLD.goal IS DISTINCT FROM NEW.goal AND NEW.goal IS NOT NULL
  → INSERT в user_goals_history (user_id, goal, NOW())
```

### `sync_pro_status(user_id UUID)`

SECURITY DEFINER функция для вызова из webhook. Синхронизирует `profiles.is_pro` из `subscriptions`.

---

## Views

### `weekly_volume`

Объём тренировок по неделям и группам мышц.

```sql
SELECT * FROM weekly_volume WHERE user_id = $1 ORDER BY week_start DESC;
```

**Колонки:** `user_id`, `week_start` (DATE, усечённая до недели), `muscle_group` (category упражнения), `total_sets`, `total_reps`, `total_volume_kg`.

**Фильтр:** только завершённые (`completed = true`) рабочие подходы с весом (не warmup неявно, т.к. `weight IS NOT NULL`).

---

## RLS — политики доступа

| Таблица | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `profiles` | own | own | own | — |
| `exercises` | standard OR own | own (is_standard=false) | own (is_standard=false) | own (is_standard=false) |
| `workouts` | own | own | own | own |
| `workout_exercises` | via workout owner | via workout owner | via workout owner | via workout owner |
| `training_sessions` | own | own | own | own |
| `sets` | via session owner | via session owner | via session owner | via session owner |
| `body_metrics` | own | own | own | own |
| `weight_logs` | own | own | own | own |
| `wellness_logs` | own | own | own | own |
| `user_events` | own | own | — | — |
| `personal_records` | own | own | own | own |
| `user_goals_history` | own | own | own | own |
| `push_notification_logs` | own | own | own | own |
| `device_tokens` | own | own | own | own |
| `subscriptions` | own | — (service_role only) | — | — |
| `user_favorite_exercises` | own | own | — | own |
| `feedback` | own | own | — | — |
| `app_config` | all (incl. anon) | — (service_role only) | — | — |

> "own" = `auth.uid() = user_id` (или `id` для profiles).
> Аналитики используют `service_role` — RLS не применяется.

---

## Индексы

| Индекс | Таблица | Колонки | Условие |
|---|---|---|---|
| `profiles_nickname_unique` | profiles | `lower(nickname)` | `WHERE nickname IS NOT NULL` |
| `workouts_user_id_idx` | workouts | `user_id` | |
| `workouts_group_id_idx` | workouts | `group_id` | `WHERE group_id IS NOT NULL` |
| `workout_exercises_workout_id_idx` | workout_exercises | `workout_id, order` | |
| `training_sessions_user_date_idx` | training_sessions | `user_id, date DESC` | |
| `training_sessions_user_completed_idx` | training_sessions | `user_id, completed` | `WHERE completed = false` |
| `training_sessions_user_kcal_idx` | training_sessions | `user_id, date DESC` | `WHERE kcal_total IS NOT NULL` |
| `sets_session_idx` | sets | `training_session_id` | |
| `sets_workout_exercise_idx` | sets | `workout_exercise_id, training_session_id` | `WHERE completed = true` |
| `body_metrics_user_date_idx` | body_metrics | `user_id, date DESC` | |
| `weight_logs_user_measured_at_idx` | weight_logs | `user_id, measured_at DESC` | |
| `wellness_logs_user_date_idx` | wellness_logs | `user_id, date DESC` | |
| `user_events_user_id_idx` | user_events | `user_id` | |
| `user_events_event_idx` | user_events | `event` | |
| `user_events_created_at_idx` | user_events | `created_at DESC` | |
| `personal_records_user_exercise_idx` | personal_records | `user_id, exercise_id, achieved_at DESC` | |
| `push_notif_logs_user_idx` | push_notification_logs | `user_id, created_at DESC` | |
| `user_goals_history_user_idx` | user_goals_history | `user_id, changed_at DESC` | |
| `device_tokens_user_id_idx` | device_tokens | `user_id` | |
| `feedback_user_id_idx` | feedback | `user_id` | |
| `feedback_category_idx` | feedback | `category` | |
| `feedback_created_at_idx` | feedback | `created_at DESC` | |

---

## Полезные аналитические запросы

### Активность пользователей по неделям
```sql
SELECT
  date_trunc('week', date) AS week,
  COUNT(DISTINCT user_id)  AS active_users,
  COUNT(*)                 AS sessions_completed
FROM training_sessions
WHERE completed = true
GROUP BY 1 ORDER BY 1 DESC;
```

### Среднее время на экране
```sql
SELECT
  props->>'screen'                        AS screen,
  COUNT(*)                                AS visits,
  ROUND(AVG((props->>'duration_s')::int)) AS avg_sec,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (props->>'duration_s')::int)) AS median_sec
FROM user_events
WHERE event = 'screen_leave'
GROUP BY 1
ORDER BY avg_sec DESC;
```

### Воронка "начал → завершил тренировку"
```sql
WITH starts AS (
  SELECT user_id, COUNT(*) AS cnt FROM user_events WHERE event = 'workout_started' GROUP BY 1
),
completes AS (
  SELECT user_id, COUNT(*) AS cnt FROM user_events WHERE event = 'workout_completed' GROUP BY 1
)
SELECT
  s.user_id,
  s.cnt AS started,
  COALESCE(c.cnt, 0) AS completed,
  ROUND(100.0 * COALESCE(c.cnt, 0) / NULLIF(s.cnt, 0), 1) AS completion_pct
FROM starts s LEFT JOIN completes c USING (user_id)
ORDER BY started DESC;
```

### NPS распределение
```sql
SELECT
  rating,
  COUNT(*) AS responses,
  CASE
    WHEN rating >= 9 THEN 'Promoter'
    WHEN rating >= 7 THEN 'Passive'
    ELSE 'Detractor'
  END AS segment
FROM feedback
WHERE category = 'nps'
GROUP BY 1, 3
ORDER BY 1;
```

### Объём по группам мышц за последние 4 недели
```sql
SELECT muscle_group, week_start, total_sets, total_volume_kg
FROM weekly_volume
WHERE user_id = '<user_id>'
  AND week_start >= NOW() - INTERVAL '4 weeks'
ORDER BY week_start DESC, total_volume_kg DESC;
```

### Пользователи с риском оттока (>7 дней без тренировки)
```sql
SELECT
  p.id,
  p.nickname,
  MAX(ts.date) AS last_session,
  NOW()::date - MAX(ts.date) AS days_inactive
FROM profiles p
LEFT JOIN training_sessions ts ON ts.user_id = p.id AND ts.completed = true
GROUP BY 1, 2
HAVING MAX(ts.date) < NOW() - INTERVAL '7 days'
    OR MAX(ts.date) IS NULL
ORDER BY days_inactive DESC NULLS LAST;
```

### Топ упражнений по популярности
```sql
SELECT
  e.name,
  e.category,
  COUNT(DISTINCT s.training_session_id) AS sessions_count,
  COUNT(*)                               AS total_sets
FROM sets s
JOIN workout_exercises we ON we.id = s.workout_exercise_id
JOIN exercises e          ON e.id  = we.exercise_id
WHERE s.completed = true
GROUP BY 1, 2
ORDER BY sessions_count DESC
LIMIT 20;
```
