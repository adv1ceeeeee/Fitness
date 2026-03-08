-- Add warmup and cooldown duration fields to workouts
ALTER TABLE workouts ADD COLUMN warmup_minutes INTEGER NOT NULL DEFAULT 0;
ALTER TABLE workouts ADD COLUMN cooldown_minutes INTEGER NOT NULL DEFAULT 0;
