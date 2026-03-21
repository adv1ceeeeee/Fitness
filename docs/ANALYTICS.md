# Sportify — Аналитические возможности

Описание инфраструктуры для продуктовой аналитики и ML.
Документ адресован аналитикам и data scientists.

---

## Содержание

1. [Обзор](#обзор)
2. [Источники данных](#источники-данных)
3. [Поведенческие события (user_events)](#поведенческие-события-user_events)
4. [Тренировочные данные](#тренировочные-данные)
5. [Данные о пользователе](#данные-о-пользователе)
6. [Фидбек и удовлетворённость](#фидбек-и-удовлетворённость)
7. [Готовые витрины](#готовые-витрины)
8. [Примеры аналитических запросов](#примеры-аналитических-запросов)
9. [ML-возможности](#ml-возможности)
10. [Доступ к данным](#доступ-к-данным)

---

## Обзор

| Параметр | Значение |
|---|---|
| БД | PostgreSQL (Supabase) |
| Основной трекинг | `user_events` — батчевая отправка событий из приложения |
| Тренировочные данные | `training_sessions`, `sets` — полная история каждого подхода |
| Фидбек | `feedback` — NPS, micro-survey, thumbs, форма |
| Готовая витрина | `weekly_volume` VIEW — объём по мышечным группам |
| Обновление данных | Real-time (события отправляются батчами ≤30 сек) |

---

## Источники данных

```
Приложение
   │
   ├─ EventLogger (батч до 20 событий, flush каждые 30 сек)
   │      └─► user_events
   │
   ├─ Тренировочный флоу
   │      └─► training_sessions + sets (каждый подход)
   │
   ├─ Фидбек-система
   │      └─► feedback (NPS, survey, thumbs, free-form)
   │
   └─ Профиль / метрики тела
          └─► profiles, body_metrics, wellness_logs
```

---

## Поведенческие события (user_events)

### Схема таблицы

```sql
CREATE TABLE user_events (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES profiles(id),
  event      TEXT        NOT NULL,
  props      JSONB       NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Каждое событие содержит `props.app_session_id` — уникальный ID сессии запуска приложения (меняется при каждом открытии).

### Полный список событий

#### Жизненный цикл пользователя
| Событие | Props | Описание |
|---|---|---|
| `user_registered` | `goal`, `level` | Первая регистрация |
| `user_logged_in` | — | Вход в аккаунт |
| `user_logged_out` | — | Выход |
| `onboarding_completed` | `goal`, `level`, `gender`, `age` | Завершил онбординг |
| `onboarding_skipped` | — | Пропустил онбординг |
| `app_opened` | `source` (cold/resume/register) | Открытие приложения |
| `pin_setup` | `enabled` | Настройка PIN |

#### Тренировки
| Событие | Props | Описание |
|---|---|---|
| `workout_started` | `workout_id`, `workout_name`, `session_id`, `streak` | Начало тренировки |
| `workout_completed` | `session_id`, `duration_seconds`, `sets_count`, `exercises_count` | Завершена |
| `workout_abandoned` | `session_id`, `duration_seconds` | Брошена |
| `workout_abandoned_at` | `session_id`, `exercise_name`, `set_number`, `completed_sets`, `total_sets` | На каком упражнении бросил |
| `set_completed` | `exercise_id`, `exercise_name`, `weight`, `reps`, `rpe`, `is_warmup`, `is_pr` | Подход выполнен |
| `set_added` | `exercise_id`, `exercise_name`, `set_number`, `session_id` | Добавил подход вне плана |
| `rest_skipped` | `elapsed_seconds` | Пропустил таймер отдыха |
| `session_rpe_logged` | `session_id`, `rpe` | Оценил сложность после тренировки |
| `personal_record` | `exercise_id`, `exercise_name`, `weight`, `reps`, `previous_weight` | Личный рекорд |

#### Прогрессия
| Событие | Props | Описание |
|---|---|---|
| `auto_progress_suggestion_shown` | `exercise_id`, `exercise_name`, `current_weight`, `suggested_weight` | Показали предложение увеличить вес |
| `auto_progress_accepted` | `exercise_id`, `exercise_name`, `old_weight`, `new_weight` | Принял предложение |
| `deload_toggled` | `enabled` | Включил/выключил deload-неделю |
| `streak_milestone` | `days` | Достиг стрика N дней |

#### Программы и упражнения
| Событие | Props | Описание |
|---|---|---|
| `workout_created` | `workout_name` | Создал программу |
| `workout_deleted` | `workout_name` | Удалил программу |
| `program_added` | `program_name` | Добавил программу из каталога |
| `standard_program_used` | `program_name` | Взял стандартную программу |
| `exercise_searched` | `query`, `results_count`, `selected_exercise` | Поиск в каталоге |
| `exercise_replaced` | `old_exercise`, `new_exercise`, `session_id` | Заменил упражнение в сессии |

#### Расписание
| Событие | Props | Описание |
|---|---|---|
| `session_scheduled` | `workout_name`, `date` | Запланировал тренировку |
| `session_deleted` | `session_id` | Удалил сессию из календаря |
| `session_skipped` | `reason` | Пропустил тренировку |

#### Прочее
| Событие | Props | Описание |
|---|---|---|
| `body_metrics_saved` | `fields_count` | Сохранил замеры тела |
| `check_in_saved` | `type` (wellness/weight) | Чек-ин по самочувствию |
| `goal_set` | `goal` | Изменил цель |
| `export_triggered` | `format` (json/csv) | Экспорт данных |
| `notification_toggled` | `enabled` | Вкл/выкл уведомления |
| `calculator_used` | `type` (1rm/bmi/ffmi/lbm/plates) | Использовал калькулятор |

#### Экраны (навигация)
| Событие | Props | Описание |
|---|---|---|
| `screen_view` | `screen` | Переход на экран |
| `screen_leave` | `screen`, `duration_s` | Покинул экран (с временем пребывания) |

#### Фидбек
| Событие | Props | Описание |
|---|---|---|
| `nps_score` | `score` (0–10), `comment` | NPS-оценка |
| `screen_feedback` | `screen`, `vote` (1/-1) | Лайк/дизлайк экрана |
| `churn_reason` | `reason` | Причина отписки/отказа |
| `feature_request` | `feature` | Запрошенная фича |
| `feedback_submitted` | `category` | Отправил форму обратной связи |

---

## Тренировочные данные

### training_sessions
Каждая завершённая тренировка. Ключевые поля:

| Поле | Тип | Описание |
|---|---|---|
| `user_id` | UUID | Пользователь |
| `workout_id` | UUID | Программа |
| `date` | DATE | Дата тренировки |
| `completed` | BOOL | Завершена ли |
| `duration_seconds` | INT | Длительность |
| `session_rpe` | INT | Субъективная нагрузка (1–10) |
| `streak_at_start` | INT | Стрик на момент начала |
| `notes` | TEXT | Заметки пользователя |

### sets
Каждый подход в каждой тренировке — **самый гранулярный уровень**:

| Поле | Тип | Описание |
|---|---|---|
| `training_session_id` | UUID | Сессия |
| `workout_exercise_id` | UUID | Упражнение в программе |
| `set_number` | INT | Номер подхода |
| `weight` | NUMERIC | Вес (кг) |
| `reps` | INT | Повторения |
| `reps_target` | INT | Целевые повторения |
| `rpe` | INT | Нагрузка подхода (1–10) |
| `completed` | BOOL | Выполнен ли |
| `rest_seconds` | INT | Фактический отдых |
| `performed_at` | TIMESTAMPTZ | Точное время выполнения |
| `is_warmup` | BOOL | Разминочный подход |
| `kcal_estimated` | NUMERIC | Расчётные ккал |

---

## Данные о пользователе

### profiles
Демографика и цели:

- `gender` — пол
- `birth_date` → возраст
- `goal` — цель (`lose_weight`, `gain_muscle`, `maintain`, `improve_endurance`, `increase_strength`)
- `level` — уровень (`beginner`, `intermediate`, `advanced`)
- `training_start_date` — когда начал тренироваться
- `weight_kg`, `height_cm` — физические параметры

### body_metrics
Динамика состава тела (15 параметров):
- `weight_kg`, `body_fat_pct`
- Обхваты: грудь, талия, бёдра, плечи, бедро, голень, шея, предплечье, запястье, бицепс (L/R), бедро (L/R)

### wellness_logs
Ежедневный чек-ин (по шкале 1–10):
- `sleep_hours`, `sleep_quality`, `energy`, `stress`, `soreness`

### user_goals_history
История смен целей (автоматически через trigger):
- `goal`, `changed_at` — когда и на что переключился

---

## Фидбек и удовлетворённость

### feedback
```sql
category  TEXT     -- 'nps' | 'micro_survey' | 'screen' | 'bug' | 'feature' | 'general'
rating    SMALLINT -- NPS: 0–10; thumbs: 1 (up) / -1 (down)
message   TEXT     -- свободный текст
metadata  JSONB    -- {screen, question, answer, ...}
```

### push_notification_logs
Эффективность уведомлений:
- `notif_type`, `scheduled_for`, `tapped_at` — конверсия tap rate по типу уведомления

---

## Готовые витрины

### weekly_volume (VIEW)
Объём тренировок по мышечным группам за неделю:

```sql
SELECT * FROM weekly_volume
WHERE user_id = '...'
ORDER BY week_start DESC;

-- Столбцы: user_id, week_start, muscle_group, total_sets, total_reps, total_volume_kg
```

### personal_records
Автоматически обновляется триггером при каждом `INSERT` в `sets`:
```sql
SELECT e.name, pr.weight_kg, pr.reps, pr.achieved_at
FROM personal_records pr
JOIN exercises e ON e.id = pr.exercise_id
WHERE pr.user_id = '...'
ORDER BY pr.achieved_at DESC;
```

---

## Примеры аналитических запросов

### Retention по неделям (когортный анализ)
```sql
WITH first_session AS (
  SELECT user_id, MIN(date) AS cohort_week
  FROM training_sessions
  WHERE completed = true
  GROUP BY user_id
),
activity AS (
  SELECT ts.user_id, fs.cohort_week,
    FLOOR(EXTRACT(EPOCH FROM (ts.date - fs.cohort_week)) / 604800)::int AS week_number
  FROM training_sessions ts
  JOIN first_session fs ON fs.user_id = ts.user_id
  WHERE ts.completed = true
)
SELECT cohort_week, week_number, COUNT(DISTINCT user_id) AS users
FROM activity
GROUP BY cohort_week, week_number
ORDER BY cohort_week, week_number;
```

### Воронка тренировки (где бросают)
```sql
SELECT
  props->>'exercise_name' AS exercise,
  COUNT(*) AS abandoned_count,
  AVG((props->>'completed_sets')::int) AS avg_sets_done
FROM user_events
WHERE event = 'workout_abandoned_at'
GROUP BY exercise
ORDER BY abandoned_count DESC
LIMIT 20;
```

### Среднее время на экране
```sql
SELECT
  props->>'screen' AS screen,
  AVG((props->>'duration_s')::int) AS avg_seconds,
  COUNT(*) AS visits
FROM user_events
WHERE event = 'screen_leave'
  AND (props->>'duration_s')::int > 2
GROUP BY screen
ORDER BY avg_seconds DESC;
```

### DAU / WAU / MAU
```sql
SELECT
  DATE_TRUNC('day', created_at) AS day,
  COUNT(DISTINCT user_id) AS dau
FROM user_events
WHERE event = 'app_opened'
GROUP BY day
ORDER BY day DESC;
```

### NPS-распределение
```sql
SELECT
  (props->>'score')::int AS score,
  COUNT(*) AS count,
  CASE
    WHEN (props->>'score')::int >= 9 THEN 'promoter'
    WHEN (props->>'score')::int >= 7 THEN 'passive'
    ELSE 'detractor'
  END AS category
FROM user_events
WHERE event = 'nps_score'
GROUP BY score
ORDER BY score;
```

### Принятие автопрогрессии весов
```sql
SELECT
  COUNT(*) FILTER (WHERE event = 'auto_progress_suggestion_shown') AS shown,
  COUNT(*) FILTER (WHERE event = 'auto_progress_accepted') AS accepted,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE event = 'auto_progress_accepted')
    / NULLIF(COUNT(*) FILTER (WHERE event = 'auto_progress_suggestion_shown'), 0)
  ) AS acceptance_rate_pct
FROM user_events;
```

### Корреляция wellness → результаты
```sql
SELECT
  w.energy,
  w.soreness,
  AVG(s.weight) AS avg_weight,
  COUNT(s.id) AS sets_done
FROM wellness_logs w
JOIN training_sessions ts ON ts.user_id = w.user_id AND ts.date = w.date
JOIN sets s ON s.training_session_id = ts.id AND s.completed = true
GROUP BY w.energy, w.soreness
ORDER BY w.energy DESC;
```

---

## ML-возможности

### Что можно строить уже сейчас

| Модель | Входные данные | Выход |
|---|---|---|
| **Предсказание оттока** | `app_opened` events, дни без тренировок, `session_rpe`, NPS | Вероятность ухода → триггер уведомления |
| **Рекомендация веса** | История `sets` (вес × повторения), `rpe`, прогрессия за последние 4 недели | Рекомендуемый вес на следующей тренировке |
| **Оптимальный день тренировки** | `wellness_logs` + результаты `sets` | В какой день пользователь тренируется лучше всего |
| **Персонализация программ** | `goal`, `level`, история выполнения упражнений | Программа под пользователя |
| **Прогноз PR** | История личных рекордов + объём тренировок | Когда ожидать следующий рекорд |
| **Аномалии перетренированности** | `soreness`, `energy`, `session_rpe`, объём | Предупреждение о перегрузке |

### Ограничения

- **Холодный старт**: новые пользователи (< 4 тренировок) — данных недостаточно для персонализации
- **Размер выборки**: MVP-база, для обучения сложных моделей нужно 1000+ пользователей с историей 3+ месяцев
- **Отсутствие A/B тестов**: нет механизма деления на группы (можно добавить через `profiles.experiment_group`)

### Подключение внешних BI-инструментов

Supabase поддерживает прямое подключение через **PostgreSQL connection string**:
- **Metabase**, **Redash**, **Superset** — подключаются напрямую к Postgres
- **Python / pandas**: `psycopg2` или `sqlalchemy` → `pd.read_sql()`
- **dbt**: можно настроить как data warehouse поверх Supabase
- **Supabase Edge Functions**: для real-time ML inference (запрос к внешней модели при событии)

```python
# Пример: выгрузка данных для анализа
import pandas as pd
import psycopg2

conn = psycopg2.connect("postgresql://postgres:[password]@db.[ref].supabase.co:5432/postgres")
df = pd.read_sql("SELECT * FROM user_events WHERE event = 'set_completed'", conn)
```
