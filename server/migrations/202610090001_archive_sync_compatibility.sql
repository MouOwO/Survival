-- Add missing archive fields without changing existing balances or defaults.
-- Old operations keep their original hash/fingerprint and original 97 bounds.
begin;

alter table public.player_gameplay_stats
 add column if not exists starjoy_points_earned bigint not null default 0,
 add column if not exists starjoy_reward_level bigint not null default 0,
 add column if not exists hero_execute_health_threshold_pct numeric not null default 0,
 add column if not exists vip_level bigint not null default 0,
 add column if not exists shop_paid_currency bigint not null default 0,
 add column if not exists vip_recharge_total_fen bigint not null default 0;

do $constraints$
declare entry record; changes text := '';
begin
 for entry in select * from (values
  ('archive_sync_starjoy_points_earned_check', 'starjoy_points_earned >= 0'),
  ('archive_sync_starjoy_reward_level_check', 'starjoy_reward_level between 0 and 24'),
  ('archive_sync_execute_threshold_check', 'hero_execute_health_threshold_pct between 0 and 100'),
  ('archive_sync_vip_level_check', 'vip_level between 0 and 12'),
  ('archive_sync_paid_currency_check', 'shop_paid_currency between 0 and 2147483647'),
  ('archive_sync_recharge_total_check', 'vip_recharge_total_fen between 0 and 9007199254740991')
 ) as checks(name, expression) loop
  if not exists (select 1 from pg_constraint where conrelid='public.player_gameplay_stats'::regclass and conname=entry.name) then
   changes := changes || case when changes='' then '' else ', ' end
    || format('add constraint %I check (%s)', entry.name, entry.expression);
  end if;
 end loop;
 if changes<>'' then execute 'alter table public.player_gameplay_stats ' || changes; end if;
end;
$constraints$;

