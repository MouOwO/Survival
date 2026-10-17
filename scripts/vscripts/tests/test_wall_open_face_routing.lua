-- Real contact allocation with a path oracle that routes around the wall's
-- outer corners. This is an offline allocator regression, not native physics.
package.path = 'scripts/vscripts/?.lua;' .. package.path
Vector = function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,areas,next_id,path_calls,curved_paths = 0,{},1000,0,0
local path_bursts,failures,cases = {},{},0
GameRules = {GetGameTime=function() return clock end}
GetGroundHeight = function() return 384 end
local function copy(p) return Vector(p.x,p.y,p.z) end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function rotate(x,y,q)
    if q==0 then return x,y elseif q==1 then return y,-x
    elseif q==2 then return -x,-y else return -y,x end
end
local function point(area,x,y)
    x,y=rotate(x,y,area.rotation)
    return Vector(area.x+x,area.y+y,384)
end
local function relative(area,p) return p.x-area.x,p.y-area.y end
local function containing(p)
    local best,found
    for _,area in ipairs(areas) do
        local d=(p.x-area.x)^2+(p.y-area.y)^2
        if not best or d<best then best,found=d,area end
    end
    return assert(found,'navigation query outside a registered test area')
end
local function face(area,p)
    local x,y=relative(area,p)
    if math.abs(x)>=math.abs(y) then return x<0 and 1 or 2 end
    return y<0 and 3 or 4
end
-- Strict interior intersection allows a path to follow the expanded square's
-- boundary, while forbidding a straight chord through its interior.
local function crosses(a,b)
    local low,high,half=0,1,160
    for _,axis in ipairs({'x','y'}) do
        local start,delta=a[axis],b[axis]-a[axis]
        if math.abs(delta)<.000001 then
            if start<=-half or start>=half then return false end
        else
            local enter,leave=(-half-start)/delta,(half-start)/delta
            if enter>leave then enter,leave=leave,enter end
            low,high=math.max(low,enter),math.min(high,leave)
            if high-low<.000001 then return false end
        end
    end
    return high-low>.000001
