-- ============================================================
-- Migration 011: group_id for multi-section programs
-- Allows multiple Workout rows to belong to the same program.
-- ============================================================

ALTER TABLE public.workouts
  ADD COLUMN IF NOT EXISTS group_id UUID;

CREATE INDEX IF NOT EXISTS workouts_group_id_idx
  ON public.workouts(group_id)
  WHERE group_id IS NOT NULL;
