-- Track when each set begins (rest ends / first set of exercise starts).
-- NULL for sets saved before this migration (historical data).
ALTER TABLE sets
    ADD COLUMN IF NOT EXISTS started_at timestamptz;
