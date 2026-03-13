-- Feature: is_warmup flag on individual sets
ALTER TABLE public.sets
  ADD COLUMN IF NOT EXISTS is_warmup BOOLEAN NOT NULL DEFAULT false;

-- Feature: pre-computed volume (non-warmup kg×reps) stored on session completion
ALTER TABLE public.training_sessions
  ADD COLUMN IF NOT EXISTS volume_kg NUMERIC(10,2);
