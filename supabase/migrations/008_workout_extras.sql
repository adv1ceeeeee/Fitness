-- Add target weight and target RPE to workout exercise templates
ALTER TABLE public.workout_exercises
  ADD COLUMN IF NOT EXISTS target_weight FLOAT,
  ADD COLUMN IF NOT EXISTS target_rpe    INT CHECK (target_rpe >= 0 AND target_rpe <= 10);

-- Add cycle duration (weeks) to workouts
ALTER TABLE public.workouts
  ADD COLUMN IF NOT EXISTS cycle_weeks INT DEFAULT 8;
