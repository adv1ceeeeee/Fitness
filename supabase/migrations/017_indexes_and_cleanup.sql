-- ============================================================
-- Migration 017: performance indexes + schema hardening
-- Add before user growth — cheap to add now, costly to add later.
-- ============================================================

-- ── 1. Hot query indexes ──────────────────────────────────────────────────────

-- Calendar + history: user's sessions ordered by date
CREATE INDEX IF NOT EXISTS training_sessions_user_date_idx
  ON public.training_sessions (user_id, date DESC);

-- Active session lookup (FAB, session restore)
CREATE INDEX IF NOT EXISTS training_sessions_user_completed_idx
  ON public.training_sessions (user_id, completed)
  WHERE completed = false;

-- Set lookup for session detail screen
CREATE INDEX IF NOT EXISTS sets_session_idx
  ON public.sets (training_session_id);

-- Exercise progress chart: sets by exercise + completed
CREATE INDEX IF NOT EXISTS sets_workout_exercise_idx
  ON public.sets (workout_exercise_id, training_session_id)
  WHERE completed = true;

-- My workouts list
CREATE INDEX IF NOT EXISTS workouts_user_id_idx
  ON public.workouts (user_id);

-- Exercises in a workout (session screen, add-exercises screen)
CREATE INDEX IF NOT EXISTS workout_exercises_workout_id_idx
  ON public.workout_exercises (workout_id, "order");

-- Body metrics chart
CREATE INDEX IF NOT EXISTS body_metrics_user_date_idx
  ON public.body_metrics (user_id, date DESC);

-- Wellness logs
CREATE INDEX IF NOT EXISTS wellness_logs_user_date_idx
  ON public.wellness_logs (user_id, date DESC);

-- Weight logs (today's weigh-ins)
CREATE INDEX IF NOT EXISTS weight_logs_user_measured_at_idx
  ON public.weight_logs (user_id, measured_at DESC);

-- ── 2. Schema hardening ───────────────────────────────────────────────────────

-- Ensure nickname is lowercase only (prevents duplicate-by-case attacks)
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_nickname_lowercase;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_nickname_lowercase
    CHECK (nickname = lower(nickname));

-- workouts.name must not be blank
ALTER TABLE public.workouts
  DROP CONSTRAINT IF EXISTS workouts_name_not_blank;
ALTER TABLE public.workouts
  ADD CONSTRAINT workouts_name_not_blank
    CHECK (length(trim(name)) > 0);

-- sets.weight must be positive if provided
ALTER TABLE public.sets
  DROP CONSTRAINT IF EXISTS sets_weight_positive;
ALTER TABLE public.sets
  ADD CONSTRAINT sets_weight_positive
    CHECK (weight IS NULL OR weight > 0);

-- sets.reps must be positive if provided
ALTER TABLE public.sets
  DROP CONSTRAINT IF EXISTS sets_reps_positive;
ALTER TABLE public.sets
  ADD CONSTRAINT sets_reps_positive
    CHECK (reps IS NULL OR reps > 0);

-- body_metrics: weight and measurements must be positive
ALTER TABLE public.body_metrics
  DROP CONSTRAINT IF EXISTS body_metrics_weight_positive;
ALTER TABLE public.body_metrics
  ADD CONSTRAINT body_metrics_weight_positive
    CHECK (weight_kg IS NULL OR weight_kg > 0);

-- ── 3. Missing updated_at triggers ───────────────────────────────────────────
-- profiles and workouts already have updated_at columns but may lack triggers

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'profiles_updated_at'
  ) THEN
    CREATE TRIGGER profiles_updated_at
      BEFORE UPDATE ON public.profiles
      FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'workouts_updated_at'
  ) THEN
    CREATE TRIGGER workouts_updated_at
      BEFORE UPDATE ON public.workouts
      FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
END $$;

-- ── 4. Device tokens (for future server-side push notifications) ──────────────
-- Client registers token after requesting permission.
-- Server uses this to send push from Supabase Edge Function + FCM/APNs.

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  token       TEXT        NOT NULL,
  platform    TEXT        NOT NULL CHECK (platform IN ('ios', 'android')),
  app_version TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (user_id, token)
);

CREATE INDEX IF NOT EXISTS device_tokens_user_id_idx
  ON public.device_tokens (user_id);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own device tokens" ON public.device_tokens
  FOR ALL USING (auth.uid() = user_id);
