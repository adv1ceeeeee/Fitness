-- Migration 046: Server-side push notification cron
--
-- Prerequisites (run once in Supabase SQL editor):
--
--   1. Store the Edge Function URL base in app_config:
--        INSERT INTO app_config (key, value)
--        VALUES ('functions_url', 'https://<YOUR_PROJECT_REF>.supabase.co/functions/v1')
--        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
--
--   2. Store the service role key as a Postgres parameter:
--        ALTER DATABASE postgres
--          SET "app.service_role_key" TO '<YOUR_SERVICE_ROLE_KEY>';
--      (Dashboard → Settings → API → service_role key)
--
--   3. Set FCM secrets in Dashboard → Settings → Edge Functions → Secrets:
--        FCM_SERVICE_ACCOUNT = <full service account JSON>
--        FCM_PROJECT_ID      = <firebase project id>

-- Enable required extensions (idempotent)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Remove existing schedule if re-running migration
SELECT cron.unschedule('send-push-notifications')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'send-push-notifications'
);

-- Schedule: call send-push Edge Function every 15 minutes
SELECT cron.schedule(
  'send-push-notifications',
  '*/15 * * * *',
  $$
  SELECT net.http_post(
    url     := (SELECT value FROM app_config WHERE key = 'functions_url')
               || '/send-push',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
    ),
    body    := '{}'::jsonb
  );
  $$
);
