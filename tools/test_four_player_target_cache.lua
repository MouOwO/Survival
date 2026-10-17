-- Exact path-origin regression. Native path queries are the simulated boundary;
-- the production registry, preference and fallback resolver stay unchanged.
package.path = 'scripts/vscripts/?.lua;' .. package.path
local tick = 0
Vector = function(x, y, z) return {x=x, y=y, z=z or 0} end
GameRules = {GetGameTime=function() return tick end}
DOTA_TEAM_GOODGUYS = 2
GetGroundHeight = function() return 0 end
GridNav = {
    IsTraversable=function() return true end,
    IsBlocked=function() return false end,
    CanFindPath=function(_, from, to)
        -- Two distinct native navigation cells in the same 128-unit bucket
        -- are separated by an obstacle. Only the right cell reaches this wall.
        return to.x < 500 or from.x >= 64
    end,
}
local targets = require('systems/wall_target_service')
local function entity(index, x, y, owner, wall)
    local unit = {survival_player_id=owner, survival_building_id=wall and 'wall' or nil}
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:entindex() return index end
    function unit:GetAbsOrigin() return Vector(x,y,0) end
    function unit:GetHullRadius() return 32 end
    function unit:GetTeamNumber() return 2 end
    return unit
end
local own = entity(101,1200,300,0,true)
local other = entity(102,-600,300,1,true)
local left = entity(201,32,0,0,false)
local right = entity(202,96,0,0,false)
for _, reverse in ipairs({false,true}) do
    targets.reset()
    targets.register({building_id='wall',player_id=0,entindex=101,unit=own})
    targets.register({building_id='wall',player_id=1,entindex=102,unit=other})
    if reverse then
        assert(targets.resolve(right,0,-1)==101,'right origin can reach its own wall')
        assert(targets.resolve(left,0,-1)==102,'reachable cache must not leak into blocked origin')
    else
        assert(targets.resolve(left,0,-1)==102,'left origin falls back to reachable wall')
        assert(targets.resolve(right,0,-1)==101,'blocked cache must not leak into reachable origin')
    end
end
print('FOUR_PLAYER_TARGET_ORIGIN_CACHE_PASS both distinct-cell insertion orders')

-- The old four face-centre probes all miss this reachable outer contact.
-- Run the real terrain-filtered allocator, not a stubbed list of slots.
local contact=require('systems/wall_melee_contact')
targets.reset();contact.reset()
local p=Vector(1200,300,0)
own.GetAbsOrigin=function() return p end
own.survival_wall_relocation_revision=0
local path_calls=0
GridNav.CanFindPath=function(_,from,to)
    path_calls=path_calls+1
    return math.abs(to.x-(p.x-184))<.01 and math.abs(to.y-(p.y-96))<.01
end
targets.register({building_id='wall',player_id=0,entindex=101,unit=own})
local selected,cache=targets.resolve(left,0,-1)
assert(selected==101,'reachable outer attack slot must keep the completed own wall eligible')
local waypoint=assert(left.survival_wall_route)
assert(waypoint.wall==own and waypoint.revision==0)
assert(waypoint.point.x==1016 and waypoint.point.y==204,
    'AI staging must receive the actual path-validated contact, not a blocked face centre')
local checked=path_calls
for _=1,1000 do selected,cache=targets.resolve(left,0,selected,cache) end
assert(path_calls==checked,'a stable chosen wall cannot trigger repeated route searches')

-- Production relocation clears contact/nav state before publishing its event.
local old_point=waypoint.point
p=Vector(1520,300,0);own.survival_wall_relocation_revision=1
contact.clear(101);tick=.6
targets.register({building_id='wall',player_id=0,entindex=101,unit=own})
selected,cache=targets.resolve(left,0,selected,cache)
waypoint=assert(left.survival_wall_route)
assert(selected==101 and waypoint.revision==1 and waypoint.point.x==1336)
assert(waypoint.point~=old_point and old_point.x==1016,
    'moving the same wall must replace the waypoint without mutating cached geometry')

targets.reset();contact.reset()
GridNav.IsTraversable=function() return false end
targets.register({building_id='wall',player_id=0,entindex=101,unit=own})
assert(targets.resolve(left,0,-1)==-1,'a wall without any real legal contact remains unreachable')
assert(left.survival_wall_route==nil,'failed selection must clear the obsolete staging waypoint')
print('WALL_TARGET_CONTACT_ROUTE_PASS outer slot, actual waypoint, cached stable goal, relocation and no-legal-slot rejection')
