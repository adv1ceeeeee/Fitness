-- Store body-progress goal in profiles so it persists across sessions/devices.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS goal_metric TEXT    NOT NULL DEFAULT 'weight_kg',
  ADD COLUMN IF NOT EXISTS goal_target NUMERIC,
  ADD COLUMN IF NOT EXISTS goal_start  DATE;
