-- Planned start time for individual training sessions.
-- Used for "notify N minutes before" mode.
ALTER TABLE training_sessions
  ADD COLUMN IF NOT EXISTS planned_time TIME;
