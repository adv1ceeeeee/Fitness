-- Migration 053: persist energy reserve checkpoint per session
--
-- energy_end stores the athlete's energy reserve (0–100) at the moment the
-- session was completed. The next session's starting reserve is derived from
-- this value + exponential recovery (not recomputed from scratch), ensuring
-- the hidden-state trajectory is strictly sequential in time.

ALTER TABLE training_sessions
  ADD COLUMN IF NOT EXISTS energy_end double precision;

-- Index for the single-row "last checkpoint" lookup
-- (user_id + completed + date DESC LIMIT 1)
CREATE INDEX IF NOT EXISTS idx_training_sessions_energy_checkpoint
  ON training_sessions (user_id, date DESC)
  WHERE completed = true AND energy_end IS NOT NULL;

COMMENT ON COLUMN training_sessions.energy_end IS
  'Energy reserve (0–100) at session end — checkpoint for the inter-session recovery model.';
