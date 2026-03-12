-- ============================================================
-- Migration 015: subscription system + user roles
-- Must be done before implementing any paywall logic.
-- ============================================================

-- ── 1. Role + Pro status on profiles ─────────────────────────────────────────
-- role: 'user' | 'trainer' | 'admin'
-- is_pro + pro_expires_at: fast local check (synced from subscriptions)

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS role            TEXT        NOT NULL DEFAULT 'user',
  ADD COLUMN IF NOT EXISTS is_pro          BOOLEAN     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pro_expires_at  TIMESTAMPTZ;

-- ── 2. Subscriptions table ────────────────────────────────────────────────────
-- One row per subscription period. User may have multiple historical rows.
-- App checks profiles.is_pro for speed; this table is the source of truth.

CREATE TABLE IF NOT EXISTS public.subscriptions (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- Plan & status
  plan                    TEXT        NOT NULL,           -- 'monthly' | 'annual' | 'lifetime' | 'trial'
  status                  TEXT        NOT NULL DEFAULT 'active', -- 'active' | 'cancelled' | 'expired' | 'trial'

  -- Payment source
  store                   TEXT        NOT NULL,           -- 'rustore' | 'google_play' | 'app_store' | 'promo'
  store_subscription_id   TEXT,                           -- Store receipt ID for server-side verification
  amount_kopecks          INTEGER     NOT NULL DEFAULT 0, -- 0 for promo/trial; full price in kopecks

  -- Period
  trial_ends_at           TIMESTAMPTZ,
  current_period_start    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  current_period_end      TIMESTAMPTZ,                    -- NULL means lifetime

  -- Lifecycle
  cancelled_at            TIMESTAMPTZ,
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS subscriptions_user_id_idx
  ON public.subscriptions (user_id);
CREATE INDEX IF NOT EXISTS subscriptions_status_idx
  ON public.subscriptions (status)
  WHERE status = 'active';

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- Users can view their own subscriptions; writing is server-only (service_role)
CREATE POLICY "Users can view own subscriptions" ON public.subscriptions
  FOR SELECT USING (auth.uid() = user_id);

CREATE TRIGGER subscriptions_updated_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 3. Function: sync is_pro from subscriptions ───────────────────────────────
-- Called from server-side webhook (RuStore/Google Play receipt validation).
-- Sets profiles.is_pro = true and pro_expires_at when subscription is active.

CREATE OR REPLACE FUNCTION public.sync_pro_status(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_active RECORD;
BEGIN
  -- Find the best active subscription
  SELECT plan, current_period_end
  INTO   v_active
  FROM   public.subscriptions
  WHERE  user_id = p_user_id
    AND  status  = 'active'
    AND  (current_period_end IS NULL OR current_period_end > NOW())
  ORDER BY
    -- lifetime first, then latest period_end
    CASE WHEN plan = 'lifetime' THEN 0 ELSE 1 END,
    current_period_end DESC NULLS FIRST
  LIMIT 1;

  IF FOUND THEN
    UPDATE public.profiles
    SET    is_pro         = true,
           pro_expires_at = v_active.current_period_end,
           updated_at     = NOW()
    WHERE  id = p_user_id;
  ELSE
    -- No active subscription: revoke Pro
    UPDATE public.profiles
    SET    is_pro         = false,
           pro_expires_at = NULL,
           updated_at     = NOW()
    WHERE  id = p_user_id
      AND  is_pro = true;
  END IF;
END;
$$;
