-- Migration 062: per-user device profiles.
--
-- One row per (user, physical device) so support can answer "what's broken
-- for this user" in seconds and product can slice DAU / churn by platform
-- and OS version. Upserted by DeviceProfileService.upsertOnAppStart on
-- every cold start; stale rows naturally fall behind via last_seen_at.
--
-- Privacy note: nothing here is a "raw" identifier — device_id is the
-- platform-vendor id (Android ID / IDFV / Windows deviceId), tied to the
-- app install on that device. No IMEI / MAC / advertising id.

CREATE TABLE IF NOT EXISTS public.user_devices (
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  device_id     TEXT NOT NULL,
  platform      TEXT NOT NULL,       -- 'ios' | 'android' | 'windows' | 'macos' | 'linux' | 'web'
  os_version    TEXT,                -- e.g. '14.2' (iOS), '14' (Android), '11' (Windows)
  device_model  TEXT,                -- e.g. 'iPhone 15 Pro', 'Pixel 7'
  manufacturer  TEXT,                -- e.g. 'Apple', 'Samsung', 'Xiaomi'
  app_version   TEXT,                -- '1.9.0+47'
  locale        TEXT,                -- 'ru_RU', 'en_US'
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_user_devices_user
  ON public.user_devices (user_id);

CREATE INDEX IF NOT EXISTS idx_user_devices_last_seen
  ON public.user_devices (last_seen_at DESC);

ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own devices"
  ON public.user_devices
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
