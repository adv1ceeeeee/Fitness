-- 057: Optional human-readable name for a multi-section workout program.
-- Denormalised — all sections of the same program (sharing group_id) carry
-- the same group_name. Single-section workouts leave it NULL and fall back
-- to the workout's own `name` for display.
--
-- We update all sections of a group together via WorkoutService.renameProgram,
-- so the values stay in sync without needing a separate workout_groups table.

BEGIN;

ALTER TABLE workouts
  ADD COLUMN IF NOT EXISTS group_name TEXT;

COMMIT;
