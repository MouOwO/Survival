package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x,y,z) return {x=x,y=y,z=z or 0} end
GetMapName = function() return "template_map" end
package.loaded["systems/match_setup_service"]={get_mode=function() return "cold" end}
local config=require("config/mode_spawn_config").modes.cold
local spawns={{9600,14080},{14464,11264},{9856,8448},{14208,5632}}
local players={{14336,13056},{10752,10496},{14336,7936},{10752,5376}}
local cities,walls,markers={}, {}, {}
local marker_reads,city_reads,path_reads=0,0,0
local function entity(x,y)
    return {IsNull=function() return false end,GetAbsOrigin=function() return Vector(x,y,128) end}
end
for id=0,3 do
    markers[config.monster_markers[id]]=entity(unpack(spawns[id+1]))
    markers[config.player_markers[id]]=entity(unpack(players[id+1]))
    local b=config.player_bounds[id]
    assert(id%2==0 and spawns[id+1][1]<b.min_x or id%2==1 and spawns[id+1][1]>b.max_x,
        "arrows alternate +X/-X from the opposite end of each court")
end
Entities={FindByName=function(_,_,name) marker_reads=marker_reads+1;return markers[name] end}
EntIndexToHScript=function(index) return walls[index] end
package.loaded["systems/building_system"]={main_city_for_player=function(id)
    city_reads=city_reads+1;return cities[id]
end}
local expected_route,path_blocked
GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end,
    IsNearbyTree=function() return false end,CanFindPath=function(_,from,to)
        path_reads=path_reads+1
        local b=config.player_bounds[expected_route]
        assert((expected_route%2==0 and to.x<b.min_x or expected_route%2==1 and to.x>b.max_x)
            and to.y>=b.min_y-512 and to.y<=b.max_y+512,
            "shared owners must check the selected court's attack front, not their original court")
        return not path_blocked
    end}
GetGroundPosition=function(p) return Vector(p.x,p.y,128) end
local service=require("systems/mode_spawn_service")
local routing=require("systems/wave_spawn_routing")
local function channels(count)
    local result={}
    for id=0,count-1 do result[id]={player_id=id,quota=23+id} end
    return result
end
local function city_at(id,route)
    local p=players[route+1];cities[id]=entity(p[1],p[2])
end
for route=0,3 do for count=1,4 do
    local active,wall_ids=channels(count),{}
    for id=0,count-1 do
        city_at(id,route)
        local p=players[(route+1)%4+1];walls[id+100]=entity(p[1],p[2]);wall_ids[id]=id+100
    end
    routing.refresh(active,wall_ids,1)
    local previous,offset_sum,quota= nil,0,0
    expected_route=route
    for id=0,count-1 do
        local channel=active[id]
        assert(channel.player_id==id and channel.quota==23+id,"physical routing preserves ownership and per-player quota")
        assert(channel.route_id==route and channel.marker_name==config.monster_markers[route])
        local p=assert(routing.position(channel))
        assert(p.x==spawns[route+1][1] and p.y==spawns[route+1][2]+channel.spawn_offset_y)
        if previous then assert(p.y-previous==80,"teammates use distinct evenly spaced births near the shared entrance") end
        previous=p.y;offset_sum=offset_sum+channel.spawn_offset_y;quota=quota+channel.quota
        local safe=assert(service.wave_position(channel,32))
        assert(safe.x==p.x and safe.y==p.y and safe.z==128)
        assert(math.abs(safe.y-spawns[route+1][2])+48<=192,"full hull fits the local spawn area")
    end
    assert(offset_sum==0 and quota==count*23+count*(count-1)/2)
    local reads,city_calls=marker_reads,city_reads
    for _=1,1000 do for _,channel in pairs(active) do assert(routing.position(channel)) end end
    assert(marker_reads==reads and city_reads==city_calls,"no city/marker discovery per monster")
end end
-- Mixed courts, a main-city move, owner removal and pending callback identity.
local active=channels(4)
for id=0,3 do city_at(id,id<2 and 0 or 3) end
routing.refresh(active,{},1)
for id=0,3 do assert(active[id].route_id==(id<2 and 0 or 3) and math.abs(active[id].spawn_offset_y)==40) end
local retained=active[1];city_at(1,2);routing.refresh(active,{},1)
assert(active[1]==retained and retained.route_id==2 and retained.spawn_offset_y==0)
assert(active[0].spawn_offset_y==0)
active[2]=nil;routing.refresh(active,{},1);assert(active[3].spawn_offset_y==0)
-- No city: use a registered wall's court; no base yet: retain the initial court.
cities={};walls[100]=entity(unpack(players[3]));active=channels(1)
routing.refresh(active,{[0]=100},1);assert(active[0].route_id==2)
routing.refresh(active,{},1);assert(active[0].route_id==0)
-- Missing selected entrance and invalid base positions fail closed.
city_at(0,2);local name=config.monster_markers[2];local saved=markers[name];markers[name]=nil
routing.refresh(active,{},1);assert(not routing.position(active[0]) and active[0].route_error:find(name,1,true))
markers[name]=saved;cities[0]=entity(0,0);routing.refresh(active,{},1)
assert(active[0].route_error=="cold_wave_base_outside_courts" and not routing.position(active[0]))
city_at(0,2);routing.refresh(active,{},1);expected_route=2;path_blocked=true
assert(not service.wave_position(active[0],32),"an unreachable arrow route cannot fall back to a different court")
path_blocked=false
local position=assert(service.wave_position(active[0],32))
local unit={GetAbsOrigin=function(self) return self.position end}
FindClearSpaceForUnit=function(u,p) u.position=Vector(p.x+1000,p.y,128) end
assert(not service.place_wave_unit(unit,active[0],position,32),"native clear-space displacement cannot escape the entrance")
FindClearSpaceForUnit=function(u,p) u.position=p end
assert(service.place_wave_unit(unit,active[0],position,32))
print("COLD_WAVE_ROUTES_PASS: 4 arrows x1-4 owners, main-city priority/move, shared/mixed courts, centered hull-safe births, quota/identity retention, cached positions, missing/path/displacement safety")
