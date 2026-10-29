package.path="scripts/vscripts/?.lua;"..package.path
GetMapName=function() return "template_map" end
DOTA_TEAM_GOODGUYS,DOTA_UNIT_TARGET_TEAM_BOTH=2,3
DOTA_UNIT_TARGET_HERO,DOTA_UNIT_TARGET_BASIC,DOTA_UNIT_TARGET_BUILDING=1,2,4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE,FIND_ANY_ORDER=0,0
local mt={__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end}
Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},mt) end
package.loaded["systems/match_setup_service"]={get_mode=function() return "cold" end}
package.loaded["systems/player_context_service"]={slot=function(id)
    return {slot_id=({"east","south","west","north"})[id+1]}
end}
local config=require("config/mode_spawn_config").modes.cold
local restored={{13824,12288},{10240,11520},{14080,7168},{10240,6656}}
local original={{14336,13056},{10752,10496},{14336,7936},{10752,5376}}
local blocked,trees,units=true,false,{}
local function on_restored(p)
    for _,v in ipairs(restored) do
        if math.abs(p.x-v[1])<=160 and math.abs(p.y-v[2])<=160 then return true end
    end
    return false
end
local function height(p)
    -- Low road and high cliff inside a court's rectangular envelope.
    if p.x>=12288 and p.x<12800 and p.y>=11776 and p.y<12544 then return 0 end
    if p.x>=8960 and p.x<9472 and p.y>=11776 then return 384 end
    return 128
end
GetGroundHeight=function(p) return height(p) end
GetGroundPosition=function(p) return Vector(p.x,p.y,height(p)) end
GridNav={IsTraversable=function() return true end,
    IsBlocked=function(_,p) return blocked and on_restored(p) end,
    IsNearbyTree=function() return trees end}
FindUnitsInRadius=function() return units end
local markers={[config.center_marker]=Vector(12672,9472,16)}
for id=0,3 do markers[config.player_markers[id]]=Vector(unpack(original[id+1])) end
Entities={FindByName=function(_,_,name)
    local p=markers[name]
    return p and {IsNull=function() return false end,GetAbsOrigin=function() return p end}
end}
local regions=require("systems/rich_region_service")
local grid=require("systems/grid_placement_system")
local spawns=require("systems/mode_spawn_service")
regions.init()
for id=0,3 do assert(regions.region(id)) end -- initialize while these cells are blocked
local function place(v,owner,footprint)
    return grid._can_place_for_test({player_id=owner or 0,
        position=Vector(v[1],v[2],128),footprint=footprint or {x=4,y=4}})
end
for id=0,3 do
    local v=restored[id+1]
    assert(not spawns.contains(config.player_bounds[id],Vector(v[1],v[2],128)))
    local r=place(v,id)
    assert(not r.ok and r.error=="terrain_blocked","temporary native blockers must still reject construction")
end
blocked=false
for owner=0,3 do for _,v in ipairs(restored) do
    local r=place(v,owner)
    assert(r.ok,"all four owners can build on restored flat snow after blocker removal: "..tostring(r.error))
end end
trees=true
assert(place(restored[1]).error=="tree_blocked");trees=false
local p=restored[1]
units={{IsNull=function() return false end,IsAlive=function() return true end,
    entindex=function() return 501 end,GetAbsOrigin=function() return Vector(p[1],p[2],128) end,
    GetHullRadius=function() return 32 end}}
assert(place(p).error=="unit_blocked");units={}
assert(not place({12544,12032}).ok,"lower road inside a rectangular envelope is not snow floor")
assert(not place({9216,12032}).ok,"high cliff inside a rectangular envelope is not snow floor")
assert(not place({12288,12288}).ok,"a footprint crossing two courts is rejected")
assert(not place({15296,13568}).ok,"full footprint must fit inside the outer court boundary")
for _,v in ipairs({{9600,14080},{14464,11264},{9856,8448},{14208,5632},{12672,9472}}) do
    assert(not place(v).ok,"monster entrances and central roads remain unbuildable")
end
print("COLD_BUILDABLE_PASS: real four-court config, 4x4 restored-floor construction x4 owners, temporary blocker recovery, fresh nav/tree/unit rejection, low roads/high cliffs/cross-court/footprint-edge safety")
