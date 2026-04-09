-- Gamification: XP, levels, seasons
-- Migration 054

-- XP total on profile
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS xp_total integer NOT NULL DEFAULT 0;

-- XP log for audit and rollback
CREATE TABLE IF NOT EXISTS xp_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  amount integer NOT NULL,
  reason text NOT NULL,         -- 'workout_completed', 'set_completed', 'personal_record', etc.
  source_id uuid,               -- training_session_id, set_id, etc.
  daily_total integer,          -- running daily total at time of award (for cap audit)
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_xp_log_user_date
  ON xp_log (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_xp_log_user_reason_date
  ON xp_log (user_id, reason, created_at DESC);

-- RLS policies
ALTER TABLE xp_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY xp_log_select ON xp_log
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY xp_log_insert ON xp_log
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Season log: tracks decay events
CREATE TABLE IF NOT EXISTS xp_season_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  season_start date NOT NULL,
  xp_before integer NOT NULL,
  xp_after integer NOT NULL,
  decay_factor double precision NOT NULL DEFAULT 0.5,
  applied_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE xp_season_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY xp_season_log_select ON xp_season_log
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY xp_season_log_insert ON xp_season_log
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Atomic XP increment (avoids read-then-write race)
CREATE OR REPLACE FUNCTION increment_xp(p_user_id uuid, p_amount integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
  UPDATE profiles
  SET xp_total = xp_total + p_amount
  WHERE id = p_user_id;
$$;
