-- Weight logs: multiple timestamped weigh-ins per day per user
CREATE TABLE IF NOT EXISTS weight_logs (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  weight_kg   DECIMAL(5,2) NOT NULL,
  measured_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS weight_logs_user_time
  ON weight_logs(user_id, measured_at DESC);

ALTER TABLE weight_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own weight logs"
  ON weight_logs FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
