-- Real grid checks, four Hammer rotations and sparse/remapped engine IDs.
package.path = "scripts/vscripts/?.lua;" .. package.path
package.loaded["config/test_access"] = {enabled=false}
local current_map = "template_map"
GetMapName = function() return current_map end
DOTA_TEAM_GOODGUYS = 2
DOTA_UNIT_TARGET_TEAM_BOTH,DOTA_UNIT_TARGET_HERO,DOTA_UNIT_TARGET_BASIC = 3,1,2
DOTA_UNIT_TARGET_BUILDING,DOTA_UNIT_TARGET_FLAG_INVULNERABLE,FIND_ANY_ORDER = 4,0,0
local mt = {}
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},mt) end
mt.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
mt.__sub = function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
GetGroundHeight = function() return 384 end
GetGroundPosition = function(p) return Vector(p.x,p.y,384) end
local blocked
GridNav = {IsTraversable=function() return true end,
    IsBlocked=function(_,p) return blocked and blocked(p) or false end,
    IsNearbyTree=function() return false end}
FindUnitsInRadius = function() return {} end
local function rotate(x,y,index)
    for _=1,index do x,y=y,-x end
    return x-1024,y+4096
end
local function entity(position,id)
    return {GetAbsOrigin=function() return position end,IsNull=function() return false end,
        IsAlive=function() return true end,entindex=function() return id end}
end
local markers = {}
for index=0,3 do
    for name,coordinates in pairs({turret_1={1024,624},turret_2={1408,624},
        turret_3={1792,624},corner_2={2432,912}}) do
        local x,y=rotate(coordinates[1],coordinates[2],index)
        markers["c6_player_"..index.."_"..name]=entity(Vector(x,y,400),index+50)
    end
end
Entities = {FindByName=function(_,_,name) return markers[name] end,
    FindAllByClassname=function() return {} end}
local assignments = {[7]=2,[12]=0,[5]=3,[2]=1}
package.loaded["systems/player_context_service"] = {slot=function(id)
    local index = assignments[id]
    return index and {slot_id="mapped_"..index,builder_spawn_marker="player_"..index.."_builder_spawn"} or nil
end}
local bus,events = require("core/event_bus"),require("core/events")
require("systems/forbidden_region_service").init()
local grid = require("systems/grid_placement_system")
local rows,grid_queries = {},0
bus.handle_request(events.GRID_CAN_PLACE_REQUEST,function(payload)
    grid_queries=grid_queries+1
    return grid._can_place_for_test(payload)
end)
bus.handle_request(events.BUILDING_LIST_REQUEST,function() return {ok=true,buildings=rows} end)
bus.handle_request(events.BUILDER_GET_REQUEST,function() return {ok=false} end)
local targets = require("systems/onboarding_targets")
local snap = require("core/building_grid_geometry").snap_axis
for player_id,index in pairs(assignments) do
    local result,reason=targets.get(player_id,"standard")
    assert(result,reason)
    assert(result.court_index==index,"court follows the registered spawn slot, never PlayerID order")
    for kind,coordinates in pairs({wall={2304,912},main_city={1408,1488},tower={1408,624}}) do
        local x,y=rotate(coordinates[1],coordinates[2],index)
        local _,sx=snap(x,result[kind].footprint_x)
        local _,sy=snap(y,result[kind].footprint_y)
        assert(result[kind].x==sx and result[kind].y==sy and result[kind].z==384,
            kind.." must be placed on this rotated court's actual snapped, grounded grid")
        assert(result[kind].width==64 and result[kind].height==64)
    end
end
assert(grid_queries==12,"all three recommendations per player pass real grid validation")
local base=assert(targets.get(12,"pure"))
-- An early wall built while account metadata is loading cannot move the
-- guide away from its exact stair-mouth anchor or count as guide completion.
local wrong_wall=entity(Vector(base.wall.x+64,base.wall.y,384),702)
rows={{player_id=12,building_id="wall",unit=wrong_wall,entindex=702}}
local misplaced,misplaced_reason=targets.get(12,"standard")
assert(not misplaced and misplaced_reason=="misplaced_wall",
    "an out-of-position unique wall must offer skipping instead of requesting an impossible second wall")
local aligned_wall=entity(Vector(base.wall.x+31,base.wall.y-31,384),703)
rows={{player_id=12,building_id="wall",unit=aligned_wall,entindex=703}}
local aligned=assert(targets.get(12,"standard"))
assert(aligned.existing.wall==703 and aligned.wall.existing_entindex==703
    and aligned.wall.x==base.wall.x and aligned.wall.y==base.wall.y,
    "same snapped anchor can recover without moving the recommended center")
rows={{player_id=12,building_id="wall",unit=wrong_wall,entindex=702},
    {player_id=12,building_id="wall",unit=aligned_wall,entindex=703}}
