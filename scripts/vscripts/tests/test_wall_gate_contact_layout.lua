-- Real geometry, native-obstruction footprints and contact allocator. Paths
-- use an independent visibility graph around physical bodies; no Dota process.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,queries,paths,created,removed,writes=0,0,0,0,0,0
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
local q,offset,bias,width=0,0,-32,384
local obstacles={}
local base=Vector(1280,4928,384)
local function rotate(x,y,n)
    for _=1,n do x,y=-y,x end
    return x,y
end
local function world(n,l)
    local x,y=rotate(n,l,q);return Vector(base.x+x,base.y+y,384)
end
local function local_point(p) return rotate(p.x-base.x,p.y-base.y,(4-q)%4) end
local function terrain(p)
    local _,l=local_point(p);return l>bias-width/2 and l<bias+width/2
end
local function covered(o,p)
    return not o.deleted and p.x>=o.p.x-64 and p.x<o.p.x+64
        and p.y>=o.p.y-64 and p.y<o.p.y+64
end
local function clear(p,radius)
    for _,o in ipairs({{0,0},{radius-1,0},{1-radius,0},{0,radius-1},{0,1-radius}}) do
        local s=Vector(p.x+o[1],p.y+o[2],384)
        if not terrain(s) then return false end
        for _,block in ipairs(obstacles) do if covered(block,s) then return false end end
    end
    return true
end
local function segment(a,b)
    local d=math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    for i=0,math.max(1,math.ceil(d/8)) do
        local t=i/math.max(1,math.ceil(d/8))
        if not clear(Vector(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,384),32) then return false end
    end
    return true
