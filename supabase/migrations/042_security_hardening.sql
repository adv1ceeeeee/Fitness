-- ============================================================
-- Migration 042: security hardening
--
-- 1. weekly_volume VIEW — add security_invoker so RLS applies
--    (previously any authenticated user could query other users' volume)
-- 2. app_config — restrict to authenticated users only
--    (previously anon key could read min_version etc.)
-- ============================================================


-- ── 1. weekly_volume VIEW — security_invoker ──────────────────────────────────
-- PostgreSQL views run as owner (security-definer) by default,
-- bypassing RLS on underlying tables. With security_invoker = on,
-- the view runs as the calling user — RLS on training_sessions and sets
-- applies normally, so users can only see their own data.

CREATE OR REPLACE VIEW public.weekly_volume
WITH (security_invoker = on)
AS
SELECT
  ts.user_id,
  date_trunc('week', ts.date::TIMESTAMPTZ)             AS week_start,
  e.category                                            AS muscle_group,
  COUNT(s.id)                                           AS total_sets,
  COALESCE(SUM(s.reps), 0)                             AS total_reps,
  COALESCE(SUM(
    CASE
      WHEN s.weight IS NOT NULL AND s.reps IS NOT NULL
        THEN s.weight * s.reps
      ELSE 0
    END
  ), 0)                                                 AS total_volume_kg
FROM public.sets s
JOIN public.training_sessions ts ON ts.id = s.training_session_id
JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
JOIN public.exercises e          ON e.id  = we.exercise_id
WHERE s.completed = true
GROUP BY ts.user_id, week_start, e.category;


-- ── 2. app_config — require authenticated role ────────────────────────────────
-- Before: "app_config readable by all" allows anon requests (no auth needed).
-- After:  only authenticated users can read config values.
-- This prevents unauthenticated clients from reading store URLs / min_version.

DROP POLICY IF EXISTS "app_config readable by all" ON public.app_config;

CREATE POLICY "app_config readable by authenticated"
  ON public.app_config FOR SELECT
  TO authenticated
  USING (true);
