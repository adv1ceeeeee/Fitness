-- Add updated_at timestamp to body_metrics for display in the progress card.
ALTER TABLE body_metrics
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Trigger: keep updated_at current on every UPDATE.
CREATE OR REPLACE FUNCTION _set_body_metrics_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_body_metrics_updated_at ON body_metrics;
CREATE TRIGGER trg_body_metrics_updated_at
  BEFORE UPDATE ON body_metrics
  FOR EACH ROW EXECUTE FUNCTION _set_body_metrics_updated_at();

-- Change goal_start from DATE to TIMESTAMPTZ so we can show the exact time.
ALTER TABLE profiles
  ALTER COLUMN goal_start TYPE TIMESTAMPTZ USING goal_start::TIMESTAMPTZ;