end
local function route(a,b)
    if not clear(a,32) or not clear(b,32) then return -1 end
    local nodes={a,b}
    for _,n in ipairs({-161,161}) do for _,l in ipairs({offset-161,offset+161}) do
        nodes[#nodes+1]=world(n,l)
    end end
    local lengths,visited={[1]=0},{}
    for _=1,#nodes do
        local current,best
        for i=1,#nodes do if not visited[i] and lengths[i]
            and (not best or lengths[i]<best) then current,best=i,lengths[i] end end
        if not current then return -1 end
        if current==2 then return best end
        visited[current]=true
        for i=1,#nodes do if not visited[i] and segment(nodes[current],nodes[i]) then
            local value=best+math.sqrt((nodes[current].x-nodes[i].x)^2+(nodes[current].y-nodes[i].y)^2)
            if not lengths[i] or value<lengths[i] then lengths[i]=value end
        end end
    end
    return -1
end
GridNav={IsTraversable=function(_,p) queries=queries+1;return terrain(p) end,
    IsBlocked=function(_,p)
        queries=queries+1
        for _,o in ipairs(obstacles) do if covered(o,p) then return true end end
        return false
    end,
    FindPathLength=function(_,a,b) paths=paths+1;return route(a,b) end}
SpawnEntityFromTableSynchronous=function(name,kv)
    assert(name=='point_simple_obstruction')
    local o={p=kv.origin,IsNull=function(self) return self.deleted==true end}
    obstacles[#obstacles+1]=o;created=created+1;return o
end
DoEntFireByInstanceHandle=function() end
UTIL_Remove=function(o) assert(not o.deleted);o.deleted=true;removed=removed+1 end
local function actor(id,p,radius)
    local u={p=p,radius=radius or 32,hull_writes=0}
    function u:entindex() return id end
    function u:IsNull() return false end
    function u:IsAlive() return not self.dead end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return self.radius end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:SetHullRadius(value) self.radius=value;self.hull_writes=self.hull_writes+1 end
    function u:SetAbsOrigin(value) self.p=value;writes=writes+1 end
    return u
end
local navigation=require('systems/wall_navigation_service')
local contact=require('systems/wall_melee_contact')
local cases=0
for rotation=0,3 do for _,shift in ipairs({-64,0,64}) do
    navigation.clear_all();contact.reset();obstacles={};q=rotation;offset=shift;clock=0
    local wall=actor(1,world(0,offset),128)
    local count_before=created
    navigation.create(wall)
    assert(created-count_before==4,'wall must create exactly four physical square blockers')
    local layout=assert(navigation.contact_layout(wall))
    assert(not layout.gate,'a wider real staircase must preserve its actual side gaps')
    local scout=actor(2,world(-400,offset))
    assert(navigation.contact_face(wall,scout)==nil,'open side route must not force a single attack face')
    local hull_before,path_before=scout.hull_writes,paths
    local candidates=contact.approach_points(wall,scout)
    assert(scout.hull_writes==hull_before and paths==path_before,
        'read-only approach candidates must not mutate hull or search paths')
    local front,seen=0,{}
    -- Independent corridor bounds: Hull32 leaves legal centers strictly
    -- between -193 and129. Four padded42 bodies fit at pitch84; shifts-64/0
    -- need no displacement, while shift64 needs the smallest grid shift-64.
    local expected_center=shift==64 and -64 or 0
    local expected_pitch,expected_front=84,4
    for _,c in ipairs(candidates) do
        local n,l=local_point(c.point)
        if n==-184 then
            front=front+1
            local relative=l-offset
            local authored=relative-expected_center
            assert(authored==-126 or authored==-42 or authored==42 or authored==126,
                'repair must make only the smallest bounded shift of the solid native row')
            local world_center=expected_center*((rotation==1 or rotation==2) and -1 or 1)
            assert(c.lateral_center==world_center and c.lane_pitch==expected_pitch,
                'a wider row must retain native padded-body spacing and its own wait geometry: rotation='
                    ..rotation..' wall_shift='..shift..' center='..c.lateral_center..' pitch='..c.lane_pitch)
            assert(clear(c.point,32),'offered contact intersects static terrain or wall body')
            seen[l]=true
        end
    end
    assert(front==expected_front,
        'the real offset staircase must retain four full native front bodies')
    local query_before=queries
    for _=1,100 do assert(contact.approach_points(wall,scout)==candidates) end
    assert(queries==query_before,'stable candidate reads must use shared geometry cache')
    local owners={}
    for i=1,front do
        local u=actor(10+i,world(-400,offset))
        local plan=assert(contact.resolve(wall,u))
        assert(plan.claimed,'each real front slot must accept an owner')
        local n,l=local_point(plan.point)
        assert(n==-184 and seen[l],'front arrivals must use the real surviving front slots')
        assert(u.radius==32 and u.hull_writes==0,'contact admission must preserve the fixed native body')
        u.p=plan.point;assert(contact.settle(wall,u,plan.point));owners[#owners+1]=u
    end
    do
        local extra=actor(30,world(-400,offset))
        local plan=assert(contact.resolve(wall,extra))
        assert(plan.claimed,'remaining enemy must route through a real gap to another attack face')
        local n,l=local_point(plan.point)
        assert(n~=-184 and route(extra.p,plan.point)>=0,'overflow must use a genuinely reachable other face')
        local victim=owners[2];local old=victim.p;victim.dead=true
        local replacement=actor(31,world(-400,offset))
        local next_plan=assert(contact.resolve(wall,replacement))
        assert(not next_plan.claimed or next_plan.point.x~=old.x or next_plan.point.y~=old.y,
            'a later same-distance callback must not steal the already observed remote owner nomination')
        next_plan=assert(contact.resolve(wall,extra))
        assert(next_plan.claimed and next_plan.point.x==old.x and next_plan.point.y==old.y,
            'the nearest observed remote owner must release its old route and refill exactly the physical vacant front slot')
    end
    -- Stay outside the rear-queue admission area; this assertion owns the
    -- existing verified long-distance waypoint path, before local queueing.
    local distant=actor(40,world(-1400,offset))
    local chosen=candidates[1].point
    distant.survival_wall_route={wall=wall,revision=0,point=chosen}
    local nav_before,path_before=queries,paths
    local plan=assert(contact.resolve(wall,distant))
    assert(not plan.claimed and plan.point==chosen and distant.radius==32 and distant.hull_writes==0,
        'far route must use verified point without premature reservation or phasing')
    assert(queries==nav_before and paths==path_before,'verified route must not query navigation again')
    wall.survival_wall_relocation_revision=1
    local stale=assert(contact.resolve(wall,distant))
    assert(stale.point~=chosen,'wall move revision must invalidate its old far waypoint')
    distant.survival_wall_route={wall={},revision=1,point=chosen}
    stale=assert(contact.resolve(wall,distant))
    assert(stale.point~=chosen,'another wall handle must not lend its route waypoint')
    distant.survival_wall_route=nil
    local traversable=GridNav.IsTraversable
    GridNav.IsTraversable=function() queries=queries+1;return false end
    clock=3
    assert(contact.resolve(wall,distant)==nil,
        'no safe far staging point must fall back to chase instead of a dead waiting MOVE')
    GridNav.IsTraversable=traversable
    cases=cases+1
end end
-- The installed native stair is symmetric384: centered64 seams close, while
-- one-cell tangent shifts leave a128 side route. One/two-cell shifts fit four
-- native bodies on the original floor without adding any physical blockers.
bias=0
for rotation=0,3 do for _,shift in ipairs({-128,-64,0,64,128}) do
    navigation.clear_all();contact.reset();obstacles={};q=rotation;offset=shift;clock=0
    local wall=actor(101,world(0,offset),128)
    local count_before=created;navigation.create(wall)
    assert(created-count_before==(offset==0 and 8 or 4),
        'only two centered64 seams may add finite blockers')
    local layout=assert(navigation.contact_layout(wall))
    assert(layout.gate==(offset==0),'one-sided128 gap must retain open-face routing')
    local scout=actor(102,world(-400,offset))
    local candidates=contact.approach_points(wall,scout)
    local front,front_points=0,{}
    for _,c in ipairs(candidates) do
        local n=local_point(c.point)
        if n==-184 then
            front=front+1;front_points[#front_points+1]=c.point
            local center=offset==0 and 0 or (offset<0 and 1 or -1)*(math.abs(offset)-32)
            local sign=(rotation==1 or rotation==2) and -1 or 1
            assert(c.lateral_center==center*sign and c.lane_pitch==(offset==0 and 88 or 84),
                'centered valid rows stay authored; displaced rows use the smallest native-body fit')
            assert(clear(c.point,32),'a fitted endpoint must retain its whole native hull on original terrain')
        end
    end
    assert(front==4,'one/two-cell displacements must retain exactly four native front contacts')
    for i=1,#front_points do for j=i+1,#front_points do
        local a,b=front_points[i],front_points[j]
        assert((a.x-b.x)^2+(a.y-b.y)^2>=84^2,'fitted front contacts preserve padded42 separation')
    end end
    if offset==0 then
        assert(#candidates==8,'closed centered stair must expose only front/back contacts')
        assert(GridNav:IsBlocked(world(0,-192)) and GridNav:IsBlocked(world(0,192)),
            'centered corner seams must be physically blocked')
    else
        local gap=world(0,offset>0 and -128 or 128)
        assert(GridNav:IsTraversable(gap) and not GridNav:IsBlocked(gap),
            'tangent displacement must preserve the actual open side route')
    end
    cases=cases+1
end end
-- When both smaller pitches fit without moving the row, retain the wider
-- native spacing: this324 opening rejects authored88 but safely admits86.
width=324
for rotation=0,3 do
    navigation.clear_all();contact.reset();obstacles={};q=rotation;offset=0;clock=0
    local wall=actor(201,world(0,0),128)
    local count_before=created;navigation.create(wall)
    assert(created-count_before==8,'the same bounded corner seams remain physical navigation')
    local scout,front=actor(202,world(-400,0)),0
    for _,c in ipairs(contact.approach_points(wall,scout)) do
        local n=local_point(c.point)
        if n==-184 then
            front=front+1
            assert(c.lane_pitch==86 and c.lateral_center==0,'equal-displacement fits prefer the wider safe pitch')
            assert(clear(c.point,32),'pitch86 retains full terrain clearance')
        end
    end
    assert(front==4,'the narrower opening still admits only four native front bodies')
    cases=cases+1
end
navigation.clear_all();contact.reset()
assert(created==removed,'physical registration or contact lifecycle leaked native blockers')
assert(writes==0,'contact settlement or lifecycle must never write world coordinates')
print('WALL_GATE_CONTACT_LAYOUT_PASS cases='..cases..' four_rotations Hull32 padded42 pitch88_86_84 centered64_seams_only tangent64_and128_four_front bounded_minimal_shift terrain_filtered_slots real_side_route death_refill read_only_cached_candidates verified_far_route stale_route_rejected blocked_stage_fallback no_position_writes')
