-- 048: Transactional RPCs for session completion and deletion
-- Wraps multi-step operations in a single BEGIN/COMMIT to guarantee atomicity.

-- ── fn_complete_session ──────────────────────────────────────────────────────
-- Marks a session complete and calculates kcal_total + volume_kg from its sets
-- in one atomic transaction. Replaces three separate app-level calls.
CREATE OR REPLACE FUNCTION fn_complete_session(
  p_session_id      uuid,
  p_duration_seconds int  DEFAULT NULL,
  p_notes           text  DEFAULT NULL,
  p_session_rpe     int   DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    uuid    := auth.uid();
  v_volume_kg  numeric;
  v_kcal_total numeric;
BEGIN
  -- Verify ownership
  IF NOT EXISTS (
    SELECT 1 FROM training_sessions
    WHERE id = p_session_id AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'session not found or not owned by current user';
  END IF;

  -- Sanitise inputs (mirrors app-level validation)
  p_session_rpe     := CASE WHEN p_session_rpe IS NOT NULL
                            THEN GREATEST(1, LEAST(10, p_session_rpe))
                            ELSE NULL END;
  p_notes           := CASE WHEN p_notes IS NOT NULL
                            THEN LEFT(p_notes, 1000)
                            ELSE NULL END;
  p_duration_seconds := CASE WHEN p_duration_seconds IS NOT NULL AND p_duration_seconds < 0
                             THEN 0
                             ELSE p_duration_seconds END;

  -- Aggregate kcal from ALL completed sets (including warmups)
  SELECT ROUND(COALESCE(SUM(kcal_estimated), 0)::numeric, 1)
  INTO   v_kcal_total
  FROM   sets
  WHERE  training_session_id = p_session_id
    AND  completed = true;

  -- Aggregate volume from non-warmup completed sets only
  SELECT ROUND(COALESCE(SUM(COALESCE(weight, 0) * COALESCE(reps, 0)), 0)::numeric, 2)
  INTO   v_volume_kg
  FROM   sets
  WHERE  training_session_id = p_session_id
    AND  completed = true
    AND  is_warmup = false;

  -- Single atomic UPDATE
  UPDATE training_sessions SET
    completed        = true,
    duration_seconds = COALESCE(p_duration_seconds, duration_seconds),
    notes            = p_notes,
    session_rpe      = COALESCE(p_session_rpe, session_rpe),
    kcal_total       = CASE WHEN v_kcal_total > 0 THEN v_kcal_total ELSE kcal_total END,
    volume_kg        = CASE WHEN v_volume_kg  > 0 THEN v_volume_kg  ELSE volume_kg  END
  WHERE id = p_session_id AND user_id = v_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_complete_session(uuid, int, text, int) TO authenticated;


-- ── fn_delete_session ────────────────────────────────────────────────────────
-- Deletes a session and all its sets atomically.
-- Verifies ownership before touching any rows.
CREATE OR REPLACE FUNCTION fn_delete_session(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  -- Verify ownership first
  IF NOT EXISTS (
    SELECT 1 FROM training_sessions
    WHERE id = p_session_id AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'session not found or not owned by current user';
  END IF;

  DELETE FROM sets              WHERE training_session_id = p_session_id;
  DELETE FROM training_sessions WHERE id = p_session_id AND user_id = v_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_delete_session(uuid) TO authenticated;
