-- ============================================================
-- Migration 035: analysis tables
--   1. personal_records   — append-only PR log, auto-populated by trigger
--   2. weekly_volume      — Postgres VIEW for volume periodization
--   3. push_notification_logs — scheduled notification tracking
--   4. user_goals_history — goal change log, auto-populated by trigger
-- ============================================================

-- ── 1. personal_records ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.personal_records (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  exercise_id UUID        NOT NULL REFERENCES public.exercises(id) ON DELETE CASCADE,
  weight_kg   FLOAT       NOT NULL CHECK (weight_kg > 0),
  reps        INT,
  session_id  UUID        REFERENCES public.training_sessions(id) ON DELETE SET NULL,
  achieved_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS personal_records_user_exercise_idx
  ON public.personal_records (user_id, exercise_id, achieved_at DESC);

ALTER TABLE public.personal_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own personal_records" ON public.personal_records
  FOR ALL USING (auth.uid() = user_id);

-- Trigger: insert a row whenever a completed set exceeds the user's current max weight
CREATE OR REPLACE FUNCTION fn_check_personal_record()
RETURNS TRIGGER AS $$
DECLARE
  v_exercise_id UUID;
  v_user_id     UUID;
  v_current_max FLOAT;
BEGIN
  -- Only process completed, weighted sets
  IF NEW.completed = false OR NEW.weight IS NULL OR NEW.weight <= 0 THEN
    RETURN NEW;
  END IF;

  SELECT exercise_id INTO v_exercise_id
    FROM public.workout_exercises WHERE id = NEW.workout_exercise_id;

  SELECT user_id INTO v_user_id
    FROM public.training_sessions WHERE id = NEW.training_session_id;

  SELECT MAX(weight_kg) INTO v_current_max
    FROM public.personal_records
    WHERE user_id = v_user_id AND exercise_id = v_exercise_id;

  IF v_current_max IS NULL OR NEW.weight > v_current_max THEN
    INSERT INTO public.personal_records
      (user_id, exercise_id, weight_kg, reps, session_id, achieved_at)
    VALUES
      (v_user_id, v_exercise_id, NEW.weight, NEW.reps,
       NEW.training_session_id, COALESCE(NEW.performed_at, NOW()));
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sets_personal_record_check
  AFTER INSERT ON public.sets
  FOR EACH ROW EXECUTE FUNCTION fn_check_personal_record();

-- ── 2. weekly_volume VIEW ─────────────────────────────────────────────────────
-- Aggregates training volume per user / week / muscle group.
-- Query: SELECT * FROM weekly_volume WHERE user_id = $1 ORDER BY week_start DESC;

CREATE OR REPLACE VIEW public.weekly_volume AS
SELECT
  ts.user_id,
  date_trunc('week', ts.date::TIMESTAMPTZ)  AS week_start,
  e.category                                 AS muscle_group,
  COUNT(s.id)                                AS total_sets,
  COALESCE(SUM(s.reps), 0)                  AS total_reps,
  COALESCE(SUM(s.weight * s.reps), 0)       AS total_volume_kg
FROM public.sets s
JOIN public.training_sessions ts ON ts.id = s.training_session_id
JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
JOIN public.exercises e          ON e.id  = we.exercise_id
WHERE s.completed = true
  AND s.weight IS NOT NULL
GROUP BY ts.user_id, week_start, e.category;

-- ── 3. push_notification_logs ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.push_notification_logs (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  notif_type    TEXT        NOT NULL,    -- 'workout_reminder' | 'session' | 'inactivity' | 'weigh_in' | 'rest_day'
  notif_id      INT         NOT NULL,    -- OS notification id
  scheduled_for TIMESTAMPTZ,            -- NULL for recurring weekly notifications
  session_id    UUID        REFERENCES public.training_sessions(id) ON DELETE SET NULL,
  tapped_at     TIMESTAMPTZ,            -- set when user taps notification
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS push_notif_logs_user_idx
  ON public.push_notification_logs (user_id, created_at DESC);

ALTER TABLE public.push_notification_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own notif logs" ON public.push_notification_logs
  FOR ALL USING (auth.uid() = user_id);

-- ── 4. user_goals_history ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.user_goals_history (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  goal       TEXT        NOT NULL,
  changed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS user_goals_history_user_idx
  ON public.user_goals_history (user_id, changed_at DESC);

ALTER TABLE public.user_goals_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own goals history" ON public.user_goals_history
  FOR ALL USING (auth.uid() = user_id);

-- Trigger: capture every goal change automatically (no Flutter code needed)
CREATE OR REPLACE FUNCTION fn_log_goal_change()
RETURNS TRIGGER AS $$
BEGIN
  IF (OLD.goal IS DISTINCT FROM NEW.goal) AND NEW.goal IS NOT NULL THEN
    INSERT INTO public.user_goals_history (user_id, goal, changed_at)
    VALUES (NEW.id, NEW.goal, NOW());
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_goal_change
  AFTER UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION fn_log_goal_change();
