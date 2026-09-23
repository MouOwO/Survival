-- Applied after the unchanged historical harden.sql, in the same transaction.
-- Keep the original security/harden.sql hash valid on deployed test03.
REVOKE ALL ON public.survival_data_migrations FROM PUBLIC,goufayu_app,anon,authenticated,service_role;
ALTER TABLE public.survival_data_migrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON FUNCTION public.archive_commit_lottery(text,text,bigint,jsonb,jsonb,text,jsonb,jsonb)
 FROM PUBLIC,goufayu_app,anon,authenticated,service_role;
ALTER FUNCTION public.archive_commit_lottery(text,text,bigint,jsonb,jsonb,text,jsonb,jsonb)
 SET search_path = pg_catalog,public,extensions,pg_temp;
GRANT EXECUTE ON FUNCTION public.archive_commit_lottery(text,text,bigint,jsonb,jsonb,text,jsonb,jsonb)
 TO goufayu_app;
