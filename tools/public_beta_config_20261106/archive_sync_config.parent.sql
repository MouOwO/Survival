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
 -- Exact published WS4 catalog contract, 20261031.
 IF p_hash='d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488' THEN
 IF encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'93e950784f60e92e718506eb6c8ef770c6f2a60771a3abdabc35a3f8b8366d81' THEN RAISE EXCEPTION 'archive_release_configuration_mismatch'; END IF;
 INSERT INTO public.archive_config_sets(config_hash,config) VALUES(p_hash,p_config) ON CONFLICT DO NOTHING;
 SELECT config INTO v FROM public.archive_config_sets WHERE config_hash=p_hash;
 IF v IS DISTINCT FROM p_config THEN RAISE EXCEPTION 'archive_config_immutable'; END IF;
 RETURN jsonb_build_object('ok',true);
 END IF;

 if jsonb_typeof(p_config) is distinct from 'object' or octet_length(p_config::text)>4000000 then
  raise exception 'archive_config_invalid';
 end if;
 -- Reviewed cultivation gold-ticket costs and display-only ticket rename.
 if p_hash='bbaf4162a941449082f4c5ddcb6d02b056db54a656e08e681d4cae4adbdccf6d' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'169fa5ce7362b7ab112b8f4b7a00d2766836b6b59cad87605d7f93340be5c913' then raise exception 'archive_gold_ticket_configuration_mismatch'; end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed benefits 20261021: exact immutable configuration.
 if p_hash='47accd81d92265b93c243efc876cbd588e9f260ed8a8d7ff9e9afa1943ec9a9e' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'6a86920ab19b093497d104b1bb85e0d43c11a1d7fd8761cf7f9680e69ffd6025' then raise exception 'archive_benefits_configuration_mismatch'; end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed benefits 20261021: exact immutable configuration.
 if p_hash='a08e9c87e917ac98995a26d32055b090c4686844d140525813ba72b6aa3c1ba3' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'b6fb6c452d9ffe554de727c368164df69acbf2e82df25d53bb50e9a2feb5377a' then raise exception 'archive_benefits_configuration_mismatch'; end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed monthly challenge tickets and requested fragment/cage quotas.
 if p_hash='0763266ab8d30552fe16b69b5f78c12e073509f525d6b6ad007db34163901b3e' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'4d550b5fc9b72b3843dbb3b2562f7f93ea557016d9e46611f6035da4357e53f1' then raise exception 'archive_monthly_configuration_mismatch'; end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed archive modes and final daily quotas: one exact immutable configuration.
 if p_hash='ecf55dd6ba24d0b391a1640f7e25c06c50d79ec1eb37f0bfcdb86c28afde22f7' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'388c49bd8aea6818523c7b7ae152120d2eed15bab87cc624d89fb54262f32a1b' then
   raise exception 'archive_modes_daily_caps_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed mode-chain004 candidate: exact immutable configuration; no account backfill.
 if p_hash='b3c342e1de0de5d8c5b21471eb87a6af288a177e88d1875e43d9fcae24c3af93' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'70330a4262311f77e1f5f10e54a34960c78dc9b765730616e905818ab8a26feb' then
   raise exception 'archive_mode_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed daily unique points: exact configuration with backed-up inventory repair.
 if p_hash='0328f6ba83a13d309b8b6df84524814cf10ed5287c019282e35e286161d27bac' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'c72b65988fc8d8fd49304f77d0fc62e21327c88678012db1266901039af41308' then
   raise exception 'archive_daily_unique_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed unique points: exact immutable configuration; no player migration.
 if p_hash='ccc088836ff79f635a002095958f6bcd43f45361e71037c26bfe5054b42f1348' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'a217bf7a0517e5b5f6ecbe7316143dcf99a6e93884d5327d5b7fbd961bb6a66b' then
   raise exception 'archive_unique_points_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed 58-yuan monthly pass: one exact configuration, unchanged reward rules.
  if p_hash='9d27f6174b24e922d831837ec7a971c3726dc7a95b894c536b191ad5227406fb' then
   if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'68cd98483ab73b05471fe76e1c316626e7d2624f1a2b80805d8cdf21bf6ab985' then
    raise exception 'archive_monthly_58_configuration_mismatch';
   end if;
   insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
   select config into v from archive_config_sets where config_hash=p_hash;
   if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
   return jsonb_build_object('ok',true);
  end if;
  -- Reviewed half-price shop: one exact config and explicit parent commerce route.
  if p_hash='76591e8be3ebdfa14a947d5fa7f9c51f01e73fed81fb607480b6b2ef08b6c6b8' then
   if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'b51af08acf174269a3e3d1a0bf4e849d0b39d156a2660764c6ba0d18631078c5' then
    raise exception 'archive_half_price_configuration_mismatch';
   end if;
   insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
   select config into v from archive_config_sets where config_hash=p_hash;
   if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
   return jsonb_build_object('ok',true);
  end if;
  -- Reviewed endless titles: one exact immutable configuration, cosmetics only.
 if p_hash='60d6ce00a7d3257b6982492fdfdf68aa8deacdb4d46f837248ecfbef5ebdec94' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'aed85b2d1ef3f071696dc545a8554cdf2e89638b2cbc51bd456ad3d14a9e66c7' then
   raise exception 'archive_titles_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed shop catalog: one exact immutable target, no reducer changes.
 if p_hash='eb49cbe03cd338757949a3d7449457005d9e79ddd0f51b9ec1d8becc9e66a261' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'f754fb8f707f4ef16997a159fd36d9c5333565f3ee5a8e07394f633b7de70158' then
   raise exception 'archive_shop_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed functional commerce: exact immutable target, existing reducers retained.
 if p_hash='ab2db559240bcb08d60bc982152bc869b729496cc2afcb71dabb973149c1f3fb' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'5b3c805a1ad47ffb59626be21db010b2606e047b3660c119bfbf3a0e3f8c6658' then
   raise exception 'archive_functional_commerce_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed wife collection: one exact immutable candidate, no generic aliases.
 if p_hash='f44d6c2baaacb7a570dd5ebb2c03b01a8b1838fb1c8f102b8005cc09626669a4' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'3fb0754df745ed1466123d233682337efdde61b43f48ab5df2957911bbe2ade7' then
   raise exception 'archive_wife_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Reviewed collection rarity: one exact immutable candidate, no generic aliases.
 if p_hash='fbf16c3e996fa377f0d3cacd726c919f93958ecaf8be94a52b89ee08719f52e9' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'deb0819aa8fa32fb8149d54df694763892a56a64e8a284f0bac4f8ea90b4d0c8' then
   raise exception 'archive_collection_rarity_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
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
