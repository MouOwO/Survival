-- Count actual frozen projection work for identical synthetic profile events.
-- This is an explicit audit batch, not a game timer or native/FPS measurement.
local source=arg and arg[1]
package.path=(source and source..'/scripts/vscripts/?.lua;' or 'scripts/vscripts/?.lua;')..package.path
package.loaded['core/test_access_policy']={enabled=function()return false end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return false end}
package.loaded['core/scheduler']={every=function()end,cancel=function()end}
local profiles,projections,lookups,outputs=0,0,0,0
local profile={save={content_inventory={},gameplay_stats={hero_attribute_bonus_pct=100},archive={}}}
package.loaded['systems/player_profile_service']={get_profile=function()profiles=profiles+1;return profile end}
local bus=require('core/event_bus');local events=require('core/events')
local commerce=require('systems/commerce_effects')
local original_project,original_count=commerce.project,commerce.count
commerce.project=function(...)projections=projections+1;return original_project(...)end
commerce.count=function(...)lookups=lookups+1;return original_count(...)end
local permanent=require('systems/permanent_reward_effect_service');permanent.init()
bus.subscribe(events.PERMANENT_REWARD_EFFECTS_CHANGED,function()outputs=outputs+1 end)
for i=1,60 do bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason='synthetic_same_stats_checkpoint'})end
local definitions=#require('config/generated/lottery_item_definitions').rows
assert(profiles==60 and projections==60 and outputs==1 and lookups>=60*definitions)
print(string.format('IDENTICAL_PROFILE_PROJECTION events=60 get_profile_calls=%d commerce_full_projections=%d inventory_scalar_lookups=%d lottery_definition_rows=%d emitted_changed_outputs=%d actual_native_calls=0 actual_network_calls=0',
 profiles,projections,lookups,definitions,outputs))
