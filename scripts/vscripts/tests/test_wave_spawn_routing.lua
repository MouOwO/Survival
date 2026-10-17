package.path = "scripts/vscripts/?.lua;" .. package.path
local routing = require("systems/wave_spawn_routing")
local cx, cy = -1024, 5376
Vector = function(x, y, z) return {x=x, y=y, z=z or 0} end
local portals, walls, lookups = {}, {}, 0
local function entity(x, y)
    local position = Vector(cx+x, cy+y, 16)
    return {IsNull=function() return false end, GetAbsOrigin=function() return position end}
end
for index, xy in ipairs({{600,0},{0,-600},{-600,0},{0,600}}) do
    portals["monsterborn_player"..index] = entity(xy[1], xy[2])
end
Entities = {FindByName=function(_, _, name) lookups=lookups+1; return portals[name] end}
EntIndexToHScript = function(id) return walls[id] end
local function channels()
    local result = {}
    for id=0,3 do
        local name="monsterborn_player"..(id+1)
        result[id]={player_id=id,marker=portals[name],marker_name=name}
    end
    return result
end
local quadrants={{100,100,"north",4},{-100,100,"west",3},
    {-100,-100,"south",2},{100,-100,"east",1}}
for _, quadrant in ipairs(quadrants) do
    for count=1,4 do
        local active, wall_ids = channels(), {}
        for id=0,3 do
            if id>=count then active[id]=nil
            else walls[id+100]=entity(quadrant[1],quadrant[2]); wall_ids[id]=id+100 end
        end
        routing.refresh(active,wall_ids,1)
        local previous, total_offset
        total_offset=0
        for id=0,count-1 do
            local channel=active[id]
            assert(channel.spawn_side==quadrant[3])
            assert(channel.marker==portals["monsterborn_player"..quadrant[4]])
            local position=assert(routing.position(channel))
            local horizontal=quadrant[3]=="north" or quadrant[3]=="south"
            local offset=horizontal and (position.x-cx) or (position.y-cy)
            local longitudinal=horizontal and (position.y-cy) or (position.x-cx)
            assert(longitudinal==((quadrant[3]=="north" or quadrant[3]=="east") and 600 or -600))
            assert(math.abs(offset)+32<=224,"Hull32 formation must fit the native 448-wide entrance")
            if previous then assert(offset-previous==80 and offset-previous>=64) end
            total_offset, previous=total_offset+offset,offset
        end
        assert(total_offset==0,"formation must stay centered on the existing portal")
    end
end
local active, wall_ids=channels(),{}
for id=0,3 do walls[id+100]=entity(quadrants[id+1][1],quadrants[id+1][2]);wall_ids[id]=id+100 end
routing.refresh(active,wall_ids,1)
for id=0,3 do
    assert(active[id].spawn_side==quadrants[id+1][3])
    assert(active[id].spawn_offset_x==0 and active[id].spawn_offset_y==0)
end
local identity=active[0]
walls[100]=entity(-100,-100)
routing.refresh(active,wall_ids,1)
assert(active[0]==identity and active[0].spawn_side=="south","pending callbacks retain their channel identity")
wall_ids[0]=nil
routing.refresh(active,wall_ids,1)
assert(active[0].marker==portals.monsterborn_player1,"no completed wall keeps the configured initial portal")
local position=portals.monsterborn_player1:GetAbsOrigin()
local x,y,z=position.x,position.y,position.z
local copies=routing.position(active[0]);copies.x,copies.y,copies.z=0,0,0
assert(position.x==x and position.y==y and position.z==z,"routing cannot move a real Hammer marker")
assert(routing.side_for(Vector(cx,cy,0),Vector(cx,cy,0))=="north","centerline tie is deterministic")
wall_ids[0]=100;portals.monsterborn_player4=nil
routing.refresh(active,wall_ids,1)
assert(active[0].marker==nil and active[0].route_error=="wave_spawn_layout_incomplete")
assert(routing.position(active[0])==nil,"missing routing layout must not silently use a wrong portal")
local before=lookups
for _=1,1000 do routing.position(active[1]) end
assert(lookups==before,"individual spawning performs no marker discovery or route scan")

-- The released map has folded entrances: the east low road turns north into
-- the northeast court. These positions come from the current Content VMAP,
-- rather than the old straight-road layout used by the generic cases above.
-- The high-ground wall examples are the four actual doorway centers. The
-- builder positions independently identify which court each route serves.
local original_get_map_name = GetMapName
local generic_routing = routing
local function load_map_routing(map_name)
    GetMapName = function() return map_name end
    package.loaded["systems/wave_spawn_routing"] = nil
    return require("systems/wave_spawn_routing")
