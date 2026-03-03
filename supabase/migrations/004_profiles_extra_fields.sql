-- SportWAI: extra profile fields for registration/login

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS first_name TEXT,
  ADD COLUMN IF NOT EXISTS last_name TEXT,
  ADD COLUMN IF NOT EXISTS birth_date DATE,
  ADD COLUMN IF NOT EXISTS nickname TEXT;

-- Nickname should be unique (login by nickname)
CREATE UNIQUE INDEX IF NOT EXISTS profiles_nickname_unique
  ON public.profiles (lower(nickname))
  WHERE nickname IS NOT NULL;

