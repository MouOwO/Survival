-- Reapply after historical harden.sql, which deliberately revokes all functions.
REVOKE ALL ON public.match_profile_sessions FROM PUBLIC,goufayu_app,anon,authenticated,service_role;
ALTER TABLE public.match_profile_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON FUNCTION public.match_profile_context(text,text),public.match_profile_login(text,text,text,jsonb)
 FROM PUBLIC,goufayu_app,anon,authenticated,service_role;
ALTER FUNCTION public.match_profile_context(text,text) SET search_path=pg_catalog,public,extensions,pg_temp;
ALTER FUNCTION public.match_profile_login(text,text,text,jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
GRANT EXECUTE ON FUNCTION public.match_profile_context(text,text),public.match_profile_login(text,text,text,jsonb)
 TO goufayu_app;
