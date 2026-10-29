-- Isolated PostgreSQL only: apply the real migration chain and final hardening
-- as goufayu_owner first. The isolated administrator must be able to SET ROLE
-- to both owner and app for effective-permission probes and must run this
-- entire file, including ROLLBACK. No external accounts/config/bundle needed.
-- All fixture data, the test trigger and function are rolled back.
begin;

create function public.archive_challenge_receipt_probe_failure() returns trigger
language plpgsql set search_path=pg_catalog,public,pg_temp as $$
begin
 if new.operation_id='challenge-probe:response-failure' then
  raise exception 'probe_response_write_failed';
 end if;
 return new;
end; $$;
create trigger archive_challenge_receipt_probe_failure
 before update of response on public.archive_operations
 for each row execute function public.archive_challenge_receipt_probe_failure();

do $probe$
declare
 account text:=encode(sha256(convert_to('challenge-receipt-probe:'||clock_timestamp()::text,'UTF8')),'hex');
 config_hash text:=encode(sha256(convert_to('challenge-config-probe:'||clock_timestamp()::text,'UTF8')),'hex');
 signature text:='public.archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)';
 response jsonb:='{"awarded":2,"challenge_id":"hunt_01","rewards":[{"name":"测试碎片","quality":"gold","count":2}]}';
 archive jsonb:='{"fragment_counts":{"fragment_01":2},"sentinel":"kept"}';
 inventory jsonb:='{"unrelated_material":37,"lottery_ticket":9}';
 first jsonb; replay jsonb; stale jsonb; prepared jsonb; row_before jsonb; row_after jsonb;
 archive_before jsonb; stats_before jsonb; stats_after jsonb; inventory_before jsonb;
 revision bigint; initial_wood numeric; role_name text; count_receipts integer;
