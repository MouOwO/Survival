package.loaded['config/generated/commerce_catalog']=REVIEWED_COMMERCE
local medal=require('config/generated/archive_vip_rewards').by_id.vip_medal_01
local fields={'tower_critical_chance_pct','tower_final_damage_bonus_pct','hero_final_damage_bonus_pct','hero_critical_chance_pct','hero_attribute_bonus_pct'}
local schema=require('config/generated/player_gameplay_stats')
local archive_settle=require('systems/archive_settlement')
local commerce=require('systems/commerce_settlement')
local function owned_profile()
 local s={};for _,r in ipairs(schema.rows)do s[r.field_id]=r.default_value end
 s.vip_recharge_total_fen=5000;s.shop_paid_currency=100000
 return {mode='archive',revision=1,save={gameplay_stats=s,permanent_effects={},content_inventory={},archive={commerce={balances={u_coin=100000000,shop_points=0,shop_gold=0}}}},entitlements={}}
end
local serial=0
local function accept(p,r)
 assert(r.ok,tostring(r.error));for _,k in ipairs({'archive','gameplay_stats','content_inventory'})do if r[k] then p.save[k]=r[k] end end;return r
end
local function old_purchase(p)
 serial=serial+1;return archive_settle.settle(p,{kind='vip_purchase',reward_id='vip_package_01',id='medal:audit:'..serial},false)
end
check('v1_config_five_effects',function()
 assert(#medal.effect_ids==5)
 for i,f in ipairs(fields)do assert(medal.effect_ids[i]==f);near(tonumber(medal.effect_values[i]),1)end
 return 'Stable vip_medal_01 contains five +1 percentage effects; no image or display-only pseudo effect.'
end)
check('legacy_and_video_purchase_share_ownership_and_deduplicate',function()
 local p=owned_profile();local before={};for _,f in ipairs(fields)do before[f]=p.save.gameplay_stats[f] end
 accept(p,old_purchase(p))
 for _,f in ipairs(fields)do near(p.save.gameplay_stats[f]-before[f],1)end
 assert(p.save.archive.vip_claimed.vip_medal_01)
 accept(p,old_purchase(p));for _,f in ipairs(fields)do near(p.save.gameplay_stats[f]-before[f],1)end
 assert(commerce.settle(p,{kind='commerce_purchase',sku='video_bundle_vip_01'}).error=='already_owned')
 local q=owned_profile();accept(q,commerce.settle(q,{kind='commerce_purchase',sku='video_bundle_vip_01'}))
 for _,f in ipairs(fields)do near(q.save.gameplay_stats[f]-before[f],1)end
 assert(q.save.archive.vip_claimed.vip_medal_01 and q.save.archive.vip_claimed.vip_package_01)
 accept(q,old_purchase(q));for _,f in ipairs(fields)do near(q.save.gameplay_stats[f]-before[f],1)end
 local r=owned_profile();r.save.archive.vip_claimed={vip_medal_01=true}
 for _,f in ipairs(fields)do r.save.gameplay_stats[f]=r.save.gameplay_stats[f]+1 end
 accept(r,commerce.settle(r,{kind='commerce_purchase',sku='video_bundle_vip_01'}))
 for _,f in ipairs(fields)do near(r.save.gameplay_stats[f]-before[f],1)end
 return 'Old and video V1 packages both grant exactly +1 to five stats, persist the same medal marker, prevent repeat charging and cross-path duplication, and skip an already owned medal.'
end)
local medal_stats={};for _,f in ipairs(fields)do medal_stats[f]=1 end
local tower=unit(781)
check('tower_live_stats_and_actual_critical_roll',function()
 local m=require('systems/building_upgrade_system');local apply=assert(private(m.init,'apply_research_technology'))
 local state={unit=tower,player_id=0,building_id='arrow_tower',level=1,definition={levels={{attack=100,health=1000,armor=10}}},research_base_attack_damage=100}
 private(m.init,'buildings')[tower:entindex()]=state
 set({});apply(state,'medal_audit');near(tower.survival_super_tower_crit_chance,0)
 set(medal_stats);apply(state,'medal_audit');near(tower.survival_super_tower_crit_chance,1);near(tower.survival_gameplay_final_damage_pct,1)
 apply(state,'medal_audit');near(tower.survival_super_tower_crit_chance,1)
 local roll=require('systems/tower_attack_critical').roll;local target=unit(782)
 RandomFloat=function()return .999 end;near(roll(tower,target),2)
 RandomFloat=function()return 1 end;near(roll(tower,target),1)
 return 'Production building refresh supplies 1% crit and +1% final damage; real tower crit roll doubles at 0.999 and does not crit at 1.000; refresh does not stack.'
end)
local hero_snapshot
check('hero_all_three_attributes_and_actual_critical_callback',function()
 local m=require('systems/hero_combat_stat_service');local states=assert(private(m.init,'state_by_player'));local recalc=assert(private(m.init,'recalculate'))
 states[0]={unit=hero,hero_id='audit',definition={base_attack_time=2},base={strength=100,agility=100,intellect=100,attack_min=100,attack_max=100},damage_multiplier=1,engine_base_attack_min=100,engine_base_attack_max=100,engine_base_attack_time=2,refresh_version=0}
 set({});local baseline=recalc(0,'medal_audit')
 set(medal_stats);hero_snapshot=recalc(0,'medal_audit')
 for _,f in ipairs({'strength','agility','intellect'})do near(hero_snapshot[f],baseline[f]*1.01)end
 near(hero_snapshot.critical_chance_pct-baseline.critical_chance_pct,1)
 near(hero.survival_gameplay_final_damage_pct,1)
 require('modifiers/modifier_weapon_stat_projection')
 local modifier=setmetatable({server_snapshot=hero_snapshot},{__index=modifier_weapon_stat_projection});function modifier:GetParent()return hero end
 RandomFloat=function()return .999 end;modifier:OnAttackRecord({attacker=hero,record=78001});near(modifier:GetModifierDamageOutgoing_Percentage(),100)
 RandomFloat=function()return 1 end;modifier:OnAttackRecord({attacker=hero,record=78002});near(modifier:GetModifierDamageOutgoing_Percentage(),0)
 return 'Production hero projection changes STR/AGI/INT from 100 to 101, adds 1% crit and +1% final damage; actual outgoing callback is +100% only within the 1% chance.'
end)
check('actual_tower_and_hero_final_damage_filter',function()
 local m=require('combat/damage_filter_service');m.init({event_bus=bus,events=ev,repository={consume_pending=function()end},config={boss_rules={enabled=false},minimum_post_multiplier=0}})
 local target=unit(783);target.team=3;local attacker
 EntIndexToHScript=function(i)return i==783 and target or attacker end
 DAMAGE_TYPE_PHYSICAL=1;DAMAGE_TYPE_MAGICAL=2
 for _,a in ipairs({tower,hero})do
  attacker=a;local keys={damage=100,entindex_attacker_const=a:entindex(),entindex_victim_const=783,damagetype_const=2}
  assert(m._filter_for_test(nil,keys));near(keys.damage,101)
 end
 return 'Real shared damage filter resolves both tower and hero 100 input damage to 101 after medal.'
end)
GUCHENG_MEDAL_RESULTS=results