create or replace function public.archive_sync_config(p_hash text,p_config jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,extensions,pg_temp as $$
declare v jsonb; compatibility jsonb; rule record; list_name text; item jsonb;
 old_rows jsonb; new_rows jsonb; old_spec jsonb; new_spec jsonb;
 source_hashes constant text[] := array[
  '2f4ee5dc4b4ff35378ef8b33eecd3d2ae150555c093ddf55f0bc0777058f5b8d',
  '288f724bcfd79880c4fbd7d4ac77040a8636e2f8f3ef96836632001340d3b2a7'];
 upgrade_kinds constant text[] := array['clear','boss_kill','endless','endless_reconcile',
  'starjoy_reconcile','welfare_reconcile','challenge','social_draw','promotion','daily_init',
  'daily_claim','vip_claim','vip_purchase','title_equip','work_upgrade','building_upgrade'];
 new_fields constant text[] := array['starjoy_points_earned','starjoy_reward_level',
  'hero_execute_health_threshold_pct','vip_level','shop_paid_currency','vip_recharge_total_fen'];
 expected_type text; expected_max jsonb;
begin
 if jsonb_typeof(p_config) is distinct from 'object' or octet_length(p_config::text)>4000000 then
  raise exception 'archive_config_invalid';
 end if;
 -- Compatibility is part of the immutable config record, not a mutable alias.
 if p_config ? 'compatible_config_hashes' then
  compatibility := p_config->'compatible_config_hashes';
  if jsonb_typeof(compatibility) is distinct from 'object' then raise exception 'archive_compatibility_invalid'; end if;
  for rule in select * from jsonb_each(compatibility) loop
   if not rule.key=any(source_hashes) or rule.key=p_hash
      or jsonb_typeof(rule.value) is distinct from 'object'
      or not rule.value ?& array['commands','upgrade_commands']
      or rule.value-'commands'-'upgrade_commands'<>'{}'::jsonb then
    raise exception 'archive_compatibility_invalid';
   end if;
   foreach list_name in array array['commands','upgrade_commands'] loop
    if jsonb_typeof(rule.value->list_name) is distinct from 'array' then raise exception 'archive_compatibility_invalid'; end if;
    for item in select value from jsonb_array_elements(rule.value->list_name) loop
     if jsonb_typeof(item) is distinct from 'string' or item#>>'{}' !~ '^[a-z_]+$' then
      raise exception 'archive_compatibility_invalid';
     end if;
     if list_name='upgrade_commands' and
        (not (item#>>'{}')=any(upgrade_kinds) or not (rule.value->'commands') ? (item#>>'{}')) then
      raise exception 'archive_compatibility_upgrade_invalid';
     end if;
    end loop;
    if (select count(*) from jsonb_array_elements(rule.value->list_name)) <>
       (select count(distinct value) from jsonb_array_elements(rule.value->list_name)) then
     raise exception 'archive_compatibility_invalid';
    end if;
   end loop;
   -- Every old spec, including its bounds/default, must remain byte-for-byte JSON
   -- equivalent. Only the six zero-default additions can use compatible bounds.
   if jsonb_array_length(rule.value->'upgrade_commands')>0 then
    select config->'configs'->'player_gameplay_stats'->'rows' into old_rows
     from archive_config_sets where config_hash=rule.key;
    new_rows := p_config->'configs'->'player_gameplay_stats'->'rows';
    if jsonb_typeof(old_rows) is distinct from 'array' or jsonb_typeof(new_rows) is distinct from 'array'
       or jsonb_array_length(new_rows)<>jsonb_array_length(old_rows)+6
       or (select count(distinct value->>'field_id') from jsonb_array_elements(new_rows))<>jsonb_array_length(new_rows) then
     raise exception 'archive_compatibility_schema_invalid';
    end if;
    for old_spec in select value from jsonb_array_elements(old_rows) loop
     select value into new_spec from jsonb_array_elements(new_rows)
      where value->>'field_id'=old_spec->>'field_id';
     if new_spec is distinct from old_spec then raise exception 'archive_compatibility_schema_invalid'; end if;
    end loop;
    foreach list_name in array new_fields loop
     select value into new_spec from jsonb_array_elements(new_rows) where value->>'field_id'=list_name;
     expected_type := case when list_name='hero_execute_health_threshold_pct' then 'percentage' else 'integer' end;
     expected_max := case list_name when 'starjoy_reward_level' then '24'::jsonb
      when 'hero_execute_health_threshold_pct' then '100'::jsonb when 'vip_level' then '12'::jsonb
      when 'shop_paid_currency' then '2147483647'::jsonb
      when 'vip_recharge_total_fen' then '9007199254740991'::jsonb else null end;
     if new_spec is null or new_spec->>'storage_type' is distinct from expected_type
        or new_spec->'default_value' is distinct from '0'::jsonb
        or new_spec->'min_value' is distinct from '0'::jsonb
        or new_spec->'enabled' is distinct from 'true'::jsonb
        or new_spec->'max_value' is distinct from expected_max then
      raise exception 'archive_compatibility_schema_invalid';
     end if;
    end loop;
   end if;
  end loop;
 end if;
 insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
 select config into v from archive_config_sets where config_hash=p_hash;
 if v<>p_config then raise exception 'archive_config_immutable'; end if;
 return jsonb_build_object('ok',true);
end; $$;

create or replace function public.archive_commit(p_account text,p_id text,p_revision bigint,p_archive jsonb,p_deltas jsonb,p_error text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions,pg_temp as $$
declare op archive_operations%rowtype; revision bigint; entry record; spec jsonb; previous numeric; next_value numeric;
begin
 perform 1 from player_gameplay_stats where player_id=p_account for update;
 select profile_revision into revision from survival_players where account_id=p_account for update;
 select * into op from archive_operations where account_id=p_account and operation_id=p_id for update;
 if not found then raise exception 'archive_operation_missing'; end if;
 if op.done then return archive_resume(p_account,p_id); end if;
 if revision<>p_revision then return jsonb_build_object('ok',false,'error','archive_revision_conflict'); end if;
 if p_error is null then
  if jsonb_typeof(p_archive)<>'object' or jsonb_typeof(p_deltas)<>'object' then raise exception 'archive_state_invalid'; end if;
  for entry in select * from jsonb_each_text(p_deltas) loop
   select entries.spec into spec from archive_config_sets c,
    jsonb_array_elements(c.config->'configs'->'player_gameplay_stats'->'rows') as entries(spec)
    where c.config_hash=op.config_hash and entries.spec->>'field_id'=entry.key;
   -- Keep the original spec whenever it exists. A legacy operation can only
   -- append explicitly approved new stats; it cannot borrow new currency bounds.
   if spec is null
      and op.config_hash in ('2f4ee5dc4b4ff35378ef8b33eecd3d2ae150555c093ddf55f0bc0777058f5b8d',
       '288f724bcfd79880c4fbd7d4ac77040a8636e2f8f3ef96836632001340d3b2a7')
      and op.command->>'kind' in ('clear','boss_kill','endless','endless_reconcile',
       'starjoy_reconcile','welfare_reconcile','challenge','social_draw','promotion','daily_init',
       'daily_claim','vip_claim','vip_purchase','title_equip','work_upgrade','building_upgrade')
      and entry.key in ('starjoy_points_earned','starjoy_reward_level','hero_execute_health_threshold_pct',
       'vip_level','shop_paid_currency','vip_recharge_total_fen') then
    select entries.spec into spec from archive_config_sets c,
     jsonb_array_elements(c.config->'configs'->'player_gameplay_stats'->'rows') as entries(spec)
     where (c.config->'compatible_config_hashes'->op.config_hash->'upgrade_commands') ? (op.command->>'kind')
       and entries.spec->>'field_id'=entry.key
     order by c.created_at desc,c.config_hash desc limit 1;
   end if;
   if spec is null or entry.key='online_seconds_total' then raise exception 'archive_stat_invalid'; end if;
   execute format('select %I from public.player_gameplay_stats where player_id=$1',entry.key) into previous using p_account;
   next_value:=previous+entry.value::numeric;
   if next_value::text in ('NaN','Infinity','-Infinity') or next_value<(spec->>'min_value')::numeric
     or next_value>(spec->>'max_value')::numeric
     or (spec->>'storage_type'='integer' and next_value<>trunc(next_value)) then raise exception 'archive_stat_bounds'; end if;
   execute format('update public.player_gameplay_stats set %I=$1,updated_at=now() where player_id=$2',entry.key) using next_value,p_account;
  end loop;
  insert into player_archive_state(account_id,archive) values(p_account,p_archive)
   on conflict(account_id) do update set archive=excluded.archive;
  update survival_players set profile_revision=profile_revision+1,updated_at=now() where account_id=p_account;
 end if;
 update archive_operations set done=true,error=p_error where account_id=p_account and operation_id=p_id;
 return archive_resume(p_account,p_id);
end; $$;

commit;