begin
 if not exists(select 1 from pg_proc where oid=signature::regprocedure
    and prosecdef and proowner=(select oid from pg_roles where rolname='goufayu_owner')
    and 'search_path=pg_catalog, public, extensions, pg_temp'=any(proconfig)) then
  raise exception 'challenge_probe_function_security_invalid';
 end if;
 if not has_function_privilege('goufayu_app',signature,'EXECUTE') then
  raise exception 'challenge_probe_app_execute_missing';
 end if;
 foreach role_name in array array['anon','authenticated','service_role'] loop
  if has_function_privilege(role_name,signature,'EXECUTE') then
   raise exception 'challenge_probe_untrusted_execute: %',role_name;
  end if;
 end loop;
 if has_table_privilege('goufayu_app','public.archive_operations','SELECT,INSERT,UPDATE,DELETE')
   or has_table_privilege('goufayu_app','public.player_archive_state','SELECT,INSERT,UPDATE,DELETE')
   or has_table_privilege('goufayu_app','public.player_gameplay_stats','SELECT,INSERT,UPDATE,DELETE') then
  raise exception 'challenge_probe_app_direct_table_access';
 end if;

 perform public.archive_sync_config(config_hash,
  '{"configs":{"player_gameplay_stats":{"rows":[{"field_id":"initial_wood","storage_type":"integer","min_value":0,"max_value":2147483647,"default_value":0}]}}}');
 perform public.ensure_player_gameplay_stats(account,'{}');
 insert into public.player_archive_state(account_id,archive,content_inventory)
  values(account,'{"sentinel":"kept"}',inventory)
  on conflict(account_id) do update set archive=excluded.archive,content_inventory=excluded.content_inventory;
 select g.initial_wood into initial_wood from public.player_gameplay_stats g where g.player_id=account;
 prepared:=public.archive_prepare(account,'challenge-probe:first',config_hash,'probe-original-fingerprint',
  '{"id":"challenge-probe:first","kind":"challenge","challenge_id":"hunt_01","difficulty_id":"n1","kill_sequence":1}');
 revision:=(prepared->'profile'->>'revision')::bigint;
 stale:=public.archive_prepare(account,'challenge-probe:stale',config_hash,'probe-stale-fingerprint',
  '{"id":"challenge-probe:stale","kind":"challenge","challenge_id":"hunt_02"}');
 select to_jsonb(op) into row_before from public.archive_operations op
  where op.account_id=account and op.operation_id='challenge-probe:first';
 first:=public.archive_commit_challenge(account,'challenge-probe:first',revision,archive,'{"initial_wood":7}',null,response);
 if first->>'ok'<>'true' or first->>'done'<>'true' or first->'response' is distinct from response then
  raise exception 'challenge_probe_atomic_response_missing';
 end if;
 if (first->'profile'->>'revision')::bigint<>revision+1 then raise exception 'challenge_probe_revision_not_once'; end if;
 select to_jsonb(op) into row_after from public.archive_operations op
  where op.account_id=account and op.operation_id='challenge-probe:first';
 if row_after-'done'-'response' is distinct from row_before-'done'-'response' then
  raise exception 'challenge_probe_identity_fingerprint_command_changed';
 end if;
 if first->'profile'->'save'->'content_inventory' is distinct from inventory then
  raise exception 'challenge_probe_inventory_changed';
 end if;
 if (select g.initial_wood from public.player_gameplay_stats g where g.player_id=account)<>initial_wood+7 then
  raise exception 'challenge_probe_stat_grant_missing';
 end if;
 -- A lost first response is recovered from the real durable receipt, without
 -- reusing the newly submitted forged response/state/delta or granting again.
 replay:=public.archive_resume(account,'challenge-probe:first');
 if replay->'response' is distinct from response then raise exception 'challenge_probe_lost_ack_resume'; end if;
 replay:=public.archive_commit_challenge(account,'challenge-probe:first',revision,'{}','{"initial_wood":999}',null,
  '{"awarded":999,"rewards":[{"name":"forged retry","count":999}]}');
 if replay->'response' is distinct from response
   or (replay->'profile'->>'revision')::bigint<>revision+1
   or (select g.initial_wood from public.player_gameplay_stats g where g.player_id=account)<>initial_wood+7 then
  raise exception 'challenge_probe_replay_double_grant_or_overwrite';
 end if;
 replay:=public.archive_commit_challenge(account,'challenge-probe:stale',revision,'{}','{}',null,'{}');
 if replay->>'error'<>'archive_revision_conflict' then raise exception 'challenge_probe_stale_revision_accepted'; end if;
 if exists(select 1 from public.archive_operations op where op.account_id=account
    and op.operation_id='challenge-probe:stale' and (op.done or op.response is not null)) then
  raise exception 'challenge_probe_conflict_persisted_response';
 end if;

 -- Fail specifically after archive_commit has changed stats/archive/revision
 -- and done=true. The same RPC statement must roll every mutation back.
 prepared:=public.archive_prepare(account,'challenge-probe:response-failure',config_hash,'probe-failure-fingerprint',
  '{"id":"challenge-probe:response-failure","kind":"challenge","challenge_id":"hunt_03"}');
 revision:=(prepared->'profile'->>'revision')::bigint;
 select a.archive,a.content_inventory into archive_before,inventory_before from public.player_archive_state a where a.account_id=account;
 select to_jsonb(g) into stats_before from public.player_gameplay_stats g where g.player_id=account;
 begin
  perform public.archive_commit_challenge(account,'challenge-probe:response-failure',revision,'{"wrong":true}',
   '{"initial_wood":11}',null,response);
  raise exception 'challenge_probe_failure_not_injected';
 exception when others then
  if sqlerrm<>'probe_response_write_failed' then raise; end if;
 end;
 select to_jsonb(g) into stats_after from public.player_gameplay_stats g where g.player_id=account;
 if stats_after is distinct from stats_before
   or (select p.profile_revision from public.survival_players p where p.account_id=account)<>revision
   or (select a.archive from public.player_archive_state a where a.account_id=account) is distinct from archive_before
   or (select a.content_inventory from public.player_archive_state a where a.account_id=account) is distinct from inventory_before
   or exists(select 1 from public.archive_operations op where op.account_id=account
      and op.operation_id='challenge-probe:response-failure' and (op.done or op.response is not null)) then
  raise exception 'challenge_probe_response_failure_partial_commit';
 end if;

 -- Invalid JSON / SQL NULL responses never cross the write boundary.
 begin
  perform public.archive_commit_challenge(account,'challenge-probe:stale',revision,archive,'{}',null,'[]');
  raise exception 'challenge_probe_array_response_accepted';
 exception when others then if sqlerrm<>'archive_challenge_response_invalid' then raise; end if; end;
 begin
  perform public.archive_commit_challenge(account,'challenge-probe:stale',revision,archive,'{}',null,null);
  raise exception 'challenge_probe_null_response_accepted';
 exception when others then if sqlerrm<>'archive_challenge_response_invalid' then raise; end if; end;

 prepared:=public.archive_prepare(account,'challenge-probe:wrong-kind',config_hash,'probe-wrong-kind',
  '{"id":"challenge-probe:wrong-kind","kind":"endless","wave":1,"difficulty":1}');
 begin
  perform public.archive_commit_challenge(account,'challenge-probe:wrong-kind',revision,'{}','{}',null,'{}');
  raise exception 'challenge_probe_wrong_kind_accepted';
 exception when others then if sqlerrm<>'archive_challenge_command_invalid' then raise; end if; end;

 -- Terminal failure stores no success detail and cannot mutate the profile.
 prepared:=public.archive_prepare(account,'challenge-probe:rejected',config_hash,'probe-rejected-fingerprint',
  '{"id":"challenge-probe:rejected","kind":"challenge","challenge_id":"hunt_04"}');
 replay:=public.archive_commit_challenge(account,'challenge-probe:rejected',revision,'{}','{"initial_wood":999}',
  'archive_fixture_rejected',response);
 if replay->>'ok'<>'false' or replay->>'done'<>'true' or replay->>'error'<>'archive_fixture_rejected'
   or replay->'response'<>'null'::jsonb then raise exception 'challenge_probe_rejection_fabricated_response'; end if;
 if (select p.profile_revision from public.survival_players p where p.account_id=account)<>revision then
  raise exception 'challenge_probe_rejection_changed_profile';
 end if;

 -- Old completed success without response stays byte-for-byte unchanged when
 -- the new RPC is retried; it must never invent the old roll or write detail.
 prepared:=public.archive_prepare(account,'challenge-probe:legacy',config_hash,'probe-legacy-fingerprint',
  '{"id":"challenge-probe:legacy","kind":"challenge","challenge_id":"hunt_05"}');
 perform public.archive_commit(account,'challenge-probe:legacy',revision,archive_before,'{}',null);
 select to_jsonb(op) into row_before from public.archive_operations op
  where op.account_id=account and op.operation_id='challenge-probe:legacy';
 replay:=public.archive_commit_challenge(account,'challenge-probe:legacy',revision,'{}','{"initial_wood":999}',null,response);
 select to_jsonb(op) into row_after from public.archive_operations op
  where op.account_id=account and op.operation_id='challenge-probe:legacy';
 if row_after is distinct from row_before or replay->'response'<>'null'::jsonb then
  raise exception 'challenge_probe_legacy_receipt_rewritten';
 end if;
 if (select g.initial_wood from public.player_gameplay_stats g where g.player_id=account)<>initial_wood+7
   or (select a.content_inventory from public.player_archive_state a where a.account_id=account) is distinct from inventory then
  raise exception 'challenge_probe_inventory_or_repeat_grant';
 end if;
 select count(*) into count_receipts from public.archive_operations op where op.account_id=account;
 if count_receipts<>6 then raise exception 'challenge_probe_receipt_count: %',count_receipts; end if;
 perform set_config('survival.challenge_probe_account',account,true);
 perform set_config('survival.challenge_probe_wood',(initial_wood+7)::text,true);
 raise notice 'ARCHIVE_CHALLENGE_RECEIPTS_DATABASE_PASS: atomic grant+response, exact lost-ACK replay, revision conflict, injected response failure rollback, invalid/null payload, kind guard, terminal rejection, immutable legacy, inventory and least privilege';
