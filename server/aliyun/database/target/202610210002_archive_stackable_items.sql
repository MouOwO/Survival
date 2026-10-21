-- 20261021: stackable ember and capped welfare zongzi; all other unique goods remain unique.
begin;
-- Unique points CHECK whitelist from bundle 109a13e04b5624ef559b8e414f03296b0746736491bfe6af57bd9e0e31ca80b7

CREATE OR REPLACE FUNCTION public.archive_unique_points_20261019_valid(p_archive jsonb,p_inventory jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public,pg_temp AS $function$
DECLARE rules constant jsonb := '{"daily":["daily_ancient_tree","daily_attack_shard","daily_attribute_gem","daily_attribute_shard","daily_block_shard","daily_forest_origin","daily_gold_gem","daily_growth_gem","daily_health_gem","daily_regen_shard","daily_wealth_talisman","daily_wood_gem"],"lottery":{"lottery_aaron_cannon":["lottery_aaron_cannon"],"lottery_abundance_blessing":["lottery_abundance_blessing"],"lottery_ancient_pine_fortification":["lottery_ancient_pine_fortification"],"lottery_attribute_crystal":["lottery_attribute_crystal"],"lottery_bombardment_crystal":["lottery_bombardment_crystal","lottery_burst_crystal"],"lottery_candle_dragon_wing":["lottery_candle_dragon_wing"],"lottery_chief_god_blessing":["lottery_chief_god_blessing"],"lottery_chosen_hero":["lottery_chosen_hero"],"lottery_crystalline_armor":["lottery_crystalline_armor"],"lottery_cyber_overlord":["lottery_cyber_overlord"],"lottery_cybernetic_implant":["lottery_cybernetic_implant"],"lottery_darksteel_wall":["lottery_darksteel_wall"],"lottery_data_unit":["lottery_data_unit"],"lottery_dimensional_barrier":["lottery_dimensional_barrier"],"lottery_divine_spirit":["lottery_divine_spirit"],"lottery_divine_tower_blessing":["lottery_divine_tower_blessing"],"lottery_echo_compass":["lottery_echo_compass"],"lottery_emerald_wood_origin":["lottery_emerald_wood_origin"],"lottery_endless_growth_ring":["lottery_endless_growth_ring"],"lottery_expansion_crystal":["lottery_expansion_crystal"],"lottery_fallen_sky_mine":["lottery_fallen_sky_mine"],"lottery_flame_wall":["lottery_flame_wall"],"lottery_forest_burning_edge":["lottery_forest_burning_edge"],"lottery_forestcast_thousand_bolts":["lottery_forestcast_thousand_bolts"],"lottery_gale_bow":["lottery_gale_bow"],"lottery_gathering_divine_codex":["lottery_gathering_divine_codex"],"lottery_gathering_grimoire":["lottery_gathering_grimoire"],"lottery_greenwood_nirvana":["lottery_greenwood_nirvana"],"lottery_greenwood_rampart":["lottery_greenwood_rampart"],"lottery_heaven_devouring_pill":["lottery_heaven_devouring_pill"],"lottery_heaven_reaching_tower_seal":["lottery_heaven_reaching_tower_seal"],"lottery_heavenly_puppet":["lottery_heavenly_puppet"],"lottery_hero_medal":["lottery_hero_medal"],"lottery_hippogryph_onslaught":["lottery_hippogryph_onslaught"],"lottery_immortal_nirvana":["lottery_immortal_nirvana"],"lottery_immortal_slaying_sword_array":["lottery_immortal_slaying_sword_array"],"lottery_investiture_of_gods":["lottery_investiture_of_gods"],"lottery_jade_purity_sword_immortal":["lottery_jade_purity_sword_immortal"],"lottery_kings_treasure":["lottery_kings_treasure"],"lottery_law_of_cycles":["lottery_law_of_cycles"],"lottery_life_spirit":["lottery_life_spirit"],"lottery_lumber_crystal":["lottery_lumber_crystal"],"lottery_lumber_expert":["lottery_lumber_expert"],"lottery_lumber_fury":["lottery_lumber_fury"],"lottery_lumber_immortal":["lottery_lumber_immortal"],"lottery_lumber_legacy":["lottery_lumber_legacy"],"lottery_magic_book":["lottery_magic_book"],"lottery_magical_girl_juggernaut":["lottery_magical_girl_juggernaut"],"lottery_magnetic_disruption_turret":["lottery_magnetic_disruption_turret"],"lottery_monkey_king":["lottery_monkey_king"],"lottery_mountain_sea_kunpeng":["lottery_mountain_sea_kunpeng"],"lottery_muramasa":["lottery_muramasa"],"lottery_nano_cluster":["lottery_nano_cluster"],"lottery_nature_crystal":["lottery_flame_crystal","lottery_nature_crystal"],"lottery_nature_spirit":["lottery_nature_spirit"],"lottery_neural_reconstruction_module":["lottery_neural_reconstruction_module"],"lottery_nitride_alloy_wall":["lottery_nitride_alloy_wall"],"lottery_oak_bulwark":["lottery_oak_bulwark"],"lottery_omniscience_blessing":["lottery_omniscience_blessing"],"lottery_orbital_cannon_core":["lottery_orbital_cannon_core"],"lottery_protection_crystal":["lottery_protection_crystal"],"lottery_pulse_conduction_turret":["lottery_pulse_conduction_turret"],"lottery_quick_dry_cement":["lottery_quick_dry_cement"],"lottery_raven_eye":["lottery_raven_eye"],"lottery_recovery_crystal":["lottery_recovery_crystal"],"lottery_recovery_spirit":["lottery_recovery_spirit"],"lottery_reincarnation_immortal_stele":["lottery_reincarnation_immortal_stele"],"lottery_reincarnation_orb":["lottery_reincarnation_orb"],"lottery_resistance_crystal":["lottery_resistance_crystal"],"lottery_rift_implant":["lottery_rift_implant"],"lottery_seed_of_all_wood":["lottery_seed_of_all_wood"],"lottery_sharp_spirit":["lottery_sharp_spirit"],"lottery_sharpwood_tower_core":["lottery_sharpwood_tower_core"],"lottery_shooting_crystal":["lottery_shooting_crystal"],"lottery_signal_hub":["lottery_signal_hub"],"lottery_sky_turning_seal":["lottery_sky_turning_seal"],"lottery_soul_devouring_blade":["lottery_soul_devouring_blade"],"lottery_soul_lock_box":["lottery_soul_lock_box"],"lottery_sovereign_under_heaven":["lottery_sovereign_under_heaven"],"lottery_spear_of_longinus":["lottery_spear_of_longinus"],"lottery_steel_wall":["lottery_steel_wall"],"lottery_struggle_diary":["lottery_struggle_diary"],"lottery_supreme_fishing_rod":["lottery_supreme_fishing_rod"],"lottery_swift_emblem":["lottery_swift_emblem"],"lottery_sword_of_promise":["lottery_sword_of_promise"],"lottery_time_orb":["lottery_time_orb"],"lottery_titan_shield":["lottery_titan_shield"],"lottery_tower_retrofit":["lottery_tower_retrofit"],"lottery_unbreakable_fortress":["lottery_unbreakable_fortress"],"lottery_universal_tool":["lottery_universal_tool"],"lottery_void_signal_terminal":["lottery_void_signal_terminal"],"lottery_wealth_crystal":["lottery_wealth_crystal"],"lottery_windspeed_bowstring":["lottery_windspeed_bowstring"],"lottery_withered_branch_lantern":["lottery_withered_branch_lantern"],"lottery_woodcraft_grandmaster":["lottery_woodcraft_grandmaster"],"lottery_woodforged_thousand_arrows":["lottery_woodforged_thousand_arrows"]}}'::jsonb;
 counts jsonb;identity text;group_row record;raw jsonb;total numeric;
BEGIN
 IF jsonb_typeof(p_archive) IS DISTINCT FROM 'object' OR jsonb_typeof(p_inventory) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
 IF p_archive ? 'daily_rewards' AND jsonb_typeof(p_archive->'daily_rewards') IS DISTINCT FROM 'object' THEN RETURN false; END IF;
 counts:=coalesce(p_archive->'daily_rewards'->'item_counts','{}'::jsonb);
 IF jsonb_typeof(counts) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
 FOR identity IN SELECT jsonb_array_elements_text(rules->'daily') LOOP
  raw:=counts->identity;
  IF raw IS NOT NULL THEN
   IF jsonb_typeof(raw)<>'number' THEN RETURN false; END IF;
   IF (raw#>>'{}')::numeric NOT IN (0,1) THEN RETURN false; END IF;
  END IF;
  -- Daily effects are granted only from archive.daily_rewards.item_counts.
  -- A second positive copy in content_inventory has no legitimate writer.
  raw:=p_inventory->identity;
  IF raw IS NOT NULL THEN
   IF jsonb_typeof(raw)<>'number' THEN RETURN false; END IF;
   IF (raw#>>'{}')::numeric<>0 THEN RETURN false; END IF;
  END IF;
 END LOOP;
 FOR group_row IN SELECT * FROM jsonb_each(rules->'lottery') LOOP
  total:=0;
  FOR identity IN SELECT jsonb_array_elements_text(group_row.value) LOOP
   raw:=p_inventory->identity;
   IF raw IS NOT NULL THEN
    IF jsonb_typeof(raw)<>'number' THEN RETURN false; END IF;
    IF (raw#>>'{}')::numeric NOT IN (0,1) THEN RETURN false; END IF;
    total:=total+(raw#>>'{}')::numeric;
   END IF;
  END LOOP;
  IF total>1 THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END;
$function$;
REVOKE ALL ON FUNCTION public.archive_unique_points_20261019_valid(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role,goufayu_app;
ALTER TABLE public.player_archive_state DROP CONSTRAINT IF EXISTS archive_unique_points_20261019_check;
ALTER TABLE public.player_archive_state ADD CONSTRAINT archive_unique_points_20261019_check
 CHECK(public.archive_unique_points_20261019_valid(archive,content_inventory)) NOT VALID;
ALTER TABLE public.player_archive_state VALIDATE CONSTRAINT archive_unique_points_20261019_check;

CREATE OR REPLACE FUNCTION public.archive_stackable_items_20261021_valid(p_inventory jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public,pg_temp AS $function$
DECLARE identity text;raw jsonb;amount numeric;
BEGIN
 IF jsonb_typeof(p_inventory) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
 FOREACH identity IN ARRAY ARRAY['lottery_ember_of_legacy','welfare_zongzi'] LOOP
  raw:=p_inventory->identity;
  IF raw IS NOT NULL THEN
   IF jsonb_typeof(raw)<>'number' THEN RETURN false; END IF;
   amount:=(raw#>>'{}')::numeric;
   IF amount<0 OR amount>9007199254740991 OR amount<>trunc(amount) THEN RETURN false; END IF;
   IF identity='welfare_zongzi' AND amount>150 THEN RETURN false; END IF;
  END IF;
 END LOOP;
 RETURN true;
END;
$function$;
REVOKE ALL ON FUNCTION public.archive_stackable_items_20261021_valid(jsonb) FROM PUBLIC,anon,authenticated,service_role,goufayu_app;
ALTER TABLE public.player_archive_state DROP CONSTRAINT IF EXISTS archive_stackable_items_20261021_check;
ALTER TABLE public.player_archive_state ADD CONSTRAINT archive_stackable_items_20261021_check
 CHECK(public.archive_stackable_items_20261021_valid(content_inventory)) NOT VALID;
ALTER TABLE public.player_archive_state VALIDATE CONSTRAINT archive_stackable_items_20261021_check;
commit;
