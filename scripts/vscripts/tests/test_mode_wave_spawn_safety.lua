package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x, y, z) return {x=x,y=y,z=z or 0} end
GetMapName = function() return "fixture" end
local mode = "scourge"
package.loaded["systems/match_setup_service"] = {get_mode=function() return mode end}
local row = {bounds={min_x=-6000,max_x=6000,min_y=-6000,max_y=6000},
    player_markers={},monster_markers={},player_bounds={},monster_bounds={}}
local config = {map_name="fixture",modes={scourge=row,cold=row,rich=row}}
package.loaded["config/mode_spawn_config"] = config
local markers = {}
for id=0,3 do
    local y = id * 1500 - 2250
    row.player_markers[id] = "player_" .. id
    row.monster_markers[id] = "monster_" .. id
    row.player_bounds[id] = {min_x=-5000,max_x=-3000,min_y=y-512,max_y=y+512}
    row.monster_bounds[id] = {min_x=-384,max_x=384,min_y=y-384,max_y=y+384}
    local function marker(x, yy)
        return {IsNull=function() return false end, GetAbsOrigin=function() return Vector(x, yy, 128) end}
    end
    markers["player_" .. id], markers["monster_" .. id] = marker(-4000,y), marker(0,y)
end
Entities = {FindByName=function(_,_,name) return markers[name] end}
local terrain_blocked, elevated, trees, path_blocked, all_blocked = false,false,false,false,false
local path_calls, samples = 0,0
GridNav = {
    IsTraversable=function(_,p)
        samples=samples+1
        return not all_blocked and not (terrain_blocked and p.x > 16 and p.x < 80)
    end,
    IsBlocked=function() return false end,
    IsNearbyTree=function(_,p,radius) return trees and p.x-radius<0 and p.x+radius>0 end,
    CanFindPath=function(_,from,to)
        path_calls=path_calls+1
        assert(to.x > -3000, "path endpoint must stay in front of a court, not under its buildings")
        return not path_blocked and not (from.x > 200)
    end,
}
GetGroundPosition=function(p) return Vector(p.x,p.y,elevated and p.x>16 and p.x<80 and 384 or 128) end
-- Drive every random draw into the same blocked strip: a checked deterministic
-- fallback must recover without ever returning an unchecked point.
RandomFloat=function() return .55 end
local service = require("systems/mode_spawn_service")
local function channel(id)
    local c = assert(service.wave_marker(id))
    c.spawn_position = c.position
    return c
end
local function inside(id,p,hull)
    assert(service.contains(row.monster_bounds[id],p,hull+16,hull+16), "whole hull stays in its own authored spawn range")
    for other=0,3 do
        assert(not service.contains(row.player_bounds[other],p), "spawn cannot move to a private court")
    end
end
for id=0,3 do
    local c=channel(id)
    local p=assert(service.wave_position(c,32));inside(id,p,32)
    assert(math.abs(p.x)>1, "scourge should sample a range instead of its fixed marker")
    assert(p.z==128)
end
local c=channel(0)
terrain_blocked=true
local p=assert(service.wave_position(c,32));inside(0,p,32)
assert(p.x+48<=16 or p.x-48>=80,"open center with blocked hull edge cannot be accepted")
terrain_blocked=false;elevated=true
p=assert(service.wave_position(c,32));inside(0,p,32)
assert(p.x+48<=16 or p.x-48>=80,"model top/height discontinuity cannot be accepted")
elevated=false;trees=true
p=assert(service.wave_position(c,32));inside(0,p,32)
assert(math.abs(p.x)>=48,"tree inside a complete hull cannot be accepted")
trees=false
RandomFloat=function() return 1 end
p=assert(service.wave_position(c,32));inside(0,p,32)
assert(p.x<=200,"disconnected open terrain must be rejected by attack-path check")
assert(not service.wave_position(c,400),"oversized boss hull must not spill out of the authored range")
path_blocked=true
assert(not service.wave_position(c,32),"no path has no unchecked marker fallback")
path_blocked=false
all_blocked=true
assert(not service.wave_position(c,32),"fully blocked region fails closed")
all_blocked=false

local unit={position=Vector(0,0,128)}
function unit:GetAbsOrigin() return self.position end
local clears=0
FindClearSpaceForUnit=function(value,point)
    clears=clears+1
    value.position=clears==1 and Vector(-4000,-2250,128) or Vector(point.x,point.y,point.z)
end
p=assert(service.wave_position(c,32))
assert(service.place_wave_unit(unit,c,p,32) and clears==2,"native displacement must be checked and retried")
inside(0,unit.position,32)
FindClearSpaceForUnit=function(value) clears=clears+1;value.position=Vector(-4000,-2250,128) end
clears=0
assert(not service.place_wave_unit(unit,c,p,32) and clears==4,"native retries are bounded and cannot escape range")
FindClearSpaceForUnit=function(value,point) value.position=Vector(point.x,point.y,point.z+256) end
assert(not service.place_wave_unit(unit,c,p,32),"clear-space cannot leave the monster stuck above terrain")
FindClearSpaceForUnit=function(value,point) value.position=point end
assert(service.place_wave_unit(unit,c,p,32),"ordinary same-wave unit overlap is not an extra spawn veto")

-- Without an authored rectangle, the compatibility search is still finite.
local authored=row.monster_bounds;row.monster_bounds=nil
p=assert(service.wave_position(c,32))
assert(math.abs(p.x)+48<=256 and math.abs(p.y-c.spawn_position.y)+48<=256)
row.monster_bounds=authored
for _,name in ipairs({"rich","cold"}) do
    mode=name;c=channel(0)
    p=assert(service.wave_position(c,32))
    assert(p.x==c.spawn_position.x and p.y==c.spawn_position.y,"other dedicated modes retain their marker")
end
mode="standard"
assert(not service.wave_position(c,32),"ordinary mode never enters dedicated spawn policy")
assert(path_calls>0 and samples>0)
print("MODE_WAVE_SPAWN_SAFETY_PASS four owner ranges, random births, full hull navigation/heights/trees, reachable attack fronts, large hull limits, checked native displacement/retries, unchanged rich/cold marker semantics")
