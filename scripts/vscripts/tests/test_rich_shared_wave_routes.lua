package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x,y,z) return {x=x,y=y,z=z or 0} end
GetMapName = function() return "template_map" end
package.loaded["systems/match_setup_service"]={get_mode=function() return "rich" end}
local config=require("config/mode_spawn_config").modes.rich
local spawn_points={{-2848,-9888},{-2656,-10080},{-2848,-10080},{-2656,-9888}}
local cities,walls,markers={},{},{}
local marker_reads,city_reads=0,0
local function entity(x,y,z)
    return {IsNull=function() return false end,GetAbsOrigin=function() return Vector(x,y,z or 128) end}
end
for id=0,3 do
    local b=config.player_bounds[id]
    markers[config.player_markers[id]]=entity((b.min_x+b.max_x)/2,(b.min_y+b.max_y)/2)
    markers[config.monster_markers[id]]=entity(spawn_points[id+1][1],spawn_points[id+1][2],0)
end
Entities={FindByName=function(_,_,name) marker_reads=marker_reads+1;return markers[name] end}
EntIndexToHScript=function(index) return walls[index] end
package.loaded["systems/building_system"]={main_city_for_player=function(id)
    city_reads=city_reads+1;return cities[id]
end}
GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end,
    IsNearbyTree=function() return false end,CanFindPath=function() return true end}
GetGroundPosition=function(p) return Vector(p.x,p.y,0) end
local spawns=require("systems/mode_spawn_service")
local routing=require("systems/wave_spawn_routing")
local function channels(count)
    local result={}
    for id=0,count-1 do result[id]={player_id=id,quota=17+id} end
    return result
end
local function city_at(owner,route) cities[owner]=markers[config.player_markers[route]] end
for route=0,3 do for count=1,4 do
    local active,wall_ids=channels(count),{}
    for id=0,count-1 do
        city_at(id,(route+1)%4)
        walls[100+id]=markers[config.player_markers[route]]
        wall_ids[id]=100+id
    end
    routing.refresh(active,wall_ids,1)
    local previous,total=nil,0
    for id=0,count-1 do
        local channel=active[id]
        assert(channel.player_id==id and channel.quota==17+id,"shared courts preserve individual wave ownership and quantities")
        assert(channel.route_id==route and channel.marker_name==config.monster_markers[route],
            "a rich player's actual wall selects the physical court ahead of its old main city")
        local p=assert(routing.position(channel))
        local offset=route%2==0 and channel.spawn_offset_y or channel.spawn_offset_x
        if route%2==0 then assert(p.x==spawn_points[route+1][1])
        else assert(p.y==spawn_points[route+1][2]) end
        if previous then assert(offset-previous==80,"same entrance owners form a centered tangent row") end
        previous,total=offset,total+offset
        local safe=assert(spawns.wave_position(channel,32))
        assert(safe.x==p.x and safe.y==p.y and safe.z==0,"the existing central marker remains the birth anchor")
        assert(math.abs(offset)+48<=192,"the complete monster hull stays inside the selected spawn area")
    end
    assert(total==0)
    local reads,scans=marker_reads,city_reads
    for _=1,1000 do for _,channel in pairs(active) do assert(routing.position(channel)) end end
    assert(reads==marker_reads and scans==city_reads,"individual spawning cannot rescan bases or markers")
end end
local active=channels(4)
for id=0,3 do city_at(id,id<2 and 0 or 3) end
routing.refresh(active,{},1)
assert(active[0].route_id==0 and active[1].route_id==0 and active[2].route_id==3 and active[3].route_id==3)
local retained=active[1]
city_at(1,2);routing.refresh(active,{},1)
assert(active[1]==retained and retained.route_id==2 and retained.spawn_offset_y==0,
    "moving a base refreshes the route without replacing pending channel identities")
cities={};walls[100]=markers[config.player_markers[2]];active=channels(1)
routing.refresh(active,{[0]=100},1);assert(active[0].route_id==2,"the owner's completed wall selects its court")
city_at(0,3);routing.refresh(active,{[0]=100},1)
assert(active[0].route_id==2,"an old main city in another court cannot override the selected wall")
cities={}
routing.refresh(active,{},1);assert(active[0].route_id==0,"before any base exists the authored initial court remains the fallback")
cities[0]=entity(0,0);routing.refresh(active,{},1)
assert(active[0].route_error=="rich_wave_base_outside_courts" and not routing.position(active[0]))
city_at(0,2)
local missing=config.monster_markers[2];local saved=markers[missing];markers[missing]=nil
routing.refresh(active,{},1)
assert(not routing.position(active[0]) and active[0].route_error:find(missing,1,true),
    "a missing selected entrance cannot borrow another player's marker")
markers[missing]=saved;routing.refresh(active,{},1)
assert(active[0].route_id==2 and spawns.wave_position(active[0],32))
print("RICH_SHARED_WAVE_ROUTES_PASS: 4 courts x1-4 owners, original central markers, wall/city priority, centered tangent births, per-owner quota, cached positions, moves and missing/invalid bases")
