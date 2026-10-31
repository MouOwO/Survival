-- Read-only audit of actual modules. All accounts, inventory and native APIs
-- are synthetic; no purchase, grant, network request or production write.
local source=arg and arg[1]
package.path=(source and source..'/scripts/vscripts/?.lua;' or 'scripts/vscripts/?.lua;')..package.path
-- No engine admission/identity exists in this synthetic standalone process.
package.loaded['core/test_access_policy']={enabled=function()return false end}
local bus=require('core/event_bus')
local events=require('core/events')
local profile={save={content_inventory={},gameplay_stats={},archive={}}}
package.loaded['systems/player_profile_service']={get_profile=function()return profile end,
 get_content_inventory_count=function(_,id)return profile.save.content_inventory[id] or 0 end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return false end}
package.loaded['systems/technology_stat_manager']={training_room_multiplier=function()return 1 end}
package.loaded['core/scheduler']={every=function()end,cancel=function()end}
local commerce=require('systems/commerce_effects')
local progression=require('systems/hero_progression_system')
local permanent=require('systems/permanent_reward_effect_service')
local function eq(actual,expected,message)assert(math.abs(actual-expected)<1e-8,message..': '..tostring(actual))end
local function request(event,payload)local result,error=bus.request(event,payload);assert(result and result.ok~=false,error or result and result.error);return result end
local function totals()return request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0}).totals end
local function refresh()commerce.invalidate(0);bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})end

bus.reset();progression.init()
local granted=0
bus.handle_request(events.HERO_SKILL_POINT_GRANT_REQUEST,function(payload)granted=granted+payload.points;return {ok=true}end)
request(events.HERO_PROGRESSION_APPLY_REQUEST,{player_id=0,effects={{effect_type='set_rebirth_level',value=10}}})
profile.save.content_inventory.lottery_immortal_nirvana=1;refresh()
bus.emit(events.HERO_READY,{player_id=0,hero={}})
eq(granted,0,'Known gap: purchase refresh at rebirth10 does not deliver five skill points')
request(events.HERO_PROGRESSION_APPLY_REQUEST,{player_id=0,effects={}})
eq(granted,5,'A later unrelated progression request delivers the delayed reward')
print('AUDIT_NIRVANA_LATE_OWNERSHIP: after_profile_refresh=0; after_later_progression_request=5')

bus.reset();progression.init();permanent.init()
profile.save={content_inventory={lottery_endless_growth_ring=1},gameplay_stats={hero_attribute_growth=100},archive={}}
refresh()
request(events.HERO_PROGRESSION_APPLY_REQUEST,{player_id=0,effects={{effect_type='add_attack_all_attribute_gain',value=10}}})
bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=0})
local p=request(events.HERO_PROGRESSION_GET_REQUEST,{player_id=0}).snapshot
eq(p.all_attributes,11,'Ring correctly amplifies intrinsic rebirth attack growth')
eq(totals().hero_all_attributes_flat,100,'Known gap: archive attack growth receives no ring multiplier')
print('AUDIT_GROWTH_RING_COVERAGE: intrinsic_attack_growth=11_of_10; archive_attack_growth=100_of_100; combined=111; broad_description_expected=121')

bus.reset();permanent.init()
profile.save={content_inventory={commerce_p048=1,lottery_kings_treasure=1},gameplay_stats={map_level=10},archive={}}
refresh()
eq(totals().hero_attribute_bonus_pct,25,'Known gap: dynamic lottery treasure layer is added after Longinus')
profile.save.content_inventory.commerce_p043=1;refresh()
eq(totals().hero_attribute_bonus_pct,51.25,'Commerce treasure layer is amplified while equal lottery layer is not')
print('AUDIT_LONGINUS_LAYER_ORDER: lottery_treasure_only=25_not_26_25; both_treasures=51_25_not_52_5')

bus.reset()
profile.save={content_inventory={lottery_endless_growth_ring=1},gameplay_stats={},archive={}}
local hero={IsNull=function()return false end,IsAlive=function()return true end,GetTeamNumber=function()return 2 end}
local marker={IsNull=function()return false end,GetAbsOrigin=function()return {} end}
Entities={FindByName=function()return marker end}
package.loaded['systems/player_room_locations']={resolve=function()return {entry_target_name='synthetic_marker'}end,marker_name=function(name)return name end}
package.loaded['systems/hero_return_home_service']={}
package.loaded['systems/destination_validation_service']={validate=function()return true end}
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function()return {ok=true,unit=hero}end)
bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST,function()return {ok=true,snapshot={rebirth_level=10}}end)
bus.handle_request(events.RESOURCE_GET_REQUEST,function()return {gold=75000}end)
local training=require('systems/training_room_service')
local result=training.enter(0,'altar_endless_training')
assert(not result.ok and result.error:find('100000',1,true),'Known gap: entry admission uses undiscounted100000 despite discounted75000 coverage')
print('AUDIT_GROWTH_RING_ENTRY: ring_owned=true; gold=75000; discounted_entry_plus_first_tick=75000; rejected_undiscounted_requirement=100000')
print('COMMERCE_EDGE_AUDIT_PASS: four existing partial-implementation cases reproduced; real_network_calls=0; real_player_mutations=0')
