-- User-specific favorites for exercises
CREATE TABLE IF NOT EXISTS public.user_favorite_exercises (
  user_id     UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  exercise_id UUID REFERENCES public.exercises(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, exercise_id)
);

ALTER TABLE public.user_favorite_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own favorites"
  ON public.user_favorite_exercises
  FOR ALL USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS user_favorites_user_idx
  ON public.user_favorite_exercises (user_id);
