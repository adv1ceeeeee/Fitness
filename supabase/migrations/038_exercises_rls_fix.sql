-- ============================================================
-- Migration 038: fix exercises RLS broken by migration 037
--
-- Migration 037 incorrectly overwrote the correct RLS policies
-- from migration 012 (which added user_id to exercises).
--
-- Correct model:
--   - Standard exercises (is_standard = true, user_id = NULL):
--       readable by everyone, never editable or deletable by users.
--   - Custom exercises (is_standard = false, user_id = auth.uid()):
--       readable only by the creator, editable and soft-deletable only by the creator.
-- ============================================================

-- ── 1. Fix exercises_select ───────────────────────────────────────────────────
-- 037 created: FOR SELECT USING (deleted_at IS NULL)
--   → wrong: hides user's own custom exercises from other users (correct),
--            but also hides standard exercises that might get deleted_at set by mistake.
-- 012 had: FOR SELECT USING (is_standard = true OR user_id = auth.uid())
--   → correct ownership, but didn't account for soft deletes yet.
-- Combined correct logic: (standard OR own) AND not soft-deleted.

DROP POLICY IF EXISTS "exercises_select"     ON public.exercises;
DROP POLICY IF EXISTS "Exercises are viewable by all" ON public.exercises;

CREATE POLICY "exercises_select" ON public.exercises
  FOR SELECT USING (
    (is_standard = true OR user_id = auth.uid())
    AND deleted_at IS NULL
  );


-- ── 2. Remove incorrect exercises_update_own from 037 ────────────────────────
-- 037 added a broad UPDATE policy based on workout ownership (incorrect proxy).
-- 012 already has the correct UPDATE policy: user_id = auth.uid() AND is_standard = false.
-- Users can update any field of their own custom exercises — that's intentional.

DROP POLICY IF EXISTS "exercises_update_own" ON public.exercises;

-- Ensure the correct update policy from 012 exists (idempotent).
DROP POLICY IF EXISTS "exercises_update"     ON public.exercises;

CREATE POLICY "exercises_update" ON public.exercises
  FOR UPDATE USING (user_id = auth.uid() AND is_standard = false);


-- ── 3. Replace hard DELETE with soft delete via SECURITY DEFINER RPC ──────────
-- Direct DELETE by users is now forbidden.
-- Instead, users call soft_delete_exercise(exercise_id) which only sets deleted_at.
-- This guarantees:
--   a) Only the owner can delete their exercise.
--   b) Only deleted_at is touched — no other fields can be modified this way.
--   c) The exercise (and its historical sets) remain in the DB.

DROP POLICY IF EXISTS "exercises_delete" ON public.exercises;

CREATE POLICY "exercises_delete" ON public.exercises
  FOR DELETE USING (false); -- hard DELETE forbidden for all users

CREATE OR REPLACE FUNCTION public.soft_delete_exercise(p_exercise_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.exercises
  SET deleted_at = NOW()
  WHERE id           = p_exercise_id
    AND user_id      = auth.uid()   -- only the creator
    AND is_standard  = false        -- never touch standard exercises
    AND deleted_at   IS NULL;       -- idempotent

  IF NOT FOUND THEN
    RAISE EXCEPTION 'exercise not found or not owned by current user';
  END IF;
END;
$$;

-- Grant execute to authenticated users
REVOKE ALL ON FUNCTION public.soft_delete_exercise(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_exercise(UUID) TO authenticated;


-- ── 4. Restore exercises_insert (idempotent) ──────────────────────────────────
DROP POLICY IF EXISTS "exercises_insert" ON public.exercises;

CREATE POLICY "exercises_insert" ON public.exercises
  FOR INSERT WITH CHECK (is_standard = false AND user_id = auth.uid());
