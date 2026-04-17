-- 056: Additive support for cardio & bodyweight exercise input modes.
-- All columns are nullable and have no defaults — existing rows keep working
-- unchanged. The app derives input mode from exercises.category / equipment_type
-- by default; exercises.input_mode acts as an explicit override for edge cases.

BEGIN;

-- Duration for time-based sets (cardio). NULL for strength sets.
ALTER TABLE sets
  ADD COLUMN IF NOT EXISTS duration_seconds INT;

-- Distance in meters for cardio sets. NULL for non-cardio.
ALTER TABLE sets
  ADD COLUMN IF NOT EXISTS distance_m REAL;

-- Optional explicit input mode override per exercise:
-- 'weighted' | 'bodyweight' | 'cardio'. NULL → derive from category/equipment.
ALTER TABLE exercises
  ADD COLUMN IF NOT EXISTS input_mode TEXT;

-- Sanity constraint: only allow known values (NULL remains valid).
ALTER TABLE exercises
  DROP CONSTRAINT IF EXISTS exercises_input_mode_check;
ALTER TABLE exercises
  ADD CONSTRAINT exercises_input_mode_check
  CHECK (input_mode IS NULL OR input_mode IN ('weighted', 'bodyweight', 'cardio'));

COMMIT;
