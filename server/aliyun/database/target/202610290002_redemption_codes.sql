-- Code definitions are operator-owned; application callers can only redeem.
begin;
create table if not exists public.redemption_codes (
 code_id text primary key check(code_id ~ '^[a-z0-9_]{1,96}$'),
 code_hash text not null unique check(code_hash ~ '^[0-9a-f]{64}$'),
 label text not null check(length(label) between 1 and 120),
 rewards jsonb not null check(jsonb_typeof(rewards)='object'),
 enabled boolean not null default true,
 starts_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz,
 max_redemptions integer not null default 0 check(max_redemptions>=0),
 reserved_count integer not null default 0 check(reserved_count>=0),
 created_at timestamptz not null default clock_timestamp(),
 check(expires_at is null or expires_at>starts_at)
);
create table if not exists public.redemption_claims (
 account_id text not null references public.survival_players(account_id),
 code_id text not null references public.redemption_codes(code_id),
 request_id text not null,
 operation_id text not null,
 created_at timestamptz not null default clock_timestamp(),
 primary key(account_id,code_id),unique(account_id,request_id)
);
create table if not exists public.redemption_attempts (
 account_id text primary key references public.survival_players(account_id),
 window_start timestamptz not null, attempts integer not null
);
alter table public.redemption_codes owner to goufayu_owner;
alter table public.redemption_claims owner to goufayu_owner;
alter table public.redemption_attempts owner to goufayu_owner;
alter table public.redemption_codes enable row level security;
alter table public.redemption_claims enable row level security;
alter table public.redemption_attempts enable row level security;
revoke all on public.redemption_codes,public.redemption_claims,public.redemption_attempts
 from public,goufayu_app,anon,authenticated,service_role;

create or replace function public.redemption_prepare(
 p_account text,p_session text,p_code_hash text,p_request text,p_hash text)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,extensions,pg_temp as $$
declare code public.redemption_codes%rowtype; claim public.redemption_claims%rowtype;
 stamp timestamptz:=clock_timestamp(); attempts integer; command jsonb; result jsonb; identifier text;
begin
 if p_account is null or p_account !~ '^[0-9a-f]{64}$'
  or p_session is null or p_session !~ '^[A-Za-z0-9_.:-]{8,128}$'
  or p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$'
  or p_request is null or p_request !~ '^[A-Za-z0-9_.-]{8,96}$'
  or p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then raise exception 'redeem_request_invalid'; end if;
 if not exists(select 1 from public.match_profile_sessions
  where account_id=p_account and match_session_id=p_session) then
  return jsonb_build_object('ok',false,'terminal',true,'error','match_session_missing');
 end if;
 -- Preserve the shared archive lock order, including concurrent cash delivery.
 perform 1 from public.player_gameplay_stats where player_id=p_account for update;
 perform 1 from public.survival_players where account_id=p_account for update;
 if not found then raise exception 'archive_account_missing'; end if;
 insert into public.redemption_attempts values(p_account,stamp,1)
 on conflict(account_id) do update set
  attempts=case when redemption_attempts.window_start<=stamp-interval '1 minute' then 1 else redemption_attempts.attempts+1 end,
  window_start=case when redemption_attempts.window_start<=stamp-interval '1 minute' then stamp else redemption_attempts.window_start end
 returning redemption_attempts.attempts into attempts;
 if attempts>10 then return jsonb_build_object('ok',false,'terminal',false,'error','redeem_rate_limited'); end if;
 select * into code from public.redemption_codes where code_hash=p_code_hash for update;
 if not found then return jsonb_build_object('ok',false,'terminal',true,'error','redeem_code_invalid'); end if;
 select * into claim from public.redemption_claims where account_id=p_account and request_id=p_request;
 if found and claim.code_id<>code.code_id then
  return jsonb_build_object('ok',false,'terminal',true,'error','archive_id_conflict');
 end if;
 select * into claim from public.redemption_claims where account_id=p_account and code_id=code.code_id;
 if found then
  result:=public.archive_resume(p_account,claim.operation_id);
  if claim.request_id<>p_request and result->>'done'='true' then
   return jsonb_build_object('ok',false,'terminal',true,'error','redeem_already_used');
  end if;
  return result;
 end if;
 if not code.enabled then return jsonb_build_object('ok',false,'terminal',true,'error','redeem_code_disabled'); end if;
 if code.starts_at>stamp then return jsonb_build_object('ok',false,'terminal',true,'error','redeem_code_not_started'); end if;
 if code.expires_at is not null and code.expires_at<=stamp then
  return jsonb_build_object('ok',false,'terminal',true,'error','redeem_code_expired');
 end if;
 if code.max_redemptions>0 and code.reserved_count>=code.max_redemptions then
  return jsonb_build_object('ok',false,'terminal',true,'error','redeem_code_exhausted');
 end if;
 identifier:='redeem:'||code.code_id;
 command:=jsonb_build_object('id',identifier,'kind','redemption_redeem','code_id',code.code_id,
  'label',code.label,'request_id',p_request,'rewards',code.rewards);
 result:=public.archive_prepare(p_account,identifier,p_hash,
  encode(sha256(convert_to(command::text,'UTF8')),'hex'),command);
 if result->>'ok'='true' then
  insert into public.redemption_claims(account_id,code_id,request_id,operation_id)
   values(p_account,code.code_id,p_request,identifier);
  update public.redemption_codes set reserved_count=reserved_count+1 where code_id=code.code_id;
 end if;
 return result;
