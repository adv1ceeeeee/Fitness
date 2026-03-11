-- ============================================================
-- Migration 010: schema additions (duration, warmup/cooldown,
--                superset grouping)
-- Combines former 010–013 into one migration.
-- NOTE: training_sessions.notes already exists in 001.
-- ============================================================

-- workout_exercises.duration_minutes — for cardio exercises
ALTER TABLE public.workout_exercises
  ADD COLUMN IF NOT EXISTS duration_minutes INTEGER;

-- workouts.warmup_minutes / cooldown_minutes
ALTER TABLE public.workouts
  ADD COLUMN IF NOT EXISTS warmup_minutes  INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cooldown_minutes INTEGER NOT NULL DEFAULT 0;

-- workout_exercises.superset_group — exercises with same non-null value form a superset
ALTER TABLE public.workout_exercises
  ADD COLUMN IF NOT EXISTS superset_group INTEGER;