end;
$probe$;

set local role goufayu_app;
do $app_probe$
declare result jsonb; account text:=current_setting('survival.challenge_probe_account');
begin
 result:=public.archive_commit_challenge(account,'challenge-probe:first',0,'{}','{"initial_wood":999}',null,
  '{"awarded":999,"rewards":[]}');
 if result->>'ok'<>'true' or result->'response'->>'awarded'<>'2'
   or result->'response'->'rewards'->0->>'name'<>'测试碎片'
   or result->'profile'->'save'->'gameplay_stats'->>'initial_wood'<>current_setting('survival.challenge_probe_wood') then
  raise exception 'challenge_probe_app_rpc_replay_invalid';
 end if;
 begin
  update public.player_archive_state set archive='{}' where account_id=account;
  raise exception 'challenge_probe_app_direct_dml_allowed';
 exception when insufficient_privilege then null; end;
 raise notice 'ARCHIVE_CHALLENGE_RECEIPTS_APP_ROLE_PASS: actual app RPC works, direct DML denied';
end;
$app_probe$;

set local role anon;
do $anon_probe$
begin
 begin
  perform public.archive_commit_challenge(current_setting('survival.challenge_probe_account'),
   'challenge-probe:first',0,'{}','{}',null,'{}');
  raise exception 'challenge_probe_anon_rpc_allowed';
 exception when insufficient_privilege then null; end;
 raise notice 'ARCHIVE_CHALLENGE_RECEIPTS_ANON_ROLE_PASS: actual anonymous RPC denied';
end;
$anon_probe$;

rollback;
