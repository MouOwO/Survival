package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x, y, z) return {x=x,y=y,z=z or 0} end
GetMapName = function() return "template_map" end
local mode, samples = "rich", 0
package.loaded["systems/match_setup_service"] = {get_mode=function() return mode end}
local points = {
    [0]=Vector(-2848,-9888,128),[1]=Vector(-2656,-9888,128),
    [2]=Vector(-2848,-10080,128),[3]=Vector(-2656,-10080,128),
}
local center=Vector(-2752,-9984,171)
local marker={IsNull=function() return false end,GetAbsOrigin=function() return center end}
local names={}
for id=0,3 do names[id]="mode_rich_monster_"..id.."_spawn" end
package.loaded["config/mode_spawn_config"]={map_name="template_map",modes={rich={
    bounds={min_x=-8192,max_x=2048,min_y=-16384,max_y=-4096},monster_markers=names}}}
GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end}
GetGroundPosition=function(p) return p end
Entities={FindByName=function(_,_,name)
    samples=samples+1
    local id=tonumber(name:match("^mode_rich_monster_(%d+)_spawn$"))
    assert(id,"Rich routing must not discover ordinary island portals")
    if points[id] then return {IsNull=function() return false end,GetAbsOrigin=function() return points[id] end} end
end}
local routing=require("systems/wave_spawn_routing")
local channels={}
for id=0,3 do channels[id]={player_id=id,marker=marker,marker_name="rich_start"} end
routing.refresh(channels,{},1)
for id=0,3 do
    local at=assert(routing.position(channels[id]))
    assert(at.x==points[id].x and at.y==points[id].y,"Each owner uses a dedicated central landing")
    assert(channels[id].marker_name==names[id] and channels[id].route_error==nil)
end
assert(samples==4)
for _=1,1000 do for id=0,3 do assert(routing.position(channels[id])) end end
assert(samples==4,"Per-monster placement reuses cached channel offsets")
-- Unresolvable wall handles retain the authored initial rich marker instead
-- of borrowing the ordinary island's quadrant/portal algorithm.
EntIndexToHScript=function() error("Rich routing must not rotate by ordinary wall quadrants") end
routing.refresh(channels,{[0]=100,[1]=101,[2]=102,[3]=103},1)
for id=0,3 do local at=routing.position(channels[id]);assert(at.x==points[id].x and at.y==points[id].y) end
points[2]=nil
routing.refresh(channels,{},1)
assert(channels[2].marker==nil and channels[2].route_error=="mode_spawn_marker_missing:"..names[2])
assert(routing.position(channels[2])==nil,"A missing rich court cannot fall back to the ordinary island")
assert(routing.position(channels[0]) and routing.position(channels[1]) and routing.position(channels[3]))
print("RICH_WAVE_ROUTES_PASS: four central Hammer landings, unchanged ownership, cached positions, no ordinary portal fallback")
