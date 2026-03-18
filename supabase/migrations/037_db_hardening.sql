-- ============================================================
-- Migration 037: database hardening & flexibility
--
-- 1. CASCADE → SET NULL  (prevents accidental data loss)
-- 2. Soft deletes on workouts & exercises
-- 3. DROP profiles.age  (stale — use birth_date instead)
-- 4. weekly_volume VIEW — include bodyweight exercises
-- 5. exercises.muscle_groups TEXT[]  (granular muscle targeting)
-- 6. personal_records + 1RM estimate  (Epley formula)
-- 7. weight_logs FK fix  (auth.users → profiles)
-- 8. Additional composite indexes
-- ============================================================


-- ── 1. CASCADE → SET NULL ─────────────────────────────────────────────────────
-- BEFORE: deleting a workout_exercise cascades and deletes all historical sets.
-- AFTER:  sets survive; workout_exercise_id becomes NULL (history preserved).

ALTER TABLE public.sets
  DROP CONSTRAINT IF EXISTS sets_workout_exercise_id_fkey;

ALTER TABLE public.sets
  ADD CONSTRAINT sets_workout_exercise_id_fkey
    FOREIGN KEY (workout_exercise_id)
    REFERENCES public.workout_exercises(id)
    ON DELETE SET NULL;

-- BEFORE: deleting a workout cascades and deletes all training sessions.
-- AFTER:  sessions survive; workout_id becomes NULL (history preserved).

ALTER TABLE public.training_sessions
  DROP CONSTRAINT IF EXISTS training_sessions_workout_id_fkey;

ALTER TABLE public.training_sessions
  ADD CONSTRAINT training_sessions_workout_id_fkey
    FOREIGN KEY (workout_id)
    REFERENCES public.workouts(id)
    ON DELETE SET NULL;


-- ── 2. Soft deletes on workouts ───────────────────────────────────────────────
-- Deleted workouts are hidden from the app but can be recovered.
-- Flutter must filter WHERE deleted_at IS NULL in queries.

ALTER TABLE public.workouts
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

-- Fast lookup: only non-deleted workouts visible in the app
CREATE INDEX IF NOT EXISTS workouts_user_active_idx
  ON public.workouts (user_id, deleted_at)
  WHERE deleted_at IS NULL;

-- Update RLS so soft-deleted workouts are invisible in SELECT
-- (Replace existing FOR ALL policy with separate per-command policies)
DROP POLICY IF EXISTS "Users can view own workouts"   ON public.workouts;
DROP POLICY IF EXISTS "Users can insert own workouts" ON public.workouts;
DROP POLICY IF EXISTS "Users can update own workouts" ON public.workouts;
DROP POLICY IF EXISTS "Users can delete own workouts" ON public.workouts;
DROP POLICY IF EXISTS "workouts_select"               ON public.workouts;
DROP POLICY IF EXISTS "workouts_insert"               ON public.workouts;
DROP POLICY IF EXISTS "workouts_update"               ON public.workouts;
DROP POLICY IF EXISTS "workouts_delete"               ON public.workouts;

CREATE POLICY "workouts_select" ON public.workouts
  FOR SELECT USING (auth.uid() = user_id AND deleted_at IS NULL);

CREATE POLICY "workouts_insert" ON public.workouts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "workouts_update" ON public.workouts
  FOR UPDATE USING (auth.uid() = user_id);

-- Physical DELETE is now forbidden for users; use UPDATE SET deleted_at = NOW().
-- Service-role can still hard-delete if needed.
CREATE POLICY "workouts_delete" ON public.workouts
  FOR DELETE USING (false);


-- ── 3. Soft deletes on user-created exercises ─────────────────────────────────
-- Standard exercises (is_standard = true) are never deleted.
-- User-created exercises can be soft-deleted.

ALTER TABLE public.exercises
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

CREATE INDEX IF NOT EXISTS exercises_active_idx
  ON public.exercises (deleted_at)
  WHERE deleted_at IS NULL;

DROP POLICY IF EXISTS "Exercises are viewable by all" ON public.exercises;
DROP POLICY IF EXISTS "exercises_select"              ON public.exercises;
DROP POLICY IF EXISTS "exercises_update_own"          ON public.exercises;

CREATE POLICY "exercises_select" ON public.exercises
  FOR SELECT USING (deleted_at IS NULL);

-- Users can soft-delete their own exercises (UPDATE deleted_at)
CREATE POLICY "exercises_update_own" ON public.exercises
  FOR UPDATE USING (
    is_standard = false AND
    EXISTS (
      SELECT 1 FROM public.workout_exercises we
      JOIN public.workouts w ON w.id = we.workout_id
      WHERE we.exercise_id = exercises.id AND w.user_id = auth.uid()
    )
  );


