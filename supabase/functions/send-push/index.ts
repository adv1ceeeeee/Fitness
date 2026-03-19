// Edge Function: send-push
// Sends FCM push notifications for 3 scenarios:
//   1. upcoming_workout  — planned_time is 15–45 min from now
//   2. missed_workout    — planned_time was 2+ hours ago, session not completed
//   3. inactivity_7d     — no completed session in the last 7 days
//
// Deploy:  supabase functions deploy send-push
//
// Required secrets (Dashboard → Settings → Edge Functions → Secrets):
//   FCM_SERVICE_ACCOUNT  — full service account JSON from Firebase Console
//                          (Project Settings → Service Accounts → Generate key)
//   FCM_PROJECT_ID       — Firebase project ID (e.g. "sportwai-12345")
//
// Invoked by pg_cron every 15 minutes (see migration 046_push_cron.sql).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// ─── FCM auth (RS256 JWT → OAuth2 access token) ───────────────────────────────

async function getFcmAccessToken(): Promise<string> {
  const sa = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT')!);
  const now = Math.floor(Date.now() / 1000);

  const header  = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64url(JSON.stringify({
    iss:   sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud:   'https://oauth2.googleapis.com/token',
    exp:   now + 3600,
    iat:   now,
  }));

  const signingInput = `${header}.${payload}`;

  const keyData = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\n/g, '');
  const binaryKey = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8', binaryKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  );

  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${b64url(sig)}`;

  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const json = await resp.json();
  if (!json.access_token) throw new Error(`OAuth2 error: ${JSON.stringify(json)}`);
  return json.access_token;
}

function b64url(input: string | ArrayBuffer): string {
  const str = typeof input === 'string'
    ? btoa(unescape(encodeURIComponent(input)))
    : btoa(String.fromCharCode(...new Uint8Array(input)));
  return str.replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

// ─── FCM send ─────────────────────────────────────────────────────────────────

async function sendFcm(
  token: string,
  title: string,
  body: string,
  data: Record<string, string> = {},
): Promise<boolean> {
  const projectId   = Deno.env.get('FCM_PROJECT_ID')!;
  const accessToken = await getFcmAccessToken();

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization:  `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: { priority: 'high' },
          apns:    { payload: { aps: { sound: 'default' } } },
        },
      }),
    },
  );

  if (!resp.ok) {
    const err = await resp.text();
    // Token invalid / unregistered — clean it up
    if (err.includes('UNREGISTERED') || err.includes('INVALID_ARGUMENT')) {
      await supabase.from('device_tokens').delete().eq('token', token);
    } else {
      console.error(`[FCM] send failed for ${token.slice(0, 12)}…: ${err}`);
    }
  }
  return resp.ok;
}

// ─── Dedup helpers ────────────────────────────────────────────────────────────

async function alreadyNotified(
  userId: string,
  type: string,
  withinHours: number,
): Promise<boolean> {
  const since = new Date(Date.now() - withinHours * 3_600_000).toISOString();
  const { data } = await supabase
    .from('push_notification_logs')
    .select('id')
    .eq('user_id', userId)
    .eq('notif_type', type)
    .gte('scheduled_for', since)
    .limit(1);
  return (data?.length ?? 0) > 0;
}

async function logSent(userId: string, type: string): Promise<void> {
  await supabase.from('push_notification_logs').insert({
    user_id:       userId,
    notif_type:    type,
    scheduled_for: new Date().toISOString(),
  });
}

async function getTokens(userId: string): Promise<string[]> {
  const { data } = await supabase
    .from('device_tokens')
    .select('token')
    .eq('user_id', userId);
  return (data ?? []).map((r: { token: string }) => r.token);
}

// ─── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async () => {
  try {
    const now     = new Date();
    const results = { upcoming: 0, missed: 0, inactive: 0 };

    // ── 1. Upcoming workout (session starts in 15–45 min) ──────────────────
    const winStart = new Date(now.getTime() + 15 * 60_000).toISOString();
    const winEnd   = new Date(now.getTime() + 45 * 60_000).toISOString();

    const { data: upcoming } = await supabase
      .from('training_sessions')
      .select('id, user_id, workouts!inner(name)')
      .gte('planned_time', winStart)
      .lte('planned_time', winEnd)
      .eq('completed', false)
      .not('planned_time', 'is', null);

    for (const s of upcoming ?? []) {
      if (await alreadyNotified(s.user_id, 'upcoming_workout', 12)) continue;
      const tokens = await getTokens(s.user_id);
      for (const t of tokens) {
        await sendFcm(t,
          '⏱ Тренировка скоро',
          `«${s.workouts.name}» начнётся через ~30 минут`,
          { type: 'upcoming_workout', session_id: s.id },
        );
      }
      if (tokens.length) { await logSent(s.user_id, 'upcoming_workout'); results.upcoming++; }
    }

    // ── 2. Missed workout (2+ hours overdue, still not done) ───────────────
    const todayStart  = new Date(now.toDateString()).toISOString();
    const twoHoursAgo = new Date(now.getTime() - 2 * 3_600_000).toISOString();

    const { data: missed } = await supabase
      .from('training_sessions')
      .select('id, user_id, workouts!inner(name)')
      .gte('planned_time', todayStart)
      .lte('planned_time', twoHoursAgo)
      .eq('completed', false)
      .not('planned_time', 'is', null);

    for (const s of missed ?? []) {
      if (await alreadyNotified(s.user_id, 'missed_workout', 20)) continue;
      const tokens = await getTokens(s.user_id);
      for (const t of tokens) {
        await sendFcm(t,
          '🤔 Пропустил тренировку?',
          `Ещё не поздно сделать «${s.workouts.name}»`,
          { type: 'missed_workout', session_id: s.id },
        );
      }
      if (tokens.length) { await logSent(s.user_id, 'missed_workout'); results.missed++; }
    }

    // ── 3. Inactivity — no completed session in 7 days ─────────────────────
    const sevenDaysAgo = new Date(now.getTime() - 7 * 86_400_000)
      .toISOString().slice(0, 10); // date only

    // Users who have a device token but no completed session in the last 7 days
    const { data: inactiveTokens } = await supabase
      .from('device_tokens')
      .select('user_id, token')
      .not('user_id', 'in',
        // subquery-style: users with a recent completed session
        `(${
          (await supabase
            .from('training_sessions')
            .select('user_id')
            .eq('completed', true)
            .gte('date', sevenDaysAgo)
          ).data?.map((r: { user_id: string }) => `"${r.user_id}"`).join(',') ?? '""'
        })`,
      );

    const seenUsers = new Set<string>();
    for (const row of inactiveTokens ?? []) {
      if (seenUsers.has(row.user_id)) continue;
      if (await alreadyNotified(row.user_id, 'inactivity_7d', 7 * 24)) continue;
      seenUsers.add(row.user_id);

      const tokens = await getTokens(row.user_id);
      for (const t of tokens) {
        await sendFcm(t,
          '💪 Давно не виделись!',
          'Самое время вернуться к тренировкам — прогресс ждёт',
          { type: 'inactivity_7d' },
        );
      }
      if (tokens.length) { await logSent(row.user_id, 'inactivity_7d'); results.inactive++; }
    }

    return new Response(JSON.stringify({ ok: true, ...results }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('[send-push]', e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
