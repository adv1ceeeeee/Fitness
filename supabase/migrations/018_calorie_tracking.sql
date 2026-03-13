-- ============================================================
-- Migration 018: calorie estimation columns
-- kcal_estimated per set (computed client-side via MET+RPE formula)
-- kcal_total per session  (summed when session is completed)
-- ============================================================

ALTER TABLE public.sets
  ADD COLUMN IF NOT EXISTS kcal_estimated NUMERIC(6,2);

ALTER TABLE public.training_sessions
  ADD COLUMN IF NOT EXISTS kcal_total NUMERIC(8,2);

-- Index for calorie analytics queries (sessions ordered by date with kcal)
CREATE INDEX IF NOT EXISTS training_sessions_user_kcal_idx
  ON public.training_sessions (user_id, date DESC)
  WHERE kcal_total IS NOT NULL;