end; $$;

create or replace function public.redemption_commit(
 p_account text,p_id text,p_revision bigint,p_archive jsonb,p_deltas jsonb,p_inventory jsonb,p_response jsonb)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,extensions,pg_temp as $$
declare op public.archive_operations%rowtype; result jsonb; entry record;
 days integer; stamp timestamptz; existing public.archive_entitlements%rowtype;
begin
 perform 1 from public.player_gameplay_stats where player_id=p_account for update;
 perform 1 from public.survival_players where account_id=p_account for update;
 select * into op from public.archive_operations where account_id=p_account and operation_id=p_id for update;
 if not found then raise exception 'archive_operation_missing'; end if;
 if op.command->>'kind' is distinct from 'redemption_redeem' or not exists(
  select 1 from public.redemption_claims where account_id=p_account and operation_id=p_id)
 then raise exception 'redeem_operation_invalid'; end if;
 if op.done then return public.archive_resume(p_account,p_id); end if;
 if jsonb_typeof(p_inventory) is distinct from 'object' or jsonb_typeof(p_response) is distinct from 'object'
 then raise exception 'redeem_payload_invalid'; end if;
 for entry in select * from jsonb_each_text(p_inventory) loop
  if entry.value is null or entry.value !~ '^[0-9]+$' or length(entry.value)>16
   or entry.value::numeric>9007199254740991 then raise exception 'redeem_inventory_invalid'; end if;
 end loop;
 result:=public.archive_commit(p_account,p_id,p_revision,p_archive,p_deltas,null);
 if result->>'error'='archive_revision_conflict' then return result; end if;
 if result->>'ok'<>'true' or result->>'done'<>'true' then return result; end if;
 update public.player_archive_state set content_inventory=p_inventory where account_id=p_account;
 -- Only the server-frozen non-VIP monthly pass may create an entitlement.
 for entry in select * from jsonb_each_text(coalesce(op.command->'rewards'->'entitlements','{}'::jsonb)) loop
  if entry.key<>'archive_pass' or entry.value !~ '^[0-9]+$' or entry.value::numeric not between 1 and 365
  then raise exception 'redeem_entitlement_invalid'; end if;
  days:=entry.value::integer;stamp:=clock_timestamp();
  select * into existing from public.archive_entitlements
   where account_id=p_account and entitlement_id='archive_pass' for update;
  if not(found and existing.active and existing.expires_at is null) then
   insert into public.archive_entitlements(account_id,entitlement_id,active,starts_at,expires_at)
   values(p_account,'archive_pass',true,
    case when existing.active and existing.starts_at<=stamp and existing.expires_at>stamp then existing.starts_at else stamp end,
    greatest(stamp,case when existing.active then existing.expires_at else stamp end)+days*interval '24 hours')
   on conflict(account_id,entitlement_id) do update
    set active=true,starts_at=excluded.starts_at,expires_at=excluded.expires_at;
  end if;
 end loop;
 update public.archive_operations set response=p_response where account_id=p_account and operation_id=p_id;
 return public.archive_resume(p_account,p_id);
end; $$;
alter function public.redemption_prepare(text,text,text,text,text) owner to goufayu_owner;
alter function public.redemption_commit(text,text,bigint,jsonb,jsonb,jsonb,jsonb) owner to goufayu_owner;
revoke all on function public.redemption_prepare(text,text,text,text,text),
 public.redemption_commit(text,text,bigint,jsonb,jsonb,jsonb,jsonb)
 from public,goufayu_app,anon,authenticated,service_role;
grant execute on function public.redemption_prepare(text,text,text,text,text),
 public.redemption_commit(text,text,bigint,jsonb,jsonb,jsonb,jsonb) to goufayu_app;
commit;
