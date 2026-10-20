-- Daily fishing quota belongs to the same transaction as the permanent grant.
-- Keep existing grant/checkpoint implementations and their immutable receipts;
-- wrap both entry points so a capped grant is never advertised as a reward.
begin;

create table if not exists public.fishing_daily_limit_receipts (
 grant_id uuid primary key,
 account_id text not null references public.survival_players(account_id),
 request_fingerprint text not null,
 day_key text not null,
 response jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table public.fishing_daily_limit_receipts enable row level security;
revoke all on public.fishing_daily_limit_receipts from public,anon,authenticated,service_role,goufayu_app;
create index if not exists reward_grants_daily_fishing_idx
 on public.reward_grants(account_id,granted_at) where effect_scope='permanent';

create or replace function public.archive_fishing_daily_limit(p_account_id text)
returns jsonb language sql security definer
set search_path=pg_catalog,public,extensions,pg_temp as $$
 -- reward_grants.granted_at defaults to now(): use that same transaction date.
 with stamp as (select floor((extract(epoch from transaction_timestamp())+28800)/86400)::bigint as day),
 counted as (
  select stamp.day,count(g.grant_id)::bigint as earned
  from stamp left join public.reward_grants g on g.account_id=p_account_id
   and g.effect_scope='permanent'
   and g.granted_at>=to_timestamp(stamp.day*86400-28800)
   and g.granted_at<to_timestamp((stamp.day+1)*86400-28800)
  group by stamp.day
 ) select jsonb_build_object('day_key',day::text,'by_key',jsonb_build_object('fishing',
  jsonb_build_object('key','fishing','name','每日钓鱼','earned',earned,'limit',80,
   'remaining',greatest(0,80-earned),'capped',case when earned>=80 then 1 else 0 end,
   'implemented',1))) from counted;
$$;
revoke all on function public.archive_fishing_daily_limit(text) from public,anon,authenticated,service_role,goufayu_app;

do $migration$
begin
 if to_regprocedure('public.grant_out_of_match_reward_before_daily_limits(text,uuid,text,integer,numeric)') is null then
  alter function public.grant_out_of_match_reward(text,uuid,text,integer,numeric)
   rename to grant_out_of_match_reward_before_daily_limits;
 end if;
 if to_regprocedure('public.checkpoint_online_time_before_daily_limits(text,text,text,integer,integer,integer,integer)') is null then
  alter function public.checkpoint_online_time(text,text,text,integer,integer,integer,integer)
   rename to checkpoint_online_time_before_daily_limits;
 end if;
 if to_regprocedure('public.checkpoint_online_time_before_daily_limits(text,text,text,integer,integer,integer,integer,boolean)') is null then
  alter function public.checkpoint_online_time(text,text,text,integer,integer,integer,integer,boolean)
   rename to checkpoint_online_time_before_daily_limits;
 end if;
 if to_regprocedure('public.fishing_profile_json_before_daily_limits(text)') is null then
  alter function public.fishing_profile_json(text) rename to fishing_profile_json_before_daily_limits;
 end if;
end;
$migration$;
-- Renamed functions retain their old grants. Revoke them explicitly to prevent
-- a runtime-role caller from reaching the uncapped implementation directly.
revoke all on function public.grant_out_of_match_reward_before_daily_limits(text,uuid,text,integer,numeric),
 public.checkpoint_online_time_before_daily_limits(text,text,text,integer,integer,integer,integer),
 public.checkpoint_online_time_before_daily_limits(text,text,text,integer,integer,integer,integer,boolean),
 public.fishing_profile_json_before_daily_limits(text) from public,anon,authenticated,service_role,goufayu_app;

create or replace function public.fishing_profile_json(p_account_id text)
returns jsonb language sql security definer
set search_path=pg_catalog,public,extensions,pg_temp as $$
 select jsonb_set(public.fishing_profile_json_before_daily_limits(p_account_id),
  '{save,daily_limits}',public.archive_fishing_daily_limit(p_account_id),true);
$$;
revoke all on function public.fishing_profile_json(text) from public,anon,authenticated,service_role,goufayu_app;

create or replace function public.grant_out_of_match_reward(
 p_account_id text,p_grant_id uuid,p_reward_id text,p_definition_version integer,p_amount numeric
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,extensions,pg_temp as $$
declare
 fingerprint text; saved public.fishing_daily_limit_receipts%rowtype;
 definition public.star_blessing_reward_definitions%rowtype;
 quota jsonb; response jsonb;
begin
 if p_account_id is null or p_account_id !~ '^[0-9a-f]{64}$' or p_grant_id is null
  or p_reward_id is null or p_reward_id !~ '^[A-Za-z0-9_.:-]{1,128}$'
  or p_definition_version is null or p_definition_version<1 or p_amount is null
  or p_amount<0 or p_amount::text in ('NaN','Infinity','-Infinity') then
  raise exception 'out_of_match_grant_payload_invalid';
 end if;
 fingerprint:=encode(digest(p_account_id||E'\n'||p_reward_id||E'\n'||p_definition_version::text||E'\n'||p_amount::text,'sha256'),'hex');
 -- Same lock order as checkpoints and archive commits: stats, then player.
 perform 1 from public.player_gameplay_stats where player_id=p_account_id for update;
 if not found then raise exception 'gameplay_stats_missing'; end if;
 perform 1 from public.survival_players where account_id=p_account_id for update;
 if not found then raise exception 'player_missing'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_grant_id::text,0));
 select * into saved from public.fishing_daily_limit_receipts where grant_id=p_grant_id;
 if found then
  if saved.account_id<>p_account_id or saved.request_fingerprint<>fingerprint then raise exception 'grant_id_conflict'; end if;
  return saved.response;
 end if;
 -- Existing accepted receipts must replay even after midnight or at today's cap.
 if exists(select 1 from public.reward_grants where grant_id=p_grant_id) then
  return public.grant_out_of_match_reward_before_daily_limits(p_account_id,p_grant_id,p_reward_id,p_definition_version,p_amount);
 end if;
 select * into definition from public.star_blessing_reward_definitions
  where definition_version=p_definition_version and reward_id=p_reward_id for share;
 if not found or definition.effect_scope<>'permanent' then raise exception 'out_of_match_reward_invalid'; end if;
 if p_amount<definition.value_min or p_amount>definition.value_max then raise exception 'out_of_match_reward_amount_invalid'; end if;
 quota:=public.archive_fishing_daily_limit(p_account_id);
 if (quota->'by_key'->'fishing'->>'remaining')::bigint=0 then
  response:=jsonb_build_object('ok',true,'duplicate',false,'daily_limit_reached',true,
   'grant',null,'grants','[]'::jsonb,'daily_limits',quota);
  -- A capped intent remains capped on retry on a later day; it cannot turn into
  -- an extra grant when a stale checkpoint is delivered again after midnight.
  insert into public.fishing_daily_limit_receipts(grant_id,account_id,request_fingerprint,day_key,response)
   values(p_grant_id,p_account_id,fingerprint,quota->>'day_key',response);
  return response;
 end if;
 return public.grant_out_of_match_reward_before_daily_limits(p_account_id,p_grant_id,p_reward_id,p_definition_version,p_amount);
