-- ─── Community average RPC functions ─────────────────────────────────────────
--
-- These functions run with SECURITY DEFINER so they bypass RLS and can
-- compute aggregates across all users. Only anonymised (avg) values are
-- returned — individual user data is never exposed.

-- Average of each user's all-time max weight for a given exercise.
-- Returns NULL if no one has logged this exercise yet.
CREATE OR REPLACE FUNCTION public.get_community_avg_exercise_weight(
  p_exercise_id UUID
)
RETURNS NUMERIC
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  WITH user_max AS (
    SELECT ts.user_id,
           MAX(s.weight) AS max_weight
    FROM   sets s
    JOIN   workout_exercises we ON we.id = s.workout_exercise_id
    JOIN   training_sessions ts ON ts.id = s.training_session_id
    WHERE  we.exercise_id = p_exercise_id
      AND  s.completed   = true
      AND  s.weight      IS NOT NULL
      AND  ts.completed  = true
    GROUP BY ts.user_id
  )
  SELECT ROUND(AVG(max_weight)::NUMERIC, 1)
  FROM   user_max;
$$;

GRANT EXECUTE ON FUNCTION public.get_community_avg_exercise_weight(UUID)
  TO authenticated;

-- Average weekly volume (kg × reps) per user over the last 8 weeks,
-- then averaged across users. Returns NULL if no data.
CREATE OR REPLACE FUNCTION public.get_community_avg_weekly_volume()
RETURNS NUMERIC
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  WITH user_weekly AS (
    SELECT ts.user_id,
           DATE_TRUNC('week', ts.date::DATE) AS week_start,
           SUM(s.weight * s.reps)            AS week_volume
    FROM   sets s
    JOIN   training_sessions ts ON ts.id = s.training_session_id
    WHERE  s.completed  = true
      AND  s.weight     IS NOT NULL
      AND  ts.completed = true
      AND  ts.date::DATE >= CURRENT_DATE - INTERVAL '56 days'
    GROUP BY ts.user_id, DATE_TRUNC('week', ts.date::DATE)
  ),
  user_avg AS (
    SELECT user_id,
           AVG(week_volume) AS avg_vol
    FROM   user_weekly
    GROUP BY user_id
  )
  SELECT ROUND(AVG(avg_vol)::NUMERIC, 1)
  FROM   user_avg;
$$;

GRANT EXECUTE ON FUNCTION public.get_community_avg_weekly_volume()
  TO authenticated;