end
local function corner_path(area,from,to)
    local ax,ay=relative(area,from)
    local bx,by=relative(area,to)
    local nodes={Vector(ax,ay),Vector(bx,by)}
    for _,x in ipairs({-160,160}) do for _,y in ipairs({-160,160}) do
        nodes[#nodes+1]=Vector(x,y)
    end end
    local lengths,visited={[1]=0},{}
    for _=1,#nodes do
        local current,best
        for index=1,#nodes do
            if not visited[index] and lengths[index]
                and (not best or lengths[index]<best) then current,best=index,lengths[index] end
        end
        if not current then return -1 end
        if current==2 then
            if crosses(nodes[1],nodes[2]) then
                assert(best>distance(nodes[1],nodes[2]),'cross-wall route must include an outside corner')
                curved_paths=curved_paths+1
            end
            return best
        end
        visited[current]=true
        for index=1,#nodes do
            if not visited[index] and not crosses(nodes[current],nodes[index]) then
                local candidate=best+distance(nodes[current],nodes[index])
                if not lengths[index] or candidate<lengths[index] then lengths[index]=candidate end
            end
        end
    end
    return -1
end
GridNav={
    IsTraversable=function() return true end,
    IsBlocked=function(_,p)
        local area=containing(p)
        local x,y=relative(area,p)
        return math.abs(x)<128 and math.abs(y)<128
    end,
    FindPathLength=function(_,a,b)
        local area=containing(a)
        assert(containing(b)==area,'contact navigation crossed into another player area')
        path_calls=path_calls+1
        local key=area.id..':'..tostring(clock)
        path_bursts[key]=(path_bursts[key] or 0)+1
        assert(path_bursts[key]<=16,'one wall exceeded its bounded path budget at a fixed game time')
        if area.blocked or (area.block_face and face(area,b)==area.block_face) then return -1 end
        return corner_path(area,a,b)
    end,
}
-- Preferred-face cases represent registered straight gates. Share their
-- cached terrain opening with the allocator, rather than an open-floor row.
package.loaded['systems/wall_navigation_service']={contact_layout=function(wall)
    local area=containing(wall:GetAbsOrigin())
    if area.gate then
        local axis=area.rotation%2==0 and 1 or 2
        local center=axis==1 and area.y or area.x
        return {gate=true,axis=axis,min=center-128,max=center+128,center=center}
    end
end}
local contact=require('systems/wall_melee_contact')
local function entity(p,radius)
    next_id=next_id+1
    local id=next_id
    local u={p=copy(p),radius=radius or 32,survival_monster_hull_radius=radius or 32}
    function u:entindex() return id end
    function u:GetAbsOrigin() return self.p end
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return not self.dead end
    function u:GetHullRadius() return self.radius end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:SetHullRadius(value) self.radius=value end
    return u
end
local function reset()
    contact.reset()
    clock,areas,path_calls,curved_paths,path_bursts=0,{},0,0,{}
end
local function area_new(rotation,x)
    local area={id=#areas+1,rotation=rotation or 0,x=x or 0,y=0,owners={}}
    areas[#areas+1]=area
    area.wall=entity(point(area,0,0),128)
    return area
end
local function arrivals(area,count)
    local result={}
    for index=1,count do
        result[index]=entity(point(area,-400,({-96,-32,32,96})[(index-1)%4+1]))
    end
    return result
end
local function retain(area)
    for _,owner in ipairs(area.owners) do
        if owner.unit:IsAlive() then
            local before=path_calls
            local plan=assert(contact.resolve(area.wall,owner.unit,owner.preferred))
            assert(plan.claimed and distance(plan.point,owner.point)<.001,'stable owner lost its reserved face')
            assert(path_calls==before,'retained contact unnecessarily recalculated a path')
        end
    end
end
local function admit(area,units,preferred)
    local admitted=0
    for _,unit in ipairs(units) do
        if not unit.admitted then
            local plan=assert(contact.resolve(area.wall,unit,preferred))
            if plan.claimed then
                unit.admitted=true;unit.p=copy(plan.point)
                assert(contact.settle(area.wall,unit,plan.point),'stationary routing fixture must actually settle')
                assert(unit:GetHullRadius()==20 and unit:GetPaddedCollisionRadius()==30,
                    '64-unit contact lanes must retain clearance for native padded bodies')
                area.owners[#area.owners+1]={unit=unit,point=copy(plan.point),preferred=preferred}
            else
                assert(unit:GetHullRadius()==32,'unadmitted body inherited a tactical collision hull')
            end
        end
        if unit.admitted then admitted=admitted+1 end
    end
    local counts,slots={0,0,0,0},{}
    for _,owner in ipairs(area.owners) do
        if owner.unit:IsAlive() then
            local side=face(area,owner.point)
            counts[side]=counts[side]+1
            assert(counts[side]<=4,'one wall face admitted more than four attackers')
            local key=owner.point.x..':'..owner.point.y
            assert(not slots[key],'two owners reserved the same fixed contact')
            slots[key]=true
            for _,other in ipairs(area.owners) do
                if other~=owner and other.unit:IsAlive() then
                    assert(distance(owner.point,other.point)>=owner.unit:GetPaddedCollisionRadius()
                        +other.unit:GetPaddedCollisionRadius()-.01,
                        'exclusive contacts must also fit both native padded collision bodies')
                end
            end
        end
    end
    return admitted,counts
end
local function fill(area,units,target,preferred)
    for _=1,24 do
        retain(area)
        local admitted,counts=admit(area,units,preferred)
        if admitted==target then return counts end
        clock=clock+.5
    end
    error('same-entry arrivals failed to occupy '..target..' reachable contacts')
end
local function check(name,fn)
    reset()
    local ok,message=pcall(fn)
    if ok then cases=cases+1 else failures[#failures+1]=name..': '..tostring(message) end
end

for rotation=0,3 do
    check('open routing rotation '..rotation,function()
        local area=area_new(rotation)
        local units=arrivals(area,16)
        local counts=fill(area,units,16)
        for side=1,4 do assert(counts[side]==4,'one reachable face remained empty') end
        assert(curved_paths>0,'rear contacts were never reached through an outside-corner path')
        local overflow=arrivals(area,32)
        local before=path_calls
        for _=1,6 do
            clock=clock+.5;retain(area)
            assert(admit(area,overflow)==0,'seventeenth attacker exceeded the wall capacity')
        end
        assert(path_calls==before,'stable full wall searched paths for waiting monsters')
        local victim=area.owners[#area.owners].unit
        victim.dead=true
        local replacement={overflow[1]}
        fill(area,replacement,1)
        assert(victim:GetHullRadius()==32,'dead contact did not recover its original hull')
        local alive_count=0
        for _,owner in ipairs(area.owners) do if owner.unit:IsAlive() then alive_count=alive_count+1 end end
        assert(alive_count==16,'one death must create exactly one replacement slot')
    end)
    check('sealed preferred face rotation '..rotation,function()
        local area=area_new(rotation)
        area.gate=true
        local units=arrivals(area,20)
        local preferred=face(area,point(area,-400,0))
        fill(area,units,4,preferred)
        local before=path_calls
        for _=1,6 do
            clock=clock+.5;retain(area)
            assert(admit(area,units,preferred)==4,'sealed gate reassigned its overflow to another face')
        end
        assert(path_calls==before,'full sealed gate repeatedly searched inaccessible other faces')
    end)
end

check('unreachable local face uses reachable sides',function()
    local area=area_new(0)
    area.block_face=1
    local units=arrivals(area,12)
    local counts=fill(area,units,12)
    assert(counts[1]==0 and counts[2]==4 and counts[3]==4 and counts[4]==4,
        'unreachable path reserved a local slot or stranded reachable side contacts')
end)

check('failed path cache invalidates after occupancy changes',function()
    local area=area_new(0)
    local original=arrivals(area,5)
    fill(area,original,5)
    local victim=area.owners[#area.owners].unit
    assert(face(area,victim.p)~=1,'failure-cache fixture needs a vacancy on a different face')
    area.blocked=true
    clock=clock+.5
    local waiting=arrivals(area,1)
    assert(admit(area,waiting)==0,'failed paths consumed a contact reservation')
    local before=path_calls
    assert(admit(area,waiting)==0 and path_calls==before,'unchanged failed paths were immediately retried')
    -- Simulate the existing death callback. Releasing a different face keeps
    -- the local front envelope unchanged, so only occupancy revision can
    -- invalidate this young cache entry (not an incidental spacing change).
    victim.dead=true
    contact.release(area.wall:entindex(),victim:entindex())
    area.blocked=false
    clock=clock+.5
    local admitted=admit(area,waiting)
    assert(admitted==1,'occupancy change did not invalidate the younger-than-two-second failure cache')
    assert(path_calls>before,'released occupancy never retried an available real path')
end)

check('four walls have independent routing budgets and ownership',function()
    local all={}
    for rotation=0,3 do
        local area=area_new(rotation,rotation*5000)
        all[#all+1]={area=area,units=arrivals(area,16)}
    end
    local completed=false
    for _=1,24 do
        completed=true
        for _,entry in ipairs(all) do
            retain(entry.area)
            local admitted=admit(entry.area,entry.units)
            assert(admitted>0,'another wall exhausted this player area routing budget')
            if admitted<16 then completed=false end
        end
        if completed then break end
        clock=clock+.5
    end
    assert(completed,'four independent walls did not recover after bounded routing pauses')
    local before=path_calls
    for _,entry in ipairs(all) do
        retain(entry.area)
        assert(admit(entry.area,arrivals(entry.area,8))==0,'full player wall admitted overflow')
    end
    assert(path_calls==before,'four full player walls repeated navigation work')
end)

contact.reset()
assert(#failures==0,table.concat(failures,'\n'))
print('WALL_OPEN_FACE_ROUTING_PASS cases='..cases
    ..' same_entry_contacts=16 rotations=4 independent_walls=4 bounded_paths stable_full_paths=0')
