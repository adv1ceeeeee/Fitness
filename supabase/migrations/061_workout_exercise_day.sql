-- Migration 061: assign exercises inside one workout program to weekdays.
-- day uses the app convention: 0 = Monday ... 6 = Sunday.
-- NULL means the exercise is shared across every scheduled day.

ALTER TABLE public.workout_exercises
  ADD COLUMN IF NOT EXISTS day INTEGER;

ALTER TABLE public.workout_exercises
  DROP CONSTRAINT IF EXISTS workout_exercises_day_check;

ALTER TABLE public.workout_exercises
  ADD CONSTRAINT workout_exercises_day_check
    CHECK (day IS NULL OR (day >= 0 AND day <= 6));

CREATE INDEX IF NOT EXISTS idx_workout_exercises_workout_day_order
  ON public.workout_exercises (workout_id, day, "order");
