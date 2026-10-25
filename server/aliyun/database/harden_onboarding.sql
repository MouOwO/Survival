-- Apply after the paired target migration and historical harden.sql, whose
-- blanket revoke intentionally removes all application function privileges.
REVOKE ALL ON public.player_onboarding_state FROM PUBLIC,goufayu_app,anon,authenticated,service_role;
ALTER TABLE public.player_onboarding_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON FUNCTION public.initialize_player_onboarding(),public.onboarding_state(text,text),
 public.onboarding_finish(text,text,text) FROM PUBLIC,goufayu_app,anon,authenticated,service_role;
ALTER FUNCTION public.initialize_player_onboarding() SET search_path=pg_catalog,public,extensions,pg_temp;
ALTER FUNCTION public.onboarding_state(text,text) SET search_path=pg_catalog,public,extensions,pg_temp;
ALTER FUNCTION public.onboarding_finish(text,text,text) SET search_path=pg_catalog,public,extensions,pg_temp;
GRANT EXECUTE ON FUNCTION public.onboarding_state(text,text),public.onboarding_finish(text,text,text) TO goufayu_app;