assert(assert(targets.get(12,"standard")).existing.wall==703,
    "a valid wall in later recovered rows must be considered before reporting a misplaced wall")
rows={{player_id=12,building_id="wall",
    unit=entity(Vector(base.wall.x+33,base.wall.y,384),704),entindex=704}}
local over_tolerance,over_tolerance_reason=targets.get(12,"standard")
assert(not over_tolerance and over_tolerance_reason=="misplaced_wall",
    "recovery tolerance never reaches the adjacent snapped anchor")
rows={}
local wrong_tower=entity(Vector(base.tower.x,base.tower.y+640,384),705)
rows={{player_id=12,building_id="arrow_tower",unit=wrong_tower,entindex=705}}
local unaligned_tower=assert(targets.get(12,"standard"))
assert(not unaligned_tower.existing.tower and not unaligned_tower.tower.existing_entindex
    and unaligned_tower.tower.x==base.tower.x and unaligned_tower.tower.y==base.tower.y,
    "an arbitrary completed tower cannot move or complete the guide's fixed recommendation")
-- A valid later row must be found even when an unrelated own tower was listed
-- first. Use the real secondary turret marker and retain its snapped center.
local secondary=markers.c6_player_0_turret_1:GetAbsOrigin()
local _,secondary_x=snap(secondary.x,2)
local _,secondary_y=snap(secondary.y,2)
rows[#rows+1]={player_id=12,building_id="arrow_tower",entindex=706,
    unit=entity(Vector(secondary_x+31,secondary_y-31,384),706)}
local aligned_tower=assert(targets.get(12,"standard"))
assert(aligned_tower.existing.tower==706 and aligned_tower.tower.existing_entindex==706
    and aligned_tower.tower.x==secondary_x and aligned_tower.tower.y==secondary_y)
rows={{player_id=7,building_id="arrow_tower",unit=entity(Vector(base.tower.x,base.tower.y,384),707),entindex=707}}
assert(not assert(targets.get(12,"standard")).existing.tower,
    "a teammate tower on the recommended anchor cannot satisfy this player's guide")
rows={}
-- Blocking the preferred rear city location must produce a different legal
-- center inside this same court rather than rendering a misleading green box.
blocked=function(p) return math.abs(p.x-base.main_city.x)<120 and math.abs(p.y-base.main_city.y)<120 end
local fallback,reason=targets.get(12,"standard")
assert(fallback,reason)
assert(fallback.main_city.x~=base.main_city.x or fallback.main_city.y~=base.main_city.y)
assert(grid._can_place_for_test({position=fallback.main_city,footprint={x=4,y=4},player_id=12}).ok)
assert(fallback.wall.x==base.wall.x and fallback.wall.y==base.wall.y)
-- The completed own city occupies its footprint and must be recovered without
-- trying to build a second city. Same-team other players never satisfy it.
local saved_city=entity(Vector(base.main_city.x,base.main_city.y,384),701)
rows={{player_id=7,building_id="main_city",unit=saved_city,entindex=701}}
local foreign=assert(targets.get(12,"standard"))
assert(not foreign.existing.main_city and not foreign.main_city.existing_entindex)
rows={{player_id=12,building_id="main_city",unit=saved_city,entindex=701}}
local recovered=assert(targets.get(12,"standard"))
assert(recovered.existing.main_city==701 and recovered.main_city.existing_entindex==701
    and recovered.main_city.x==base.main_city.x and recovered.main_city.y==base.main_city.y)
rows={}
-- A blocked stair has no shifted fallback: the unique recommended wall center
-- cannot wander onto the slope, adjacent lane, or a different entrance.
blocked=function(p) return math.abs(p.x-base.wall.x)<120 and math.abs(p.y-base.wall.y)<120 end
local unavailable,error=targets.get(12,"standard")
assert(not unavailable and error:find("onboarding_wall_position_unavailable:",1,true))
blocked=nil
assert(not targets.get(0,"standard"),"an unassigned player never borrows court zero")
assert(not targets.get(7.5,"standard"))
assert(not targets.get(7,"rich"))
assert(not targets.get(7,"fishing"))
current_map="survival_c6"
assert(not targets.get(7,"standard"),"unsupported maps never receive template_map coordinates")
current_map="template_map"
local removed=markers.c6_player_2_corner_2
markers.c6_player_2_corner_2=nil
assert(not targets.get(7,"standard"))
markers.c6_player_2_corner_2=entity(Vector(0,0,384),99)
assert(not targets.get(7,"standard"),"mismatched Hammer geometry fails closed")
markers.c6_player_2_corner_2=removed
print("ONBOARDING_TARGETS_PASS: actual grid, four rotations, remapped IDs, blocked fallback, own completion recovery, misplaced-wall/tower rejection, unique wall and unsupported-map guards")
