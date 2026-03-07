-- ============================================================
-- Migration 009: body_metrics, wellness_logs, user_events,
--                + missing columns on existing tables
-- ============================================================

-- ── 1. training_start_date on profiles ──────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS training_start_date DATE;

-- ── 2. duration_seconds on training_sessions ────────────────────────────────
ALTER TABLE public.training_sessions
  ADD COLUMN IF NOT EXISTS duration_seconds INT;

-- ── 3. rest_seconds on sets ─────────────────────────────────────────────────
ALTER TABLE public.sets
  ADD COLUMN IF NOT EXISTS rest_seconds INT;

-- ── 4. body_metrics ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.body_metrics (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  date            DATE NOT NULL,

  -- Core
  weight_kg       FLOAT,
  body_fat_pct    FLOAT,

  -- Circumferences (cm)
  neck_cm         FLOAT,
  shoulders_cm    FLOAT,
  chest_cm        FLOAT,
  waist_cm        FLOAT,
  right_arm_cm    FLOAT,
  left_arm_cm     FLOAT,
  right_forearm_cm FLOAT,
  left_forearm_cm  FLOAT,
  hips_cm         FLOAT,
  right_thigh_cm  FLOAT,
  left_thigh_cm   FLOAT,
  right_calf_cm   FLOAT,
  left_calf_cm    FLOAT,

  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (user_id, date)
);

ALTER TABLE public.body_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own body_metrics" ON public.body_metrics
  FOR ALL USING (auth.uid() = user_id);

CREATE TRIGGER body_metrics_updated_at
  BEFORE UPDATE ON public.body_metrics
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 5. wellness_logs ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.wellness_logs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  date        DATE NOT NULL,

  sleep_hours FLOAT   CHECK (sleep_hours >= 0 AND sleep_hours <= 24),
  stress      INT     CHECK (stress >= 1 AND stress <= 10),
  energy      INT     CHECK (energy >= 1 AND energy <= 10),

  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (user_id, date)
);

ALTER TABLE public.wellness_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own wellness_logs" ON public.wellness_logs
  FOR ALL USING (auth.uid() = user_id);

CREATE TRIGGER wellness_logs_updated_at
  BEFORE UPDATE ON public.wellness_logs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 6. user_events ──────────────────────────────────────────────────────────
-- Append-only event stream for analytics / funnel tracking.
CREATE TABLE IF NOT EXISTS public.user_events (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event      TEXT NOT NULL,
  props      JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS user_events_user_id_idx  ON public.user_events (user_id);
CREATE INDEX IF NOT EXISTS user_events_event_idx     ON public.user_events (event);
CREATE INDEX IF NOT EXISTS user_events_created_at_idx ON public.user_events (created_at DESC);

ALTER TABLE public.user_events ENABLE ROW LEVEL SECURITY;

-- Users can insert their own events; only service-role can SELECT (analytics backend)
CREATE POLICY "Users can insert own events" ON public.user_events
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view own events" ON public.user_events
  FOR SELECT USING (auth.uid() = user_id);
