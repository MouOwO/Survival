package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
bus.reset()
Vector = function(x,y,z) return {x=x,y=y,z=z} end
local dead, defeated, cooldown, blocked = false, false, false, false
local grid_calls, moved, cooldowns = 0, {}, 0
local units, abilities = {}, {}
for _, id in ipairs({10,11,12}) do
    local unit = {IsNull=function() return false end, IsAlive=function() return not dead end,
        entindex=function() return id end, GetTeamNumber=function() return 2 end,
        GetAbsOrigin=function() return Vector(0,0,384) end}
    local ability = {IsNull=function() return false end, IsHidden=function() return false end,
        IsActivated=function() return true end, GetLevel=function() return 1 end,
        entindex=function() return id+100 end, GetCaster=function() return unit end,
        IsCooldownReady=function() return not cooldown end, GetCooldown=function() return 5 end,
        StartCooldown=function(_, seconds) assert(seconds==5); cooldowns=cooldowns+1 end}
    unit.FindAbilityByName=function(_,name) assert(name=="ability_building_blink"); return ability end
    units[id], abilities[id] = unit, ability
end
package.loaded["systems/player_context_service"]={is_defeated=function() return defeated end}
package.loaded["systems/tower_fusion_service"]={relocation_state=function(player,id)
    if id==12 and player==0 then return {unit=units[id],player_id=0,footprint={x=2,y=2}} end
end}
package.loaded["systems/building_system"]={relocate_for_player=function(player,id,position)
    moved[#moved+1]={player=player,id=id,position=position}; return true
end}
bus.handle_request(events.BUILDING_QUERY_REQUEST,function(p)
    assert(p.read_only==true)
    if p.entindex==10 or p.entindex==11 then return {unit=units[p.entindex],
        player_id=p.entindex==10 and 0 or 1, building_id="arrow_tower",definition={footprint={x=2,y=2}}} end
end)
bus.handle_request(events.TOWER_FUSION_MOVE_REQUEST,function(p) moved[#moved+1]=p; return {ok=true} end)
bus.handle_request(events.GRID_CAN_PLACE_REQUEST,function(p)
    grid_calls=grid_calls+1
    assert(p.ignore_entindex==10 or p.ignore_entindex==12)
    assert(p.ignore_entindexes==nil and p.team==2 and p.footprint.x==2)
    return {ok=not blocked,error=blocked and "build_cell_occupied" or nil,
        world_position=Vector(math.floor(p.position.x/64+0.5)*64,
            math.floor(p.position.y/64+0.5)*64,384),cells={{x=32,y=32,z=384,ok=not blocked}}}
end)
local move=require("systems/tower_relocation_service")
local p=Vector(129,191,-50)
local preview=move.validate(0,10,p,110)
assert(preview.ok and preview.world_position.x==128 and preview.world_position.y==192)
assert(move.move(0,10,p,110).ok and #moved==1 and cooldowns==1)
assert(moved[1].position.x==128 and moved[1].position.y==192 and moved[1].position.z==384,
    "commit uses the identical snapped server position, including height")
blocked=true
assert(not move.move(0,10,p,110).ok and #moved==1 and cooldowns==1,
    "occupancy changing after green preview is rechecked at commit")
blocked=false
assert(not move.validate(0,10,Vector(999,0,384),110).ok,
    "reject a snapped cell beyond range rather than silently clamp to another cell")
local count=grid_calls
assert(not move.validate(0,11,p,111).ok and grid_calls==count,"same team is not ownership")
assert(not move.validate(0,10,p,111).ok and grid_calls==count,"cannot borrow another tower ability")
for _, value in ipairs({0/0, math.huge, -math.huge, 40000}) do
    assert(not move.validate(0,10,Vector(value,0,384),110).ok and grid_calls==count)
end
dead=true; assert(not move.validate(0,10,p,110).ok); dead=false
defeated=true; assert(not move.validate(0,10,p,110).ok); defeated=false
cooldown=true
assert(not move.move(0,10,p,110).ok and #moved==1)
assert(move.move(0,10,p,110,true).ok and #moved==2 and cooldowns==1,
    "native casts have already paid cooldown; no double charge")
cooldown=false
assert(move.move(0,12,p,112).ok and #moved==3 and cooldowns==2,
    "UR towers share exact same grid validation and ownership rules")
print("TOWER_RELOCATION_GRID_PASS exact snap, fresh occupancy, range, ownership, finite input, cooldown, UR")

-- Exercise the real grid event router: movement must not request a builder,
-- construct another tower, debit resources, or accept a closed session twice.
local listeners, replies = {}, {}
GameRules={GetGameTime=function() return 1 end}
PlayerResource={IsValidPlayerID=function(_,id) return id==0 or id==1 end,
    GetPlayer=function(_,id) return id end}
CustomGameEventManager={RegisterListener=function(_,name,fn) listeners[name]=fn end,
    Send_ServerToPlayer=function(_,id,name,data) replies[#replies+1]={id=id,name=name,data=data} end}
EntIndexToHScript=function(id) return units[id] or abilities[id-100] end
package.loaded["config/buildings_config"]={arrow_tower={id="arrow_tower",footprint={x=2,y=2}}}
package.loaded["config/generated/building_definitions"]={rows={
    {builder_ability="build_arrow",building_id="arrow_tower"}}}
local ghost_updates, ghosts = 0, 0
package.loaded["systems/grid_preview_model_service"]={clear=function() ghosts=0 end,
    clear_all=function() ghosts=0 end,update=function() ghost_updates=ghost_updates+1;ghosts=1 end}
package.loaded["systems/grid_placement_system"]={preview_area=function(p)
    assert(p.ignore_entindex==10); return "0,0,384,1"
end}
bus.handle_request(events.BUILDER_GET_REQUEST,function() error("tower move must not resolve a builder") end)
bus.handle_request(events.BUILD_CAN_PLACE_REQUEST,function() error("tower move must not pay construction costs") end)
bus.handle_request(events.BUILD_REQUEST,function() error("tower move must not construct a duplicate tower") end)
local router=require("ui/grid_placement_router")
router.init()
local profile=router._profiles_for_test().ability_building_blink
assert(profile.placement_action=="relocate" and profile.grid_footprint_x==2)
local payload={PlayerID=0,player_id=1,session_id=1,request_id=1,
    ability_name="ability_building_blink",entindex=10,ability_entindex=110,x=129,y=191,z=384}
listeners.ui_grid_placement_validate(nil,payload)
assert(replies[#replies].id==0 and replies[#replies].data.success==1)
assert(replies[#replies].data.world_x==128 and replies[#replies].data.world_y==192)
local before=#moved
listeners.ui_grid_placement_commit(nil,payload)
assert(replies[#replies].data.success==1 and #moved==before+1)
listeners.ui_grid_placement_commit(nil,payload)
assert(replies[#replies].data.error=="stale_preview_session" and #moved==before+1)
payload.session_id=2; payload.request_id=2
listeners.ui_grid_placement_validate(nil,payload)
blocked=true
listeners.ui_grid_placement_commit(nil,payload)
assert(replies[#replies].data.success==0 and #moved==before+1)
print("TOWER_RELOCATION_ROUTER_PASS shared grid session, no build costs, duplicate/revalidation safety")

-- First D can commit before any validate/pose has opened its session. It must
-- still perform fresh server geometry and close the session before late poses.
blocked=false
payload.session_id=3; payload.request_id=3
local initial_grid_calls, initial_moves = grid_calls, #moved
listeners.ui_grid_placement_commit(nil,payload)
assert(replies[#replies].data.success==1 and replies[#replies].data.session_id==3)
assert(#moved==initial_moves+1 and grid_calls==initial_grid_calls+1)
local late_updates, late_calls = ghost_updates, grid_calls
listeners.ui_grid_placement_pose(nil,payload)
listeners.ui_grid_placement_validate(nil,payload)
assert(ghost_updates==late_updates and ghosts==0 and grid_calls==late_calls,
    "late pose/validation cannot resurrect a committed cold session")
listeners.ui_grid_placement_commit(nil,payload)
assert(replies[#replies].data.error=="stale_preview_session" and #moved==initial_moves+1)

-- Invalid direct clicks spend neither cooldown nor resources; a new session
-- can choose another cell without depending on an advisory green reply.
payload.session_id=4
blocked=true
local rejected_moves, rejected_cooldowns = #moved, cooldowns
listeners.ui_grid_placement_commit(nil,payload)
assert(replies[#replies].data.success==0 and replies[#replies].data.session_id==4)
assert(#moved==rejected_moves and cooldowns==rejected_cooldowns)
listeners.ui_grid_placement_pose(nil,payload)
assert(ghost_updates==late_updates and ghosts==0)
payload.session_id=5; blocked=false
listeners.ui_grid_placement_commit(nil,payload)
assert(replies[#replies].data.success==1 and #moved==rejected_moves+1)

-- A newer visible preview remains isolated from older commit/cancel traffic.
payload.session_id=8; payload.request_id=8
listeners.ui_grid_placement_pose(nil,payload)
assert(ghosts==1)
payload.session_id=7
listeners.ui_grid_placement_commit(nil,payload)
assert(replies[#replies].data.error=="stale_preview_session" and ghosts==1)
listeners.ui_grid_placement_preview_end(nil,payload)
assert(ghosts==1)
payload.session_id=9
listeners.ui_grid_placement_commit(nil,payload)
assert(replies[#replies].data.success==1 and ghosts==0,
    "fresh authorized commit clears an earlier visible ghost")
payload.session_id=10
listeners.ui_grid_placement_preview_end(nil,payload)
listeners.ui_grid_placement_commit(nil,payload)
assert(replies[#replies].data.error=="stale_preview_session",
    "cancel can close a cold session even before its first preview")

local safe_moves, safe_cooldowns = #moved, cooldowns
local session=10
local function reject_direct(changes)
    session=session+1
    local request={PlayerID=0,player_id=1,session_id=session,request_id=session,
        ability_name="ability_building_blink",entindex=10,ability_entindex=110,x=129,y=191,z=384}
    for key,value in pairs(changes or {}) do request[key]=value end
    listeners.ui_grid_placement_commit(nil,request)
    assert(replies[#replies].data.success==0)
    assert(#moved==safe_moves and cooldowns==safe_cooldowns)
end
reject_direct({entindex=11,ability_entindex=111}) -- same team, wrong owner
reject_direct({PlayerID=1,player_id=0}) -- engine PlayerID wins over spoofed payload
reject_direct({ability_entindex=111})
reject_direct({x=999,y=0}) -- snaps outside the actual 1000-unit range
for _, value in ipairs({0/0,math.huge,-math.huge,40000}) do reject_direct({x=value}) end
dead=true; reject_direct(); dead=false
defeated=true; reject_direct(); defeated=false
cooldown=true; reject_direct(); cooldown=false
reject_direct({ability_name="build_arrow"}) -- fresh admission is relocation only
for _, value in ipairs({0,-1,0/0,math.huge,-math.huge,"not_a_session"}) do
    reject_direct({session_id=value})
end
-- Invalid session numbers cannot poison the subsequent valid session clock.
listeners.ui_grid_placement_preview_end(nil,{PlayerID=0,session_id=math.huge})
payload.session_id=session+1
listeners.ui_grid_placement_commit(nil,payload)
assert(replies[#replies].data.success==1 and #moved==safe_moves+1)
print("TOWER_RELOCATION_IMMEDIATE_PASS cold commit, late ghost rejection, retry, new/closed session isolation, fresh ownership/range/occupancy/cooldown/finite checks")
