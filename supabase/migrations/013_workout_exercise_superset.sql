-- Add superset grouping to workout exercises.
-- Exercises with the same non-null superset_group value within a workout form a superset.
ALTER TABLE workout_exercises ADD COLUMN IF NOT EXISTS superset_group INTEGER;
