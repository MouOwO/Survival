-- Persist only newly committed challenge receipt details, in the same
-- transaction as archive/stat changes. Completed receipts remain immutable,
-- including historical successful receipts with no response. No inventory
-- column, operation ID, fingerprint, command or config hash is rewritten.
begin;

create or replace function public.archive_commit_challenge(
 p_account text,p_id text,p_revision bigint,p_archive jsonb,p_deltas jsonb,p_error text,p_response jsonb)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,extensions,pg_temp as $$
declare op public.archive_operations%rowtype; result jsonb;
begin
 -- Preserve archive_commit / lottery / checkpoint lock order.
 perform 1 from public.player_gameplay_stats where player_id=p_account for update;
 perform 1 from public.survival_players where account_id=p_account for update;
 select * into op from public.archive_operations
  where account_id=p_account and operation_id=p_id for update;
 if not found then raise exception 'archive_operation_missing'; end if;
 if op.command->>'kind' is distinct from 'challenge' then
  raise exception 'archive_challenge_command_invalid';
 end if;
 if op.done then return public.archive_resume(p_account,p_id); end if;
 if p_revision is null or p_revision<0 then raise exception 'archive_challenge_revision_invalid'; end if;
 if p_error is null and (jsonb_typeof(p_archive) is distinct from 'object'
    or jsonb_typeof(p_deltas) is distinct from 'object') then
  raise exception 'archive_state_invalid';
 end if;
 if jsonb_typeof(p_response) is distinct from 'object' then
  raise exception 'archive_challenge_response_invalid';
 end if;

 result:=public.archive_commit(p_account,p_id,p_revision,p_archive,p_deltas,p_error);
 if result->>'error'='archive_revision_conflict' then return result; end if;
 if p_error is null and result->>'ok'='true' and result->>'done'='true' then
  update public.archive_operations set response=p_response
   where account_id=p_account and operation_id=p_id;
 end if;
 return public.archive_resume(p_account,p_id);
end; $$;

alter function public.archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)
 owner to goufayu_owner;
revoke all on function public.archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)
 from public,goufayu_app,anon,authenticated,service_role;
grant execute on function public.archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)
 to goufayu_app;

commit;
