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
print("WAVE_SPAWN_ROUTING_PASS: all quadrants, 1-4 parallel players, mixed sides, pending identity, shifted map center, native entrance width, missing marker safety")
