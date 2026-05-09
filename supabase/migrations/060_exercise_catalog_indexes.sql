-- Migration 060: speed up exercise catalog loading on mobile clients.
-- The app mostly asks for standard exercises plus the current user's custom
-- exercises, ordered by name, so these indexes keep that path cheap.

CREATE INDEX IF NOT EXISTS idx_exercises_standard_name
  ON public.exercises (name)
  WHERE is_standard = true;

CREATE INDEX IF NOT EXISTS idx_exercises_user_name
  ON public.exercises (user_id, name)
  WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_exercises_category_name
  ON public.exercises (category, name);
