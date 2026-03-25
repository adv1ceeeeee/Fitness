-- Add height_cm to profiles for display in edit profile screen
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS height_cm NUMERIC(5,1);