end;
$$;
revoke all on function public.grant_out_of_match_reward(text,uuid,text,integer,numeric) from public,anon,authenticated;
grant execute on function public.grant_out_of_match_reward(text,uuid,text,integer,numeric) to service_role,goufayu_app;

create or replace function public.archive_finalize_fishing_checkpoint(
 p_account_id text,p_request_id text,p_response jsonb
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,extensions,pg_temp as $$
declare checkpoint_response jsonb:=p_response; accepted jsonb; reported jsonb;
begin
 -- A response already stamped by this wrapper is immutable, even when a lost
 -- reply is retried after midnight. The fresh profile exposes today's quota.
 if checkpoint_response ? 'daily_limits' then return checkpoint_response; end if;
 reported:=checkpoint_response->'grants';
 if jsonb_typeof(reported)='array' then
  -- The retained checkpoint implementation appended its sampled item even
  -- when the nested grant returned a capped result. Filter by durable grants.
  select coalesce(jsonb_agg(entry.value order by entry.ordinality),'[]'::jsonb) into accepted
  from jsonb_array_elements(reported) with ordinality entry(value,ordinality)
  where exists(select 1 from public.reward_grants g where g.account_id=p_account_id
   and g.grant_id::text=entry.value->>'grant_id');
  checkpoint_response:=jsonb_set(checkpoint_response,'{grants}',accepted,true);
  if jsonb_array_length(accepted)<jsonb_array_length(reported) then
   checkpoint_response:=checkpoint_response||jsonb_build_object('daily_limit_reached',true);
  end if;
 end if;
 checkpoint_response:=checkpoint_response||jsonb_build_object('daily_limits',public.archive_fishing_daily_limit(p_account_id));
 -- Store exactly the response returned to the caller, including an empty grant
 -- list. Lost replies/retries cannot publish rewards which never committed.
 update public.online_time_idempotency set response=checkpoint_response
  where account_id=p_account_id and request_id=p_request_id;
 return checkpoint_response;
end;
$$;
revoke all on function public.archive_finalize_fishing_checkpoint(text,text,jsonb) from public,anon,authenticated,service_role,goufayu_app;

create or replace function public.checkpoint_online_time(
 p_account_id text,p_session_id text,p_request_id text,p_lease_seconds integer,
 p_definition_version integer,p_interval_min_seconds integer,p_interval_max_seconds integer
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,extensions,pg_temp as $$
begin
 return public.archive_finalize_fishing_checkpoint(p_account_id,p_request_id,
  public.checkpoint_online_time_before_daily_limits(p_account_id,p_session_id,p_request_id,
   p_lease_seconds,p_definition_version,p_interval_min_seconds,p_interval_max_seconds));
end;
$$;
-- The legacy seven-argument entry point remains private to its existing
-- SECURITY DEFINER delegates; the application RPC keeps its eight arguments.
revoke all on function public.checkpoint_online_time(text,text,text,integer,integer,integer,integer) from public,anon,authenticated,goufayu_app;
grant execute on function public.checkpoint_online_time(text,text,text,integer,integer,integer,integer) to service_role;

create or replace function public.checkpoint_online_time(
 p_account_id text,p_session_id text,p_request_id text,p_lease_seconds integer,
 p_definition_version integer,p_interval_min_seconds integer,p_interval_max_seconds integer,p_final boolean
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,extensions,pg_temp as $$
begin
 -- Preserve all final-session cleanup performed by the recorded implementation.
 -- Filtering here also covers a future independent eight-argument reducer;
 -- correctness never depends on it delegating to the seven-argument function.
 return public.archive_finalize_fishing_checkpoint(p_account_id,p_request_id,
  public.checkpoint_online_time_before_daily_limits(p_account_id,p_session_id,p_request_id,
   p_lease_seconds,p_definition_version,p_interval_min_seconds,p_interval_max_seconds,p_final));
end;
$$;
revoke all on function public.checkpoint_online_time(text,text,text,integer,integer,integer,integer,boolean) from public,anon,authenticated;
grant execute on function public.checkpoint_online_time(text,text,text,integer,integer,integer,integer,boolean) to service_role,goufayu_app;

create or replace function public.archive_online_pending(p_account text,p_hash text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,extensions,pg_temp as $$
declare row public.archive_online_outbox%rowtype; result jsonb:='[]'::jsonb; identifier text; date text;
begin
 for row in select x.* from public.archive_online_outbox x left join public.archive_operations o
  on o.account_id=x.account_id and o.operation_id='online:'||x.request_id
  where x.account_id=p_account and not coalesce(o.done,false) order by x.created_at limit 64 loop
  identifier:='online:'||row.request_id;
  date:=floor((extract(epoch from row.created_at)+28800)/86400)::bigint::text;
  insert into public.archive_operations(account_id,operation_id,config_hash,fingerprint,command,event_at,has_pass)
   values(p_account,identifier,p_hash,identifier,jsonb_build_object('id',identifier,'kind','online_checkpoint',
    'session',identifier,'actual_seconds',row.elapsed,'map_seconds',row.weighted,
    'day_key',date,'today',date::bigint),row.created_at,false) on conflict do nothing;
  -- Repair only unfinished legacy outbox operations whose date was missing.
  -- Their original created_at owns quota even if drained after midnight.
  update public.archive_operations set command=command||jsonb_build_object('day_key',date,'today',date::bigint)
   where account_id=p_account and operation_id=identifier and not done and not(command ? 'day_key');
  result:=result||jsonb_build_array(jsonb_build_object('id',identifier));
 end loop;
 return result;
end;
$$;
revoke all on function public.archive_online_pending(text,text) from public,anon,authenticated;
grant execute on function public.archive_online_pending(text,text) to service_role,goufayu_app;
commit;
