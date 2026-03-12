-- Add drop-set flag to workout exercises
ALTER TABLE workout_exercises
  ADD COLUMN IF NOT EXISTS is_drop_set BOOLEAN NOT NULL DEFAULT FALSE;
