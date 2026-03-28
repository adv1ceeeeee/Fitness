// Edge Function: login-by-nickname
//
// Accepts { nickname, password } and returns a Supabase auth session.
// The email lookup happens server-side using the service_role key so the
// email address is never exposed to the client — fixes the anon email
// enumeration vulnerability in get_email_by_nickname.
//
// Deploy: supabase functions deploy login-by-nickname
//
// Migration 049 revokes EXECUTE on get_email_by_nickname FROM anon,
// so this function becomes the only way to log in by nickname.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON_KEY          = Deno.env.get('SUPABASE_ANON_KEY')!;

// Service-role client — used only for the internal nickname→email lookup.
const serviceClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: CORS_HEADERS });
  }

  // Parse body
  let nickname: string | undefined;
  let password: string | undefined;
  try {
    const body = await req.json();
    nickname = typeof body.nickname === 'string' ? body.nickname.trim() : undefined;
    password = typeof body.password === 'string' ? body.password : undefined;
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }

  if (!nickname || !password) {
    return json({ error: 'nickname and password are required' }, 400);
  }

  // Look up email server-side — never exposed to client
  const { data: email, error: lookupError } = await serviceClient.rpc(
    'get_email_by_nickname',
    { p_nickname: nickname },
  );

  if (lookupError || !email) {
    // Return generic error: don't reveal whether the nickname exists
    return json({ error: 'Invalid credentials' }, 401);
  }

  // Sign in via Supabase Auth REST API using anon key
  const authRes = await fetch(
    `${SUPABASE_URL}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': ANON_KEY,
      },
      body: JSON.stringify({ email, password }),
    },
  );

  const authData = await authRes.json();

  if (!authRes.ok) {
    // Forward auth errors as generic "invalid credentials"
    return json({ error: 'Invalid credentials' }, 401);
  }

  return json(authData, 200);
});

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}
