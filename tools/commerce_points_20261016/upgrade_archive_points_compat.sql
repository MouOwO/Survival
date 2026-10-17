-- Exact reviewed archive_sync_config extension. Caller owns the transaction.
-- Adds only CAF <- DEE with an empty upgrade list and identical stat schema.
-- Existing source allowlist, upgrade kinds, six-field migration and ACL unchanged.
DO $points_compat_guard$
DECLARE definition text;
BEGIN
 IF to_regprocedure('public.archive_sync_config(text,jsonb)') IS NULL THEN
  RAISE EXCEPTION 'archive_points_sync_function_missing';
 END IF;
 SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure) INTO definition;
 IF definition IS DISTINCT FROM $archive_points_old$CREATE OR REPLACE FUNCTION public.archive_sync_config(p_hash text, p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
declare v jsonb; compatibility jsonb; rule record; list_name text; item jsonb;
 old_rows jsonb; new_rows jsonb; old_spec jsonb; new_spec jsonb;
 source_hashes constant text[] := array[
  '2f4ee5dc4b4ff35378ef8b33eecd3d2ae150555c093ddf55f0bc0777058f5b8d',
  '288f724bcfd79880c4fbd7d4ac77040a8636e2f8f3ef96836632001340d3b2a7',
  '310d3063f3e320b4d541b8715d3e2005b08a68aacfabdf471da9d1c85380fca4'];
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
end; $function$
$archive_points_old$
    AND definition IS DISTINCT FROM $archive_points_new$CREATE OR REPLACE FUNCTION public.archive_sync_config(p_hash text, p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
declare v jsonb; compatibility jsonb; rule record; list_name text; item jsonb;
 old_rows jsonb; new_rows jsonb; old_spec jsonb; new_spec jsonb;
 source_hashes constant text[] := array[
  '2f4ee5dc4b4ff35378ef8b33eecd3d2ae150555c093ddf55f0bc0777058f5b8d',
  '288f724bcfd79880c4fbd7d4ac77040a8636e2f8f3ef96836632001340d3b2a7',
  '310d3063f3e320b4d541b8715d3e2005b08a68aacfabdf471da9d1c85380fca4'];
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
   if (not rule.key=any(source_hashes) and not
       (p_hash='caf4493bb7ad373a43ca81c19f961d4fd288a47112866ba93df62013852f7a59' and rule.key='dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26')) or rule.key=p_hash
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
   -- Only the reviewed points target may accept DEE, without upgrading any
   -- recorded financial operation. Even an empty upgrade list must preserve
   -- the full existing stat schema, including every bound and default.
   if rule.key='dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26' then
    if p_hash<>'caf4493bb7ad373a43ca81c19f961d4fd288a47112866ba93df62013852f7a59' or rule.value->'upgrade_commands' is distinct from '[]'::jsonb then
     raise exception 'archive_compatibility_upgrade_invalid';
    end if;
    select config->'configs'->'player_gameplay_stats'->'rows' into old_rows
     from archive_config_sets where config_hash=rule.key;
    new_rows := p_config->'configs'->'player_gameplay_stats'->'rows';
    if jsonb_typeof(old_rows) is distinct from 'array'
       or jsonb_typeof(new_rows) is distinct from 'array'
       or new_rows is distinct from old_rows then
     raise exception 'archive_compatibility_schema_invalid';
    end if;
   end if;
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
end; $function$
$archive_points_new$ THEN
  RAISE EXCEPTION 'archive_points_sync_definition_unexpected';
 END IF;
END; $points_compat_guard$;
CREATE OR REPLACE FUNCTION public.archive_sync_config(p_hash text, p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
declare v jsonb; compatibility jsonb; rule record; list_name text; item jsonb;
 old_rows jsonb; new_rows jsonb; old_spec jsonb; new_spec jsonb;
 source_hashes constant text[] := array[
  '2f4ee5dc4b4ff35378ef8b33eecd3d2ae150555c093ddf55f0bc0777058f5b8d',
  '288f724bcfd79880c4fbd7d4ac77040a8636e2f8f3ef96836632001340d3b2a7',
  '310d3063f3e320b4d541b8715d3e2005b08a68aacfabdf471da9d1c85380fca4'];
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
   if (not rule.key=any(source_hashes) and not
       (p_hash='caf4493bb7ad373a43ca81c19f961d4fd288a47112866ba93df62013852f7a59' and rule.key='dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26')) or rule.key=p_hash
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
   -- Only the reviewed points target may accept DEE, without upgrading any
   -- recorded financial operation. Even an empty upgrade list must preserve
   -- the full existing stat schema, including every bound and default.
   if rule.key='dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26' then
    if p_hash<>'caf4493bb7ad373a43ca81c19f961d4fd288a47112866ba93df62013852f7a59' or rule.value->'upgrade_commands' is distinct from '[]'::jsonb then
     raise exception 'archive_compatibility_upgrade_invalid';
    end if;
    select config->'configs'->'player_gameplay_stats'->'rows' into old_rows
     from archive_config_sets where config_hash=rule.key;
    new_rows := p_config->'configs'->'player_gameplay_stats'->'rows';
    if jsonb_typeof(old_rows) is distinct from 'array'
       or jsonb_typeof(new_rows) is distinct from 'array'
       or new_rows is distinct from old_rows then
     raise exception 'archive_compatibility_schema_invalid';
    end if;
   end if;
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
end; $function$;
