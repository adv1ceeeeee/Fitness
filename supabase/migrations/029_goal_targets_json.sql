-- Per-metric goal storage.
-- Each metric key maps to {"target": number, "start": iso8601}.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS goal_targets_json JSONB DEFAULT '{}';
