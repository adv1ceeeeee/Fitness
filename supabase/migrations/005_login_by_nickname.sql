-- SportWAI: login helper to map nickname -> email
-- WARNING (MVP): this enables email lookup by nickname.
-- Consider rate limiting / captcha / edge function in production.

CREATE OR REPLACE FUNCTION public.get_email_by_nickname(p_nickname TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.email
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE lower(p.nickname) = lower(p_nickname)
  LIMIT 1
$$;

REVOKE ALL ON FUNCTION public.get_email_by_nickname(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_email_by_nickname(TEXT) TO anon, authenticated;

