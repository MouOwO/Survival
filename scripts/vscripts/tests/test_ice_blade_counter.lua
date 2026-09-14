package.path="scripts/vscripts/?.lua;"..package.path
local events=require("core/events")
local weapons=require("config/generated/weapon_definitions")
local subscriptions,requests={},{}
local bus={}
function bus.subscribe(name,fn) subscriptions[name]=subscriptions[name] or {};table.insert(subscriptions[name],fn) end
function bus.emit(name,x) for _,fn in ipairs(subscriptions[name] or {}) do fn(x) end end
function bus.handle_request(name,fn) requests[name]=fn end
function bus.request(name,x) if requests[name] then return requests[name](x) end end
package.loaded["core/event_bus"]=bus
package.loaded["systems/gameplay_phase_guard"]={post_clear_frozen=function()return false end}
package.loaded["systems/player_profile_service"]={get_profile=function()return {} end}
local id="weapon_ice_blade_01"
local state={equipped_by_slot={main_hand=id}}
local charges=200
local file=assert(io.open("scripts/vscripts/systems/weapon_equipment_service.lua","rb"))
local source=file:read("*a");file:close()
local body=assert(source:match("local function on_growth_changed%(payload%)(.-)\nlocal function on_polar_crystal_progress"))
local chunk=assert(loadstring("return function(payload)"..body))
setfenv(chunk,setmetatable({weapons=weapons,state=function()return state end,
 set_main_hand_counter=function(_,snapshot) charges=snapshot.stage_attack_remaining end},{__index=_G}))
local update=chunk()
bus.subscribe(events.WEAPON_GROWTH_CHANGED,update)
bus.subscribe(events.EQUIPMENT_GROWTH_CHANGED,update)
bus.handle_request(events.WEAPON_EQUIPMENT_GET_REQUEST,function()return {snapshot={main_hand_content_id=id}} end)
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,function()return {totals={}} end)
bus.handle_request(events.INVENTORY_TRANSACTION_EXECUTE_REQUEST,function(tx)
 local previous=id;id=next(tx.grant);state.equipped_by_slot.main_hand=id
 bus.emit(events.WEAPON_EQUIPPED_CHANGED,{player_id=0,slot="main_hand",content_id=id,previous_content_id=previous})
 return {ok=true}
end)
require("systems/equipment_growth_service").init()
local attacker={GetPlayerOwnerID=function()return 0 end,GetTeamNumber=function()return 2 end}
local victim={GetTeamNumber=function()return 3 end}
for kill=1,510 do
 bus.emit(events.ENGINE_ENTITY_KILLED,{victim=victim,attacker=attacker})
 local afterKill=charges
 for damageEvent=1,3 do
  bus.emit(events.WEAPON_GROWTH_CHANGED,{player_id=0,reason="damage_dealt",snapshot={content_id=id,stage_attack_target=weapons.by_id[id].progression_value,stage_attack_remaining=weapons.by_id[id].progression_value}})
  assert(charges==afterKill,"damage growth overwrote kill counter at kill "..kill)
 end
 if kill==210 then assert(id=="weapon_ice_blade_02" and charges==240) end
end
assert(id=="weapon_ice_blade_03" and charges==240)
local before=charges
bus.emit(events.EQUIPMENT_GROWTH_CHANGED,{player_id=0,content_id="weapon_ice_blade_02",snapshot={stage_attack_remaining=250}})
assert(charges==before,"stale previous-level notification changed new weapon counter")
print("ICE_BLADE_COUNTER_PASS: 510 kills, two upgrades, 1530 interleaved damage updates, stale level event rejected")
