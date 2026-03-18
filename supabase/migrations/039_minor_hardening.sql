-- ============================================================
-- Migration 039: minor hardening
--
-- 1. exercises.user_id FK  auth.users → profiles
-- 2. PR trigger fires on set UPDATE (not only INSERT)
-- 3. workouts.days CHECK (values 0–6)
-- ============================================================


-- ── 1. exercises.user_id: auth.users → profiles ───────────────────────────────
-- Migration 012 accidentally referenced auth.users instead of profiles.
-- Same issue we fixed for weight_logs in 037.

ALTER TABLE public.exercises
  DROP CONSTRAINT IF EXISTS exercises_user_id_fkey;

ALTER TABLE public.exercises
  ADD CONSTRAINT exercises_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES public.profiles(id)
    ON DELETE CASCADE;


-- ── 2. PR trigger fires on UPDATE too ────────────────────────────────────────
-- Previously the trigger only fired on INSERT into sets.
-- If a user edits set weight in session summary, PR was silently skipped.

DROP TRIGGER IF EXISTS sets_personal_record_check ON public.sets;

CREATE TRIGGER sets_personal_record_check
  AFTER INSERT OR UPDATE OF weight, reps, completed
  ON public.sets
  FOR EACH ROW EXECUTE FUNCTION fn_check_personal_record();


-- ── 3. workouts.days — validate values are 0–6 ───────────────────────────────
-- Prevents invalid day numbers (e.g. [99, -1]) from being stored.
-- 0 = Mon … 6 = Sun, matching Flutter's weekday - 1 convention.

ALTER TABLE public.workouts
  DROP CONSTRAINT IF EXISTS workouts_days_valid;

ALTER TABLE public.workouts
  ADD CONSTRAINT workouts_days_valid
    CHECK (
      days <@ ARRAY[0, 1, 2, 3, 4, 5, 6]
    );

-- Same for rest_days
ALTER TABLE public.workouts
  DROP CONSTRAINT IF EXISTS workouts_rest_days_valid;

ALTER TABLE public.workouts
  ADD CONSTRAINT workouts_rest_days_valid
    CHECK (
      rest_days <@ ARRAY[0, 1, 2, 3, 4, 5, 6]
    );
