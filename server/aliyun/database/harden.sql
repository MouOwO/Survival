-- Executed as goufayu_owner AFTER the unmodified historical migration chain.
-- RLS stays enabled; the trusted owner of SECURITY DEFINER routines accesses
-- its own tables. The application gets no owner membership or direct table DML.
REVOKE CREATE ON SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA public TO goufayu_app;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE goufayu_owner IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE goufayu_owner IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE goufayu_owner IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC;
DO $secure$
DECLARE item record;
BEGIN
 IF pg_has_role('goufayu_app','goufayu_owner','MEMBER')
    OR pg_has_role('goufayu_app','service_role','MEMBER') THEN
  RAISE EXCEPTION 'application_privileged_membership';
 END IF;
 FOR item IN SELECT c.oid::regclass AS name FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p') LOOP
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',item.name);
 END LOOP;
 FOR item IN SELECT p.oid::regprocedure AS name FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prosecdef
   AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass
     AND d.objid=p.oid AND d.deptype='e') LOOP
  EXECUTE format('ALTER FUNCTION %s SET search_path = pg_catalog,public,extensions,pg_temp',item.name);
 END LOOP;
END $secure$;
GRANT EXECUTE ON FUNCTION
 public.get_fishing_profile(text),
 public.ensure_player_gameplay_stats(text,jsonb),
 public.sync_star_blessing_reward_definitions(integer,text,jsonb),
 public.grant_out_of_match_reward(text,uuid,text,integer,numeric),
 public.checkpoint_online_time(text,text,text,integer,integer,integer,integer,boolean),
 public.archive_pending(text),public.archive_sync_config(text,jsonb),
 public.archive_resume(text,text),public.archive_prepare(text,text,text,text,jsonb),
 public.archive_commit(text,text,bigint,jsonb,jsonb,text),public.archive_online_pending(text,text)
TO goufayu_app;
