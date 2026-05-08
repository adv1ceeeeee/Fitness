-- Migration 059: per-week target weights for exercises inside a program cycle.
-- Keys are 1-based week numbers stored as strings by JSONB, values are weights in kg.

ALTER TABLE public.workout_exercises
  ADD COLUMN IF NOT EXISTS weekly_target_weights JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.workout_exercises
  ADD COLUMN IF NOT EXISTS drop_set_weekly_target_weights JSONB NOT NULL DEFAULT '{}'::jsonb;
