-- Add user_id to exercises table to support custom user-created exercises.
-- Standard exercises (is_standard = true) have user_id = null.
-- User exercises have user_id set to the creator's auth.users id.

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- Drop existing policies and recreate with user exercise support
DROP POLICY IF EXISTS "exercises_select" ON exercises;
DROP POLICY IF EXISTS "exercises_insert" ON exercises;
DROP POLICY IF EXISTS "exercises_update" ON exercises;
DROP POLICY IF EXISTS "exercises_delete" ON exercises;

-- Anyone can read standard exercises + their own custom exercises
CREATE POLICY "exercises_select" ON exercises
  FOR SELECT USING (is_standard = true OR user_id = auth.uid());

-- Users can insert their own exercises (not standard)
CREATE POLICY "exercises_insert" ON exercises
  FOR INSERT WITH CHECK (is_standard = false AND user_id = auth.uid());

-- Users can update only their own custom exercises
CREATE POLICY "exercises_update" ON exercises
  FOR UPDATE USING (user_id = auth.uid() AND is_standard = false);

-- Users can delete only their own custom exercises
CREATE POLICY "exercises_delete" ON exercises
  FOR DELETE USING (user_id = auth.uid() AND is_standard = false);
