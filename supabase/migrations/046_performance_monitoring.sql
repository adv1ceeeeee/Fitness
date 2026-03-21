-- Migration 046: performance monitoring
--
-- 1. Enable pg_stat_statements (tracks slow queries)
-- 2. Create slow_query_log view for easy inspection
-- 3. Add missing indexes identified from query patterns

-- ── 1. pg_stat_statements ─────────────────────────────────────────────────────
-- Already enabled by default on Supabase. Reset stats on each migration run.
SELECT pg_stat_statements_reset();

-- ── 2. Slow query view ────────────────────────────────────────────────────────
-- Shows top 20 slowest queries. Query via Supabase SQL Editor.
-- Usage: SELECT * FROM slow_queries;
CREATE OR REPLACE VIEW public.slow_queries AS
SELECT
  ROUND(mean_exec_time::numeric, 2)          AS avg_ms,
  ROUND(max_exec_time::numeric, 2)           AS max_ms,
  calls,
  ROUND(total_exec_time::numeric / 1000, 2)  AS total_seconds,
  ROUND(rows::numeric / NULLIF(calls, 0), 1) AS avg_rows,
  LEFT(query, 120)                           AS query_preview
FROM pg_stat_statements
WHERE userid = (SELECT oid FROM pg_roles WHERE rolname = 'authenticator')
  AND calls > 5
  AND mean_exec_time > 50  -- slower than 50ms
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Only superuser/postgres can query pg_stat_statements directly.
-- This view is intentionally not exposed via RLS (admin use only).

-- ── 3. Missing indexes ────────────────────────────────────────────────────────

-- user_events: most queries filter by user_id + event + created_at
CREATE INDEX IF NOT EXISTS user_events_user_event_idx
  ON public.user_events (user_id, event, created_at DESC);

-- sets: frequently joined via training_session_id and filtered by completed
CREATE INDEX IF NOT EXISTS sets_session_completed_idx
  ON public.sets (training_session_id, completed);

-- sets: time-based queries (performed_at used in analytics)
CREATE INDEX IF NOT EXISTS sets_performed_at_idx
  ON public.sets (performed_at DESC);

-- training_sessions: filter by user + date range (calendar, analytics)
CREATE INDEX IF NOT EXISTS training_sessions_user_date_idx
  ON public.training_sessions (user_id, date DESC);

-- training_sessions: completed sessions only (most analytics queries)
CREATE INDEX IF NOT EXISTS training_sessions_user_completed_idx
  ON public.training_sessions (user_id, completed);

-- body_metrics: time-series queries by user
CREATE INDEX IF NOT EXISTS body_metrics_user_date_idx
  ON public.body_metrics (user_id, date DESC);

-- wellness_logs: daily check-in lookups
CREATE INDEX IF NOT EXISTS wellness_logs_user_date_idx
  ON public.wellness_logs (user_id, date DESC);

-- personal_records: lookup by user + exercise
CREATE INDEX IF NOT EXISTS personal_records_user_exercise_idx
  ON public.personal_records (user_id, exercise_id, achieved_at DESC);

-- feedback: admin queries by category + date
CREATE INDEX IF NOT EXISTS feedback_category_created_idx
  ON public.feedback (category, created_at DESC);
