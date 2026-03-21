-- ============================================================
-- supabase/schema.sql
--
-- DOCUMENTATION ONLY — do NOT apply via CLI.
-- This file is the consolidated final-state schema derived from
-- migrations 001–046. It reflects all ALTER TABLE changes folded
-- in, with duplicates resolved to the latest version.
--
-- To make schema changes, add a new numbered migration in
-- supabase/migrations/ and update this file accordingly.
-- ============================================================


-- ============================================================
-- SECTION 1: TABLES
-- ============================================================


-- ── profiles ──────────────────────────────────────────────────────────────────
-- Extends auth.users. One row per registered user.
-- Created automatically by the handle_new_user() trigger on auth.users INSERT.
-- age column was dropped in 037 (use birth_date + client-side calculation).

CREATE TABLE IF NOT EXISTS public.profiles (
  id                  UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Name fields
  full_name           TEXT,
  first_name          TEXT,
  last_name           TEXT,
  middle_name         TEXT,
  nickname            TEXT        CONSTRAINT profiles_nickname_lowercase CHECK (nickname = lower(nickname)),

  -- Personal info
  birth_date          DATE,
  gender              TEXT,
  city                TEXT,
  phone               TEXT,
  email               TEXT,
  avatar_url          TEXT,

  -- Training profile
  weight              FLOAT,      -- legacy; prefer body_metrics for tracking
  goal                TEXT,
  level               TEXT,
  training_start_date DATE,

  -- Subscription / role
  role                TEXT        NOT NULL DEFAULT 'user',  -- 'user' | 'trainer' | 'admin'
  is_pro              BOOLEAN     NOT NULL DEFAULT false,
  pro_expires_at      TIMESTAMPTZ,

  -- Body-progress goal (legacy scalar fields)
  goal_metric         TEXT        NOT NULL DEFAULT 'weight_kg',
  goal_target         NUMERIC,
  goal_start          TIMESTAMPTZ,

  -- Per-metric goal targets: {"weight_kg": {"target": 80, "start": "2026-01-01T00:00:00Z"}}
  goal_targets_json   JSONB       DEFAULT '{}',

  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Unique lowercase nickname index
CREATE UNIQUE INDEX IF NOT EXISTS profiles_nickname_unique
  ON public.profiles (lower(nickname))
  WHERE nickname IS NOT NULL;


-- ── exercises ─────────────────────────────────────────────────────────────────
-- Master catalog of exercises. Standard exercises have is_standard = true and
-- user_id = NULL. User-created exercises have is_standard = false and user_id set.
-- Soft-deleted exercises have deleted_at set; they are hidden via RLS.

CREATE TABLE IF NOT EXISTS public.exercises (
  id             UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT    NOT NULL,
  name_ru        TEXT,                     -- Russian display name (041)
  category       TEXT    NOT NULL,         -- 'chest' | 'back' | 'shoulders' | 'arms' | 'legs' | 'cardio' | 'core'
  description    TEXT,                     -- English description
  description_ru TEXT,                     -- Russian description (044)
  image_url      TEXT,                     -- legacy image (use gif_url)
  gif_url        TEXT,                     -- animated GIF in exercise-gifs bucket (040)
  is_standard    BOOLEAN DEFAULT true,
  is_bodyweight  BOOLEAN DEFAULT false,
  muscle_groups  TEXT[]  DEFAULT '{}',     -- granular muscle targeting (037)
  user_id        UUID    REFERENCES public.profiles(id) ON DELETE CASCADE,  -- NULL for standard
  deleted_at     TIMESTAMPTZ DEFAULT NULL, -- soft-delete (037)
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

-- GIN index for muscle-group filtering
CREATE INDEX IF NOT EXISTS exercises_muscle_groups_gin_idx
  ON public.exercises USING GIN (muscle_groups);

-- Partial index for fast active-exercise lookups
CREATE INDEX IF NOT EXISTS exercises_active_idx
  ON public.exercises (deleted_at)
  WHERE deleted_at IS NULL;


-- ── workouts ──────────────────────────────────────────────────────────────────
-- Training programs. A user may have multiple workouts, optionally grouped
-- via group_id (multi-section programs). Soft-deleted via deleted_at.
-- Marketplace columns (is_public, price_kopecks, etc.) exist for future use.

CREATE TABLE IF NOT EXISTS public.workouts (
  id               UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID      REFERENCES public.profiles(id) ON DELETE CASCADE,
  name             TEXT      NOT NULL CONSTRAINT workouts_name_not_blank CHECK (length(trim(name)) > 0),

  -- Schedule
  days             INT[]     DEFAULT '{}' CONSTRAINT workouts_days_valid CHECK (days <@ ARRAY[0,1,2,3,4,5,6]),
  rest_days        INT[]     NOT NULL DEFAULT '{}' CONSTRAINT workouts_rest_days_valid CHECK (rest_days <@ ARRAY[0,1,2,3,4,5,6]),
  day_times        JSONB     NOT NULL DEFAULT '{}',  -- {"0": "07:30", "2": "09:00"}

  -- Program metadata
  cycle_weeks      INT       DEFAULT 8,
  warmup_minutes   INTEGER   NOT NULL DEFAULT 0,
  cooldown_minutes INTEGER   NOT NULL DEFAULT 0,
  group_id         UUID,     -- links workout rows in a multi-section program

  -- Marketplace / sharing (future)
  is_standard      BOOLEAN   DEFAULT false,
  is_public        BOOLEAN   NOT NULL DEFAULT false,
  price_kopecks    INTEGER   NOT NULL DEFAULT 0 CHECK (price_kopecks >= 0),
  trainer_id       UUID      REFERENCES public.profiles(id) ON DELETE SET NULL,
  cover_image_url  TEXT,
  description      TEXT,
  downloads_count  INTEGER   NOT NULL DEFAULT 0,

  -- Soft delete
  deleted_at       TIMESTAMPTZ DEFAULT NULL,

  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS workouts_user_id_idx
  ON public.workouts (user_id);

CREATE INDEX IF NOT EXISTS workouts_group_id_idx
  ON public.workouts (group_id)
  WHERE group_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS workouts_user_active_idx
  ON public.workouts (user_id, deleted_at)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS workouts_marketplace_idx
  ON public.workouts (is_public, downloads_count DESC)
  WHERE is_public = true;

CREATE INDEX IF NOT EXISTS workouts_trainer_id_idx
  ON public.workouts (trainer_id)
  WHERE trainer_id IS NOT NULL;


-- ── workout_exercises ─────────────────────────────────────────────────────────
-- Junction table linking exercises to workouts, with per-exercise settings.

CREATE TABLE IF NOT EXISTS public.workout_exercises (
  id               UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  workout_id       UUID    REFERENCES public.workouts(id) ON DELETE CASCADE,
  exercise_id      UUID    REFERENCES public.exercises(id) ON DELETE CASCADE,
  "order"          INT     DEFAULT 0,
  sets             INT     DEFAULT 3,
  reps_range       TEXT    DEFAULT '8-12',
  rest_seconds     INT     DEFAULT 90,
  target_weight    FLOAT,
  target_rpe       INT     CHECK (target_rpe >= 0 AND target_rpe <= 10),
  duration_minutes INTEGER,             -- for cardio exercises
  superset_group   INTEGER,            -- exercises sharing the same non-null value form a superset
  is_drop_set      BOOLEAN NOT NULL DEFAULT false,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS workout_exercises_workout_id_idx
  ON public.workout_exercises (workout_id, "order");


-- ── training_sessions ─────────────────────────────────────────────────────────
-- One row per workout session (planned or completed).
-- workout_id becomes NULL if the linked workout is deleted (history preserved).

CREATE TABLE IF NOT EXISTS public.training_sessions (
  id               UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID      REFERENCES public.profiles(id) ON DELETE CASCADE,
  workout_id       UUID      REFERENCES public.workouts(id) ON DELETE SET NULL,
  date             DATE      NOT NULL,
  completed        BOOLEAN   DEFAULT false,
  notes            TEXT,

  -- Session stats
  duration_seconds INT,
  kcal_total       NUMERIC(8,2),
  volume_kg        NUMERIC(10,2),
  session_rpe      SMALLINT  CHECK (session_rpe BETWEEN 1 AND 10),
  streak_at_start  INT,      -- consecutive workout days snapshotted at session creation

  -- Scheduling
  planned_time     TIME,     -- for "notify N minutes before" mode

  created_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS training_sessions_user_date_idx
  ON public.training_sessions (user_id, date DESC);

CREATE INDEX IF NOT EXISTS training_sessions_user_completed_idx
  ON public.training_sessions (user_id, completed)
  WHERE completed = false;

CREATE INDEX IF NOT EXISTS training_sessions_user_kcal_idx
  ON public.training_sessions (user_id, date DESC)
  WHERE kcal_total IS NOT NULL;

CREATE INDEX IF NOT EXISTS training_sessions_user_date_completed_idx
  ON public.training_sessions (user_id, date DESC, completed)
  WHERE completed = true;


-- ── sets ──────────────────────────────────────────────────────────────────────
-- Individual set records within a training session.
-- workout_exercise_id becomes NULL if the exercise template is deleted (history preserved).

CREATE TABLE IF NOT EXISTS public.sets (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  training_session_id   UUID        REFERENCES public.training_sessions(id) ON DELETE CASCADE,
  workout_exercise_id   UUID        REFERENCES public.workout_exercises(id) ON DELETE SET NULL,
  set_number            INT         NOT NULL,
  weight                FLOAT       CONSTRAINT sets_weight_positive CHECK (weight IS NULL OR weight > 0),
  reps                  INT         CONSTRAINT sets_reps_positive   CHECK (reps IS NULL OR reps > 0),
  reps_target           INT,        -- planned reps; compare with reps to detect failure
  rpe                   INTEGER     CHECK (rpe >= 0 AND rpe <= 10),
  completed             BOOLEAN     DEFAULT false,
  is_warmup             BOOLEAN     NOT NULL DEFAULT false,
  rest_seconds          INT,
  kcal_estimated        NUMERIC(6,2),
  performed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at            TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS sets_session_idx
  ON public.sets (training_session_id);

CREATE INDEX IF NOT EXISTS sets_workout_exercise_idx
  ON public.sets (workout_exercise_id, training_session_id)
  WHERE completed = true;

CREATE INDEX IF NOT EXISTS sets_session_completed_idx
  ON public.sets (training_session_id, completed, is_warmup)
  WHERE completed = true AND is_warmup = false;


-- ── body_metrics ──────────────────────────────────────────────────────────────
-- Body composition snapshots. One row per user per date (UNIQUE constraint).
-- All circumference columns in cm.

CREATE TABLE IF NOT EXISTS public.body_metrics (
  id               UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID  NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  date             DATE  NOT NULL,

  weight_kg        FLOAT CONSTRAINT body_metrics_weight_positive CHECK (weight_kg IS NULL OR weight_kg > 0),
  body_fat_pct     FLOAT,

  -- Circumferences (cm)
  neck_cm          FLOAT,
  shoulders_cm     FLOAT,
  chest_cm         FLOAT,
  waist_cm         FLOAT,
  right_arm_cm     FLOAT,
  left_arm_cm      FLOAT,
  right_forearm_cm FLOAT,
  left_forearm_cm  FLOAT,
  hips_cm          FLOAT,
  right_thigh_cm   FLOAT,
  left_thigh_cm    FLOAT,
  right_calf_cm    FLOAT,
  left_calf_cm     FLOAT,

  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (user_id, date)
);

CREATE INDEX IF NOT EXISTS body_metrics_user_date_idx
  ON public.body_metrics (user_id, date DESC);


-- ── wellness_logs ─────────────────────────────────────────────────────────────
-- Daily subjective wellness check-in. One row per user per date.

CREATE TABLE IF NOT EXISTS public.wellness_logs (
  id            UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID     NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  date          DATE     NOT NULL,

  sleep_hours   FLOAT    CHECK (sleep_hours >= 0 AND sleep_hours <= 24),
  stress        INT      CHECK (stress >= 1 AND stress <= 10),
  energy        INT      CHECK (energy >= 1 AND energy <= 10),
  sleep_quality SMALLINT CHECK (sleep_quality BETWEEN 1 AND 5),
  soreness      SMALLINT CHECK (soreness BETWEEN 1 AND 5),
  notes         TEXT,

  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (user_id, date)
);

CREATE INDEX IF NOT EXISTS wellness_logs_user_date_idx
  ON public.wellness_logs (user_id, date DESC);


-- ── user_events ───────────────────────────────────────────────────────────────
-- Append-only event stream for analytics and funnel tracking.
-- Users can INSERT their own events; SELECT is available to the user
-- (service_role is used for cross-user analytics).

CREATE TABLE IF NOT EXISTS public.user_events (
  id         UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID  NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event      TEXT  NOT NULL,
  props      JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS user_events_user_id_idx
  ON public.user_events (user_id);

CREATE INDEX IF NOT EXISTS user_events_event_idx
  ON public.user_events (event);

CREATE INDEX IF NOT EXISTS user_events_created_at_idx
  ON public.user_events (created_at DESC);

CREATE INDEX IF NOT EXISTS user_events_user_event_time_idx
  ON public.user_events (user_id, event, created_at DESC);


-- ── weight_logs ───────────────────────────────────────────────────────────────
-- Multiple timestamped weigh-ins per day per user (granular weight tracking).

CREATE TABLE IF NOT EXISTS public.weight_logs (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID         NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  weight_kg   DECIMAL(5,2) NOT NULL,
  measured_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS weight_logs_user_measured_at_idx
  ON public.weight_logs (user_id, measured_at DESC);


-- ── subscriptions ─────────────────────────────────────────────────────────────
-- One row per subscription period. Multiple historical rows per user allowed.
-- Source of truth for Pro status; profiles.is_pro is a fast cache updated via
-- sync_pro_status().

CREATE TABLE IF NOT EXISTS public.subscriptions (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  plan                  TEXT        NOT NULL,       -- 'monthly' | 'annual' | 'lifetime' | 'trial'
  status                TEXT        NOT NULL DEFAULT 'active',  -- 'active' | 'cancelled' | 'expired' | 'trial'
  store                 TEXT        NOT NULL,       -- 'rustore' | 'google_play' | 'app_store' | 'promo'
  store_subscription_id TEXT,                       -- store receipt ID for server-side verification
  amount_kopecks        INTEGER     NOT NULL DEFAULT 0,
  trial_ends_at         TIMESTAMPTZ,
  current_period_start  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  current_period_end    TIMESTAMPTZ,               -- NULL = lifetime
  cancelled_at          TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS subscriptions_user_id_idx
  ON public.subscriptions (user_id);

CREATE INDEX IF NOT EXISTS subscriptions_status_idx
  ON public.subscriptions (status)
  WHERE status = 'active';


-- ── device_tokens ─────────────────────────────────────────────────────────────
-- Push notification tokens registered by the client after permission grant.
-- Used by the send-push Edge Function + FCM/APNs for server-side notifications.

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id          UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID  NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  token       TEXT  NOT NULL,
  platform    TEXT  NOT NULL CHECK (platform IN ('ios', 'android')),
  app_version TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (user_id, token)
);

CREATE INDEX IF NOT EXISTS device_tokens_user_id_idx
  ON public.device_tokens (user_id);


-- ── user_favorite_exercises ───────────────────────────────────────────────────
-- User-specific exercise favorites (composite PK = no duplicates).

CREATE TABLE IF NOT EXISTS public.user_favorite_exercises (
  user_id     UUID REFERENCES public.profiles(id)  ON DELETE CASCADE,
  exercise_id UUID REFERENCES public.exercises(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, exercise_id)
);

CREATE INDEX IF NOT EXISTS user_favorites_user_idx
  ON public.user_favorite_exercises (user_id);


-- ── personal_records ─────────────────────────────────────────────────────────
-- Append-only log of personal records (best set per exercise).
-- Populated automatically by fn_check_personal_record() trigger on sets.
-- Comparison is by Epley 1RM estimate (one_rep_max_kg) since 037.

CREATE TABLE IF NOT EXISTS public.personal_records (
  id             UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID  NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  exercise_id    UUID  NOT NULL REFERENCES public.exercises(id) ON DELETE CASCADE,
  weight_kg      FLOAT NOT NULL CHECK (weight_kg > 0),
  reps           INT,
  one_rep_max_kg FLOAT,   -- Epley 1RM: weight × (1 + reps/30); stored pre-computed
  session_id     UUID  REFERENCES public.training_sessions(id) ON DELETE SET NULL,
  achieved_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS personal_records_user_exercise_idx
  ON public.personal_records (user_id, exercise_id, achieved_at DESC);

CREATE INDEX IF NOT EXISTS personal_records_1rm_idx
  ON public.personal_records (user_id, exercise_id, one_rep_max_kg DESC);


-- ── push_notification_logs ────────────────────────────────────────────────────
-- Tracks scheduled and tapped push notifications for delivery analytics.

CREATE TABLE IF NOT EXISTS public.push_notification_logs (
  id            UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID  NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  notif_type    TEXT  NOT NULL,       -- 'workout_reminder' | 'session' | 'inactivity' | 'weigh_in' | 'rest_day'
  notif_id      INT   NOT NULL,       -- OS notification id
  scheduled_for TIMESTAMPTZ,         -- NULL for recurring weekly notifications
  session_id    UUID  REFERENCES public.training_sessions(id) ON DELETE SET NULL,
  tapped_at     TIMESTAMPTZ,         -- set when user taps notification
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS push_notif_logs_user_idx
  ON public.push_notification_logs (user_id, created_at DESC);


-- ── user_goals_history ────────────────────────────────────────────────────────
-- Append-only log of goal changes. Populated by fn_log_goal_change() trigger.

CREATE TABLE IF NOT EXISTS public.user_goals_history (
  id         UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID  NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  goal       TEXT  NOT NULL,
  changed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS user_goals_history_user_idx
  ON public.user_goals_history (user_id, changed_at DESC);


-- ── app_config ────────────────────────────────────────────────────────────────
-- Remote key/value configuration (min_version, store URLs, functions_url, etc.).
-- Readable by authenticated users; writable only by service_role.

CREATE TABLE IF NOT EXISTS public.app_config (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);


-- ── feedback ──────────────────────────────────────────────────────────────────
-- In-app user feedback: NPS scores, micro-surveys, screen thumbs, free-form.

CREATE TABLE IF NOT EXISTS public.feedback (
  id         UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID     NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category   TEXT     NOT NULL,    -- 'nps' | 'micro_survey' | 'screen' | 'bug' | 'feature' | 'general'
  rating     SMALLINT,             -- NPS: 0–10; thumbs: 1 (up) / -1 (down)
  message    TEXT,
  metadata   JSONB    NOT NULL DEFAULT '{}',  -- {screen, feature_request, etc.}
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS feedback_user_id_idx    ON public.feedback (user_id);
CREATE INDEX IF NOT EXISTS feedback_category_idx   ON public.feedback (category);
CREATE INDEX IF NOT EXISTS feedback_created_at_idx ON public.feedback (created_at DESC);


-- ── weekly_volume VIEW ────────────────────────────────────────────────────────
-- Aggregates training volume per user / week / muscle group.
-- security_invoker = on ensures RLS on the underlying tables applies,
-- so users can only see their own data.

CREATE OR REPLACE VIEW public.weekly_volume
WITH (security_invoker = on)
AS
SELECT
  ts.user_id,
  date_trunc('week', ts.date::TIMESTAMPTZ)             AS week_start,
  e.category                                            AS muscle_group,
  COUNT(s.id)                                           AS total_sets,
  COALESCE(SUM(s.reps), 0)                             AS total_reps,
  COALESCE(SUM(
    CASE
      WHEN s.weight IS NOT NULL AND s.reps IS NOT NULL
        THEN s.weight * s.reps
      ELSE 0
    END
  ), 0)                                                 AS total_volume_kg
FROM public.sets s
JOIN public.training_sessions ts ON ts.id = s.training_session_id
JOIN public.workout_exercises we  ON we.id = s.workout_exercise_id
JOIN public.exercises e           ON e.id  = we.exercise_id
WHERE s.completed = true
GROUP BY ts.user_id, week_start, e.category;


-- ============================================================
-- SECTION 2: RLS POLICIES
-- ============================================================


-- ── profiles ──────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile"   ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);


-- ── exercises ─────────────────────────────────────────────────────────────────
-- Final state after migrations 012, 037, 038.
-- Standard exercises are readable by all authenticated users;
-- custom exercises visible only to their creator.
-- Hard DELETE is forbidden; use soft_delete_exercise() RPC instead.

ALTER TABLE public.exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "exercises_select" ON public.exercises
  FOR SELECT USING (
    (is_standard = true OR user_id = auth.uid())
    AND deleted_at IS NULL
  );

CREATE POLICY "exercises_insert" ON public.exercises
  FOR INSERT WITH CHECK (is_standard = false AND user_id = auth.uid());

CREATE POLICY "exercises_update" ON public.exercises
  FOR UPDATE USING (user_id = auth.uid() AND is_standard = false);

CREATE POLICY "exercises_delete" ON public.exercises
  FOR DELETE USING (false);  -- hard DELETE forbidden; use soft_delete_exercise()


-- ── workouts ──────────────────────────────────────────────────────────────────
-- Final state after migration 037.
-- SELECT filters out soft-deleted rows; DELETE is forbidden (soft-delete only).

ALTER TABLE public.workouts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workouts_select" ON public.workouts
  FOR SELECT USING (auth.uid() = user_id AND deleted_at IS NULL);

CREATE POLICY "workouts_insert" ON public.workouts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "workouts_update" ON public.workouts
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "workouts_delete" ON public.workouts
  FOR DELETE USING (false);  -- use UPDATE SET deleted_at = NOW() instead


-- ── workout_exercises ─────────────────────────────────────────────────────────
ALTER TABLE public.workout_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage workout_exercises" ON public.workout_exercises
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.workouts w WHERE w.id = workout_id AND w.user_id = auth.uid())
  );


-- ── training_sessions ─────────────────────────────────────────────────────────
ALTER TABLE public.training_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own sessions" ON public.training_sessions
  FOR ALL USING (auth.uid() = user_id);


-- ── sets ──────────────────────────────────────────────────────────────────────
ALTER TABLE public.sets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own sets" ON public.sets
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.training_sessions ts
      WHERE ts.id = training_session_id AND ts.user_id = auth.uid()
    )
  );


-- ── body_metrics ──────────────────────────────────────────────────────────────
ALTER TABLE public.body_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own body_metrics" ON public.body_metrics
  FOR ALL USING (auth.uid() = user_id);


-- ── wellness_logs ─────────────────────────────────────────────────────────────
ALTER TABLE public.wellness_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own wellness_logs" ON public.wellness_logs
  FOR ALL USING (auth.uid() = user_id);


-- ── user_events ───────────────────────────────────────────────────────────────
ALTER TABLE public.user_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert own events" ON public.user_events
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view own events" ON public.user_events
  FOR SELECT USING (auth.uid() = user_id);


-- ── weight_logs ───────────────────────────────────────────────────────────────
ALTER TABLE public.weight_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own weight logs" ON public.weight_logs
  FOR ALL
  USING     (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);


-- ── subscriptions ─────────────────────────────────────────────────────────────
-- Write access is service_role only (webhook-driven). Users can only read.

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own subscriptions" ON public.subscriptions
  FOR SELECT USING (auth.uid() = user_id);


-- ── device_tokens ─────────────────────────────────────────────────────────────
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own device tokens" ON public.device_tokens
  FOR ALL USING (auth.uid() = user_id);


-- ── user_favorite_exercises ───────────────────────────────────────────────────
ALTER TABLE public.user_favorite_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own favorites" ON public.user_favorite_exercises
  FOR ALL USING (auth.uid() = user_id);


-- ── personal_records ─────────────────────────────────────────────────────────
ALTER TABLE public.personal_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own personal_records" ON public.personal_records
  FOR ALL USING (auth.uid() = user_id);


-- ── push_notification_logs ────────────────────────────────────────────────────
ALTER TABLE public.push_notification_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own notif logs" ON public.push_notification_logs
  FOR ALL USING (auth.uid() = user_id);


-- ── user_goals_history ────────────────────────────────────────────────────────
ALTER TABLE public.user_goals_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own goals history" ON public.user_goals_history
  FOR ALL USING (auth.uid() = user_id);


-- ── app_config ────────────────────────────────────────────────────────────────
-- Final state: authenticated users only (migration 042 replaced the earlier anon policy).

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "app_config readable by authenticated" ON public.app_config
  FOR SELECT
  TO authenticated
  USING (true);


-- ── feedback ──────────────────────────────────────────────────────────────────
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert own feedback" ON public.feedback
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can read own feedback" ON public.feedback
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);


-- ── storage.objects (Supabase Storage buckets) ────────────────────────────────
-- exercise-gifs bucket: public read (040)
CREATE POLICY "exercise_gifs_public_read" ON storage.objects
  FOR SELECT USING (bucket_id = 'exercise-gifs');

-- avatars bucket: public read, owner-only write (041)
CREATE POLICY "avatars_public_read" ON storage.objects
  FOR SELECT USING (bucket_id = 'avatars');

CREATE POLICY "avatars_user_upload" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'avatars' AND auth.uid()::text = split_part(name, '.', 1));

CREATE POLICY "avatars_user_update" ON storage.objects
  FOR UPDATE USING (bucket_id = 'avatars' AND auth.uid()::text = split_part(name, '.', 1));

CREATE POLICY "avatars_user_delete" ON storage.objects
  FOR DELETE USING (bucket_id = 'avatars' AND auth.uid()::text = split_part(name, '.', 1));


-- ============================================================
-- SECTION 3: FUNCTIONS & TRIGGERS
-- ============================================================


-- ── update_updated_at ─────────────────────────────────────────────────────────
-- Generic BEFORE UPDATE trigger function that sets updated_at = NOW().
-- Used by profiles, workouts, body_metrics (via body_metrics_updated_at trigger),
-- wellness_logs, subscriptions, device_tokens.

CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER workouts_updated_at
  BEFORE UPDATE ON public.workouts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER wellness_logs_updated_at
  BEFORE UPDATE ON public.wellness_logs
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER subscriptions_updated_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


-- ── _set_body_metrics_updated_at ─────────────────────────────────────────────
-- Dedicated updated_at function for body_metrics (added in migration 025).
-- Replaces the earlier body_metrics_updated_at trigger from migration 009.

CREATE OR REPLACE FUNCTION public._set_body_metrics_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_body_metrics_updated_at
  BEFORE UPDATE ON public.body_metrics
  FOR EACH ROW EXECUTE FUNCTION public._set_body_metrics_updated_at();


-- ── handle_new_user ───────────────────────────────────────────────────────────
-- Runs as SECURITY DEFINER (bypasses RLS) to auto-create a profiles row
-- whenever a new auth.users row is inserted (i.e., on registration).

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    full_name,
    first_name,
    last_name,
    birth_date,
    nickname,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    COALESCE(
      NULLIF(
        trim(
          concat_ws(
            ' ',
            NEW.raw_user_meta_data->>'first_name',
            NEW.raw_user_meta_data->>'last_name'
          )
        ),
        ''
      ),
      NEW.raw_user_meta_data->>'full_name',
      split_part(NEW.email, '@', 1),
      'User'
    ),
    NEW.raw_user_meta_data->>'first_name',
    NEW.raw_user_meta_data->>'last_name',
    NULLIF(NEW.raw_user_meta_data->>'birth_date', '')::date,
    NEW.raw_user_meta_data->>'nickname',
    NOW(),
    NOW()
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ── get_email_by_nickname ─────────────────────────────────────────────────────
-- Maps nickname → email for the login-by-nickname flow.
-- WARNING: enables email lookup by nickname — apply rate limiting / captcha
-- at the edge layer in production.

CREATE OR REPLACE FUNCTION public.get_email_by_nickname(p_nickname TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.email
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE lower(p.nickname) = lower(p_nickname)
  LIMIT 1
$$;

REVOKE ALL ON FUNCTION public.get_email_by_nickname(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_email_by_nickname(TEXT) TO anon, authenticated;


-- ── sync_pro_status ───────────────────────────────────────────────────────────
-- Syncs profiles.is_pro / pro_expires_at from the subscriptions table.
-- Called from server-side webhook after receipt validation.

CREATE OR REPLACE FUNCTION public.sync_pro_status(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_active RECORD;
BEGIN
  SELECT plan, current_period_end
  INTO   v_active
  FROM   public.subscriptions
  WHERE  user_id = p_user_id
    AND  status  = 'active'
    AND  (current_period_end IS NULL OR current_period_end > NOW())
  ORDER BY
    CASE WHEN plan = 'lifetime' THEN 0 ELSE 1 END,
    current_period_end DESC NULLS FIRST
  LIMIT 1;

  IF FOUND THEN
    UPDATE public.profiles
    SET    is_pro         = true,
           pro_expires_at = v_active.current_period_end,
           updated_at     = NOW()
    WHERE  id = p_user_id;
  ELSE
    UPDATE public.profiles
    SET    is_pro         = false,
           pro_expires_at = NULL,
           updated_at     = NOW()
    WHERE  id = p_user_id
      AND  is_pro = true;
  END IF;
END;
$$;


-- ── get_community_avg_exercise_weight ─────────────────────────────────────────
-- Returns median max weight (Epley approach) across all users for a given
-- exercise over the last 7 days. Returns NULL if no data.
-- Named "avg" in the API but the value is a median (PERCENTILE_CONT 0.5),
-- which is more robust to outliers.

CREATE OR REPLACE FUNCTION public.get_community_avg_exercise_weight(
  p_exercise_id UUID
)
RETURNS NUMERIC
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  WITH user_max AS (
    SELECT ts.user_id,
           MAX(s.weight) AS max_weight
    FROM   sets s
    JOIN   workout_exercises we ON we.id = s.workout_exercise_id
    JOIN   training_sessions ts ON ts.id = s.training_session_id
    WHERE  we.exercise_id = p_exercise_id
      AND  s.completed    = true
      AND  s.weight       IS NOT NULL
      AND  ts.completed   = true
      AND  ts.date::DATE >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY ts.user_id
  )
  SELECT ROUND(
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY max_weight)::NUMERIC,
    1
  )
  FROM user_max;
$$;

GRANT EXECUTE ON FUNCTION public.get_community_avg_exercise_weight(UUID)
  TO authenticated;


-- ── get_community_avg_weekly_volume ──────────────────────────────────────────
-- Returns median average weekly volume (kg × reps) across all users over the
-- last 8 weeks. Returns NULL if no data.

CREATE OR REPLACE FUNCTION public.get_community_avg_weekly_volume()
RETURNS NUMERIC
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  WITH user_weekly AS (
    SELECT ts.user_id,
           DATE_TRUNC('week', ts.date::DATE) AS week_start,
           SUM(s.weight * s.reps)            AS week_volume
    FROM   sets s
    JOIN   training_sessions ts ON ts.id = s.training_session_id
    WHERE  s.completed  = true
      AND  s.weight     IS NOT NULL
      AND  ts.completed = true
      AND  ts.date::DATE >= CURRENT_DATE - INTERVAL '56 days'
    GROUP BY ts.user_id, DATE_TRUNC('week', ts.date::DATE)
  ),
  user_avg AS (
    SELECT user_id,
           AVG(week_volume) AS avg_vol
    FROM   user_weekly
    GROUP BY user_id
  )
  SELECT ROUND(
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_vol)::NUMERIC,
    1
  )
  FROM user_avg;
$$;

GRANT EXECUTE ON FUNCTION public.get_community_avg_weekly_volume()
  TO authenticated;


-- ── fn_check_personal_record ─────────────────────────────────────────────────
-- Fires AFTER INSERT OR UPDATE on sets. Inserts a row into personal_records
-- when a completed weighted set exceeds the user's current best (by Epley 1RM).
-- Final version from migration 037 (adds one_rep_max_kg comparison).

CREATE OR REPLACE FUNCTION public.fn_check_personal_record()
RETURNS TRIGGER AS $$
DECLARE
  v_exercise_id UUID;
  v_user_id     UUID;
  v_current_max FLOAT;
  v_one_rep_max FLOAT;
BEGIN
  -- Only process completed, weighted sets
  IF NEW.completed = false OR NEW.weight IS NULL OR NEW.weight <= 0 THEN
    RETURN NEW;
  END IF;

  SELECT exercise_id INTO v_exercise_id
    FROM public.workout_exercises WHERE id = NEW.workout_exercise_id;

  SELECT user_id INTO v_user_id
    FROM public.training_sessions WHERE id = NEW.training_session_id;

  -- Epley 1RM estimate: weight × (1 + reps / 30)
  v_one_rep_max :=
    CASE
      WHEN NEW.reps IS NOT NULL AND NEW.reps BETWEEN 1 AND 30
        THEN NEW.weight * (1.0 + NEW.reps::FLOAT / 30.0)
      ELSE NEW.weight
    END;

  SELECT MAX(one_rep_max_kg) INTO v_current_max
    FROM public.personal_records
    WHERE user_id = v_user_id AND exercise_id = v_exercise_id;

  IF v_current_max IS NULL OR v_one_rep_max > v_current_max THEN
    INSERT INTO public.personal_records
      (user_id, exercise_id, weight_kg, reps, one_rep_max_kg, session_id, achieved_at)
    VALUES
      (v_user_id, v_exercise_id, NEW.weight, NEW.reps,
       ROUND(v_one_rep_max::NUMERIC, 2),
       NEW.training_session_id, COALESCE(NEW.performed_at, NOW()));
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Fires on INSERT and on UPDATE of weight/reps/completed (added in 039)
CREATE TRIGGER sets_personal_record_check
  AFTER INSERT OR UPDATE OF weight, reps, completed
  ON public.sets
  FOR EACH ROW EXECUTE FUNCTION public.fn_check_personal_record();


-- ── fn_log_goal_change ────────────────────────────────────────────────────────
-- Fires AFTER UPDATE on profiles. Appends a row to user_goals_history
-- whenever the goal column changes.

CREATE OR REPLACE FUNCTION public.fn_log_goal_change()
RETURNS TRIGGER AS $$
BEGIN
  IF (OLD.goal IS DISTINCT FROM NEW.goal) AND NEW.goal IS NOT NULL THEN
    INSERT INTO public.user_goals_history (user_id, goal, changed_at)
    VALUES (NEW.id, NEW.goal, NOW());
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_goal_change
  AFTER UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.fn_log_goal_change();


-- ── soft_delete_exercise ──────────────────────────────────────────────────────
-- RPC callable by authenticated users to soft-delete their own custom exercise.
-- Only sets deleted_at; the exercise row (and historical sets) remain in the DB.

CREATE OR REPLACE FUNCTION public.soft_delete_exercise(p_exercise_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.exercises
  SET deleted_at = NOW()
  WHERE id          = p_exercise_id
    AND user_id     = auth.uid()   -- only the creator
    AND is_standard = false        -- never touch standard exercises
    AND deleted_at  IS NULL;       -- idempotent

  IF NOT FOUND THEN
    RAISE EXCEPTION 'exercise not found or not owned by current user';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.soft_delete_exercise(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_exercise(UUID) TO authenticated;