end
cx,cy=-1024,4096
local map_positions={{112,0},{0,-112},{-112,0},{0,112}}
for index,xy in ipairs(map_positions) do
    portals["monsterborn_player"..index]=entity(xy[1],xy[2])
end
local courts={
    {wall={128,6656},builder={-500,4600},side="east",marker=1},
    {wall={1536,2944},builder={-500,3600},side="south",marker=2},
    {wall={-2176,1536},builder={-1500,3600},side="west",marker=3},
    {wall={-3584,5248},builder={-1500,4600},side="north",marker=4},
}
local function wall_at(id,position)
    walls[id]=entity(position[1]-cx,position[2]-cy)
end
local actual_north_wall=Vector(128,6656,384)
assert(generic_routing.side_for(actual_north_wall,Vector(cx,cy,0))=="north",
    "regression fixture must expose the old north-wall choice of portal 4")
routing=load_map_routing("template_map")
assert(routing.side_for(actual_north_wall,Vector(cx,cy,0))=="east",
    "folded north doorway must use portal 1, whose east road enters its northeast court")
for _,court in ipairs(courts) do
    local builder=Vector(court.builder[1],court.builder[2],0)
    assert(routing.side_for(builder,Vector(cx,cy,0))==court.side,
        "the doorway and its actual builder court must share the same portal")
    for count=1,4 do
        active,wall_ids=channels(),{}
        for id=0,3 do
            if id>=count then active[id]=nil
            else wall_at(id+100,court.wall);wall_ids[id]=id+100 end
        end
        routing.refresh(active,wall_ids,1)
        local previous_offset,total= nil,0
        local base=portals["monsterborn_player"..court.marker]:GetAbsOrigin()
        for id=0,count-1 do
            local channel=active[id]
            assert(channel.spawn_side==court.side)
            assert(channel.marker==portals["monsterborn_player"..court.marker],
                "all players in this court must use its physical portal")
            local p=assert(routing.position(channel))
            local offset
            if court.marker==1 or court.marker==3 then
                assert(p.x==base.x,"east/west physical portals must form a row along Y")
                offset=p.y-base.y
            else
                assert(p.y==base.y,"north/south physical portals must form a row along X")
                offset=p.x-base.x
            end
            assert(p.z==base.z and math.abs(offset)+32<=224)
            if previous_offset then assert(offset-previous_offset==80) end
            previous_offset,total=offset,total+offset
        end
        assert(total==0,"shared physical portal must retain a centered formation")
    end
end

-- Moving a wall to the next court changes the route, while pending spawn
-- callbacks keep the same channel object and receive its updated marker.
active,wall_ids=channels(),{}
for id=0,3 do wall_at(id+100,courts[id+1].wall);wall_ids[id]=id+100 end
routing.refresh(active,wall_ids,1)
local identities={}
for id=0,3 do
    identities[id]=active[id]
    assert(active[id].marker==portals["monsterborn_player"..(id+1)])
    assert(active[id].spawn_offset_x==0 and active[id].spawn_offset_y==0)
end
for id=0,3 do wall_at(id+100,courts[(id+1)%4+1].wall) end
routing.refresh(active,wall_ids,1)
for id=0,3 do
    assert(active[id]==identities[id],"wall relocation must preserve pending channel identity")
    assert(active[id].marker==portals["monsterborn_player"..((id+1)%4+1)],
        "wall relocation must select the portal serving the new court")
end
wall_ids[0]=nil
routing.refresh(active,wall_ids,1)
assert(active[0].marker==portals.monsterborn_player1,
    "an absent completed wall must still restore this player's configured fallback")
local map_before=lookups
for _=1,1000 do routing.position(active[1]) end
assert(lookups==map_before,"map-specific routing must not discover markers for individual spawns")

-- Do not rotate unrelated maps or a runtime without the engine map API.
for _,map_name in ipairs({"survival_c6","unknown_routing_fixture"}) do
    local other=load_map_routing(map_name)
    for _,quadrant in ipairs(quadrants) do
        assert(other.side_for(Vector(cx+quadrant[1],cy+quadrant[2],0),Vector(cx,cy,0))==quadrant[3],
            "non-template maps must retain their established quadrant contract")
    end
end
GetMapName=nil
package.loaded["systems/wave_spawn_routing"]=nil
local no_map_api=require("systems/wave_spawn_routing")
assert(no_map_api.side_for(actual_north_wall,Vector(cx,cy,0))=="north")
GetMapName=original_get_map_name
package.loaded["systems/wave_spawn_routing"]=generic_routing
print("WAVE_SPAWN_ROUTING_PASS: legacy quadrants, real folded-map doorways and builder courts, 1-4 parallel players, physical row axes, relocation identity, missing marker safety, no per-spawn discovery")
