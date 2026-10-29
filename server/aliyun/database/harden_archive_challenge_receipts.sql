-- Reapply after historical harden.sql's blanket function revoke. Do not edit
-- the historical hardening checksums or give the application table access.
revoke all on function public.archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)
 from public,goufayu_app,anon,authenticated,service_role;
alter function public.archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)
 set search_path=pg_catalog,public,extensions,pg_temp;
grant execute on function public.archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)
 to goufayu_app;