-- ── 4. DROP profiles.age ──────────────────────────────────────────────────────
-- age is a stale computed column; birth_date is the source of truth.
-- Compute age in Flutter: DateTime.now().difference(birthDate).inDays ~/ 365

ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS age;


-- ── 5. Fix weekly_volume VIEW — include bodyweight exercises ──────────────────
-- Previously: WHERE s.weight IS NOT NULL excluded all bodyweight sets.
-- Now: bodyweight sets count toward total_sets and total_reps;
--      total_volume_kg is 0 for them (body weight unknown server-side).

CREATE OR REPLACE VIEW public.weekly_volume AS
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
JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
JOIN public.exercises e          ON e.id  = we.exercise_id
WHERE s.completed = true
GROUP BY ts.user_id, week_start, e.category;


-- ── 6. exercises.muscle_groups — granular muscle targeting ────────────────────
-- category = broad group (chest, back, …)
-- muscle_groups = specific muscles (e.g. ['pectoralis_major', 'triceps'])
-- Nullable for backwards compatibility; populated incrementally.

ALTER TABLE public.exercises
  ADD COLUMN IF NOT EXISTS muscle_groups TEXT[] DEFAULT '{}';

-- GIN index for fast "find exercises targeting muscle X" queries
CREATE INDEX IF NOT EXISTS exercises_muscle_groups_gin_idx
  ON public.exercises USING GIN (muscle_groups);


-- ── 7. personal_records — add 1RM estimate ───────────────────────────────────
-- Epley formula: 1RM ≈ weight × (1 + reps / 30)  (valid for reps 1–12)
-- Stored pre-computed for fast leaderboard / progress queries.

ALTER TABLE public.personal_records
  ADD COLUMN IF NOT EXISTS one_rep_max_kg FLOAT;

-- Backfill existing rows
UPDATE public.personal_records
SET one_rep_max_kg =
  CASE
    WHEN reps IS NOT NULL AND reps BETWEEN 1 AND 30
      THEN ROUND((weight_kg * (1.0 + reps::FLOAT / 30.0))::NUMERIC, 2)
    ELSE weight_kg
  END
WHERE one_rep_max_kg IS NULL;

-- Update trigger to compare by 1RM instead of raw weight
-- (allows "80 kg × 10" to beat "90 kg × 1" when 1RM-equivalent is higher)
CREATE OR REPLACE FUNCTION fn_check_personal_record()
RETURNS TRIGGER AS $$
DECLARE
  v_exercise_id   UUID;
  v_user_id       UUID;
  v_current_max   FLOAT;
  v_one_rep_max   FLOAT;
BEGIN
  -- Only process completed, weighted sets
  IF NEW.completed = false OR NEW.weight IS NULL OR NEW.weight <= 0 THEN
    RETURN NEW;
  END IF;

  SELECT exercise_id INTO v_exercise_id
    FROM public.workout_exercises WHERE id = NEW.workout_exercise_id;

  SELECT user_id INTO v_user_id
    FROM public.training_sessions WHERE id = NEW.training_session_id;

  -- Epley 1RM estimate
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


-- ── 8. Fix weight_logs FK (auth.users → profiles) ────────────────────────────
-- Migration 013 accidentally referenced auth.users instead of profiles.
-- This causes orphaned rows when profile is deleted but auth user exists.

ALTER TABLE public.weight_logs
  DROP CONSTRAINT IF EXISTS weight_logs_user_id_fkey;

ALTER TABLE public.weight_logs
  ADD CONSTRAINT weight_logs_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES public.profiles(id)
    ON DELETE CASCADE;


-- ── 9. Additional composite indexes ──────────────────────────────────────────

-- user_events: analytical queries filter by user + event + time window
CREATE INDEX IF NOT EXISTS user_events_user_event_time_idx
  ON public.user_events (user_id, event, created_at DESC);

-- sets: fast volume calculation for sessions (exclude warmups + null weight)
CREATE INDEX IF NOT EXISTS sets_session_completed_idx
  ON public.sets (training_session_id, completed, is_warmup)
  WHERE completed = true AND is_warmup = false;

-- personal_records: leaderboard / 1RM lookup per user+exercise
CREATE INDEX IF NOT EXISTS personal_records_1rm_idx
  ON public.personal_records (user_id, exercise_id, one_rep_max_kg DESC);

-- workouts: marketplace queries
-- (already exists as workouts_marketplace_idx in 016, skip)

-- training_sessions: weekly stats (completed sessions in date range)
CREATE INDEX IF NOT EXISTS training_sessions_user_date_completed_idx
  ON public.training_sessions (user_id, date DESC, completed)
  WHERE completed = true;
