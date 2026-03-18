// Edge Function: suggest-city
// Proxies DaData city suggestions so the API key stays server-side.
//
// Deploy: supabase functions deploy suggest-city
// Required secret (Supabase Dashboard → Settings → Edge Functions → Secrets):
//   DADATA_API_KEY — your DaData API key
//
// Flutter calls: POST /functions/v1/suggest-city  { "query": "Моск" }
// Returns DaData response body as-is.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // Require authenticated user
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const dadataKey = Deno.env.get('DADATA_API_KEY');
  if (!dadataKey) {
    return new Response(JSON.stringify({ error: 'Server misconfigured' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const { query } = await req.json();
  if (!query || typeof query !== 'string') {
    return new Response(JSON.stringify({ error: 'Missing query' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const resp = await fetch(
    'https://suggestions.dadata.ru/suggestions/api/4_1/rs/suggest/city',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Token ${dadataKey}`,
      },
      body: JSON.stringify({ query, count: 10 }),
    },
  );

  const data = await resp.json();
  return new Response(JSON.stringify(data), {
    status: resp.status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
