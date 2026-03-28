-- 049: Revoke anon access to get_email_by_nickname
-- Previously granted to anon, allowing unauthenticated email enumeration
-- by iterating over nicknames. Only authenticated users need this function
-- (login-by-nickname flow requires a session attempt first).
REVOKE EXECUTE ON FUNCTION public.get_email_by_nickname(TEXT) FROM anon;
