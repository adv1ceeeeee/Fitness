-- Migration 063: onboarding funnel analysis view.
--
-- Counts distinct users that reached each step of onboarding plus the two
-- terminal states (completed / skipped). Use it to spot where new users
-- drop off — typical pattern is biggest drop between the metrics page
-- (step 0) and the goal page (step 1).
--
-- Events expected (logged via EventLogger.onboardingStepViewed):
--   'onboarding_step_viewed' with props->>'step' in {'0','1','2','3'}
--   'onboarding_completed'
--   'onboarding_skipped'
--
-- Example query:
--   SELECT * FROM onboarding_funnel;
--
-- Drop and recreate so changes to the view are easy to apply via this file.
DROP VIEW IF EXISTS public.onboarding_funnel;

CREATE VIEW public.onboarding_funnel AS
WITH steps AS (
  SELECT
    user_id,
    (props->>'step')::int AS step,
    created_at
  FROM public.user_events
  WHERE event = 'onboarding_step_viewed'
    AND props ? 'step'
),
per_step AS (
  SELECT step, COUNT(DISTINCT user_id) AS users
  FROM steps
  GROUP BY step
),
terminal AS (
  SELECT
    event,
    COUNT(DISTINCT user_id) AS users
  FROM public.user_events
  WHERE event IN ('onboarding_completed', 'onboarding_skipped')
  GROUP BY event
),
combined AS (
  SELECT
    CASE step
      WHEN 0 THEN '0. Метрики (пол / возраст / вес / рост)'
      WHEN 1 THEN '1. Цель тренировок'
      WHEN 2 THEN '2. Уровень подготовки'
      WHEN 3 THEN '3. Настройки веса / единиц'
      ELSE step::text
    END AS step_label,
    step AS sort_key,
    users
  FROM per_step
  UNION ALL
  SELECT 'COMPLETED', 10, users FROM terminal WHERE event = 'onboarding_completed'
  UNION ALL
  SELECT 'SKIPPED',   11, users FROM terminal WHERE event = 'onboarding_skipped'
)
SELECT
  step_label,
  users,
  -- Drop-off vs the previous step (NULL for the first row).
  users::float /
    NULLIF(LAG(users) OVER (ORDER BY sort_key), 0) AS retention_vs_prev
FROM combined
ORDER BY sort_key;

-- Hand the view to authenticated users so we can query it from the app
-- (or Supabase Studio) without needing service-role.
GRANT SELECT ON public.onboarding_funnel TO authenticated;
