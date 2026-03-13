-- Update get_community_avg_exercise_weight to filter by last 7 days
-- instead of all-time, so it matches the exercise progress chart window.

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
      AND  s.completed    = true
      AND  s.weight       IS NOT NULL
      AND  ts.completed   = true
      AND  ts.date::DATE >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY ts.user_id
  )
  SELECT ROUND(AVG(max_weight)::NUMERIC, 1)
  FROM   user_max;
$$;

GRANT EXECUTE ON FUNCTION public.get_community_avg_exercise_weight(UUID)
  TO authenticated;
