-- Migration 040: add gif_url to exercises, create exercise-gifs storage bucket

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS gif_url TEXT;

-- Public read-only bucket for exercise GIFs
INSERT INTO storage.buckets (id, name, public)
VALUES ('exercise-gifs', 'exercise-gifs', true)
ON CONFLICT (id) DO NOTHING;

-- Allow anyone to read (public bucket)
CREATE POLICY IF NOT EXISTS "exercise_gifs_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'exercise-gifs');
