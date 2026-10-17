package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x, y, z) return {x=x,y=y,z=z or 0} end
GetMapName = function() return "template_map" end
local mode, samples = "rich", 0
package.loaded["systems/match_setup_service"] = {get_mode=function() return mode end}
local points = {
    [0]=Vector(-928,-9824,128),[1]=Vector(-2976,-12064,128),
    [2]=Vector(-4768,-10016,128),[3]=Vector(-2656,-8096,128),
}
package.loaded["systems/rich_region_service"] = {wave_spawn=function(id)
    samples=samples+1
    return points[id], points[id] and nil or "rich_region_missing"
end}
local center=Vector(-2752,-9984,171)
local marker={IsNull=function() return false end,GetAbsOrigin=function() return center end}
Entities={FindByName=function() error("Rich routing must not discover ordinary island portals") end}
local routing=require("systems/wave_spawn_routing")
local channels={}
for id=0,3 do channels[id]={player_id=id,marker=marker,marker_name="rich_start"} end
routing.refresh(channels,{},1)
for id=0,3 do
    local at=assert(routing.position(channels[id]))
    assert(at.x==points[id].x and at.y==points[id].y,"Each owner uses its own court's entrance")
    assert(channels[id].marker==marker and channels[id].route_error==nil)
end
assert(samples==4)
for _=1,1000 do for id=0,3 do assert(routing.position(channels[id])) end end
assert(samples==4,"Per-monster placement reuses cached channel offsets")
-- Completed walls cannot redirect a rich player to another player's portal.
EntIndexToHScript=function() error("Rich routing must not rotate by ordinary wall quadrants") end
routing.refresh(channels,{[0]=100,[1]=101,[2]=102,[3]=103},1)
for id=0,3 do local at=routing.position(channels[id]);assert(at.x==points[id].x and at.y==points[id].y) end
points[2]=nil
routing.refresh(channels,{},1)
assert(channels[2].marker==nil and channels[2].route_error=="rich_region_missing")
assert(routing.position(channels[2])==nil,"A missing rich court cannot fall back to the ordinary island")
assert(routing.position(channels[0]) and routing.position(channels[1]) and routing.position(channels[3]))
print("RICH_WAVE_ROUTES_PASS: four private entrances, unchanged ownership, cached spawn offsets, no ordinary portal fallback")
