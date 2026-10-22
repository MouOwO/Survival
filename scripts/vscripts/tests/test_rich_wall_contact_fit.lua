-- Reproduce the observed rich east wall without inventing a doorway layout:
-- wall(-896,-10112,256), front x=-1080, three authored contacts, and a
-- 320-wide walkable front strip. The original native navigation stays intact.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 256} end
local clock,rotation,queries,paths,bodies,writes,hull_writes=0,0,0,0,0,0,0
local lower,upper,interior_obstacle=-128,192,false
local wall_lateral,divider_low,divider_high=0,nil,nil
local origin=Vector(-896,-10112,256)
local actors={}
local function rotate(x,y,q)
    for _=1,q do x,y=-y,x end
    return x,y
end
local function world(n,l)
    local x,y=rotate(n,l,rotation)
    return Vector(origin.x+x,origin.y+y,n<-128 and 228 or 256)
end
local function local_point(p)
    return rotate(p.x-origin.x,p.y-origin.y,(4-rotation)%4)
end
local function terrain(p)
    local n,l=local_point(p)
    if n<-128 and (l<lower or l>=upper) then return false end
    if n<-128 and divider_low and l>=divider_low and l<divider_high then return false end
    return not (interior_obstacle and math.abs(n+184)<1 and math.abs(l+44)<1)
end
local function blocked(p)
    local n,l=local_point(p)
    return math.abs(n)<128 and math.abs(l-wall_lateral)<128
end
GetGroundHeight=function(p)
    local n=local_point(p)
    return n<-128 and 228 or 256
end
GameRules={GetGameTime=function() return clock end}
GridNav={IsTraversable=function(_,p) queries=queries+1;return terrain(p) end,
    IsBlocked=function(_,p) queries=queries+1;return blocked(p) end,
    FindPathLength=function(_,a,b)
        paths=paths+1
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    end}
DOTA_UNIT_TARGET_TEAM_BOTH=3;DOTA_UNIT_TARGET_BASIC=1;DOTA_UNIT_TARGET_HERO=2
DOTA_UNIT_TARGET_FLAG_INVULNERABLE=1;DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=2;FIND_ANY_ORDER=0
FindUnitsInRadius=function()
    bodies=bodies+1
    return actors
end
local function actor(id,n,l,padded)
    local u={p=world(n,l),padded=padded or 42}
    function u:entindex() return id end
    function u:IsNull() return false end
    function u:IsAlive() return not self.dead end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return id==1 and 128 or 32 end
    function u:GetPaddedCollisionRadius() return self.padded end
    function u:GetTeamNumber() return 3 end
    function u:SetAbsOrigin() writes=writes+1;error('a fit must never teleport a unit') end
    function u:SetHullRadius() hull_writes=hull_writes+1;error('a fit must never shrink a body') end
    actors[#actors+1]=u
    return u
end
package.loaded['systems/wall_navigation_service']={contact_layout=function() return nil end}
local contact=require('systems/wall_melee_contact')
local function full_body_clear(point)
    for _,o in ipairs({{0,0},{31,0},{-31,0},{0,31},{0,-31}}) do
        local sample=Vector(point.x+o[1],point.y+o[2],point.z)
        if not terrain(sample) or blocked(sample) then return false end
    end
    return true
end
local function front_candidates(wall,unit)
    local result={}
    for _,candidate in ipairs(contact.approach_points(wall,unit)) do
        local n=local_point(candidate.point)
        if n==-184 then result[#result+1]=candidate end
    end
    return result
end
local cold_queries=0
for q=0,3 do
    contact.reset();rotation=q;clock=0;actors={}
    lower,upper,interior_obstacle=-128,192,false
    local wall=actor(1,0,0)
    local scout=actor(2,-400,-10)
    local authored=0
    for _,l in ipairs({-132,-44,44,132}) do
        if full_body_clear(world(-184,l)) then authored=authored+1 end
    end
    assert(authored==3,'recorded rich navigation must reject exactly one original outer slot')
    local before_queries,before_paths,before_bodies=queries,paths,bodies
    local candidates=front_candidates(wall,scout)
    cold_queries=math.max(cold_queries,queries-before_queries)
    assert(#candidates==4,'the rich wall must offer four full-body contacts without a doorway layout')
    assert(paths==before_paths and bodies==before_bodies,
        'read-only fit must never search paths or scan live units')
    assert(queries-before_queries<=4096,'one shared fit must keep a bounded terrain-query budget: '
        ..(queries-before_queries))
    local sign=(q==1 or q==2) and -1 or 1
    local seen={}
    for _,candidate in ipairs(candidates) do
        local n,l=local_point(candidate.point)
        assert(n==-184 and (l==-94 or l==-10 or l==74 or l==158),
            '320-wide front must fit the native84 pitch with the smallest32 shift')
        assert(candidate.lane_pitch==84 and candidate.lateral_center==32*sign,
            'the fitted row must expose its actual native body spacing and center')
        assert(full_body_clear(candidate.point),'all five body samples must remain on original navigable terrain')
        assert(math.abs(l)<184,'repair must retain the physical front face')
        seen[l]=true
    end
    for i=1,4 do for j=i+1,4 do
        local a,b=candidates[i].point,candidates[j].point
        assert((a.x-b.x)^2+(a.y-b.y)^2>=84^2,'native padded bodies must not overlap')
    end end
    local shared=contact.approach_points(wall,scout)
    before_queries=queries
    for _=1,100 do assert(contact.approach_points(wall,scout)==shared) end
    assert(queries==before_queries,'a dense queue must reuse the shared two-second fit cache')
    local padded=actor(3,-400,0,43)
    assert(#front_candidates(wall,padded)==3,
        'the same hull with larger native padding must not inherit an unsafe84-pitch cache')
    assert(#front_candidates(wall,scout)==4,'returning to native42 padding must restore the valid fitted row')
    before_queries=queries
    for _=1,50 do
        assert(#front_candidates(wall,padded)==3 and #front_candidates(wall,scout)==4)
    end
    assert(queries==before_queries,'mixed native padding must retain independent shared geometry caches')
    local face=q+1
    if q==1 then face=3 elseif q==2 then face=2 elseif q==3 then face=4 end
    local front={}
    for i,l in ipairs({-94,-10,74,158}) do
        local u=actor(10+i,-400,l)
        local plan=assert(contact.resolve(wall,u,face))
        assert(plan.claimed and seen[select(2,local_point(plan.point))],
            'all four real arrivals must acquire a distinct repaired contact')
        u.p=plan.point
        assert(contact.settle(wall,u,plan.point),'each contact must pass native body admission')
        front[#front+1]=u
    end
    local fifth=actor(20,-400,-10)
    local wait=assert(contact.resolve(wall,fifth,face))
    assert(not wait.claimed and wait.point,'a fifth attacker must wait outside the four solid contacts')
    local wait_n=local_point(wait.point)
    assert(full_body_clear(wait.point) and wait_n<=-276,
        'the rear goal must use real terrain behind the front without sharing a front lane')
    local victim=front[2];victim.dead=true
    local refill=assert(contact.resolve(wall,fifth,face))
    assert(refill.claimed and refill.point==victim.p,'death must refill the exact vacated fitted contact')
    fifth.p=refill.point;assert(contact.settle(wall,fifth,refill.point));front[2]=fifth
    local waiters={}
    for i=1,90 do
        local u=actor(100+i,-400,({-94,-10,74,158})[(i-1)%4+1])
        assert(not contact.resolve(wall,u,face).claimed)
        waiters[#waiters+1]=u
    end
    -- New destinations use a shared bounded native-path budget. Finish that
    -- initial work before measuring stable crowd observation, while keeping
    -- the four live front owners observed through their normal lease cadence.
    for pass=1,16 do
        clock=pass*.5
        for _,u in ipairs(front) do assert(contact.resolve(wall,u,face).claimed) end
        for _,u in ipairs(waiters) do assert(not contact.resolve(wall,u,face).claimed) end
    end
    before_queries,before_paths,before_bodies=queries,paths,bodies
    for pass=1,30 do
        clock=8+pass*.05
        for _,u in ipairs(front) do assert(contact.resolve(wall,u,face).claimed) end
        for _,u in ipairs(waiters) do assert(not contact.resolve(wall,u,face).claimed) end
    end
    assert(queries==before_queries and paths==before_paths and bodies==before_bodies,
        'stable ninety-unit fitted queues must add no terrain, path or body queries')
    clock=10.1
    before_queries,before_paths,before_bodies=queries,paths,bodies
    assert(#front_candidates(wall,scout)==4,'cache expiry must preserve the same legal four-body fit')
    assert(queries-before_queries<=4096 and paths==before_paths and bodies==before_bodies,
        'expired fit refresh must remain bounded and independent of the ninety waiting units')
end
-- Keep the actual stair fixed while moving the physical wall by one/two
-- cells. Depending on direction the authored row retains only two contacts;
-- one additional partial-row case retains one. All four fitted bodies still
-- occupy the same continuous strip, rather than following the wall into a bank.
local moved_cases=0
for q=0,3 do for _,shift in ipairs({-160,-128,-64,0,64,128}) do
    contact.reset();rotation=q;clock=0;actors={}
    lower,upper,interior_obstacle=-128,192,false
    wall_lateral,divider_low,divider_high=shift,nil,nil
    local wall=actor(1,0,shift)
    local scout=actor(2,-400,32)
    local before_queries,before_paths,before_bodies=queries,paths,bodies
    local candidates=front_candidates(wall,scout)
    assert(#candidates==4,'moved wall must fit all four native front contacts: '..q..':'..shift)
    assert(paths==before_paths and bodies==before_bodies,'fitting moved walls must remain read-only geometry')
    assert(queries-before_queries<=8192,'large moved-wall fits retain a bounded shared query budget')
    local sign=(q==1 or q==2) and -1 or 1
    local seen={}
    for _,candidate in ipairs(candidates) do
        local n,l=local_point(candidate.point)
        assert(n==-184 and (l==-94 or l==-10 or l==74 or l==158),
            'moving the wall must not move the fitted row through the original stair bank')
        assert(candidate.lateral_center==(32-shift)*sign and candidate.lane_pitch==84)
        assert(full_body_clear(candidate.point),'all moved contacts retain their complete native hull')
        assert(not seen[l],'only four exclusive front keys may exist');seen[l]=true
    end
    for i=1,4 do for j=i+1,4 do
        local a,b=candidates[i].point,candidates[j].point
        assert((a.x-b.x)^2+(a.y-b.y)^2>=84^2,'moved contacts preserve padded42 separation')
    end end
    local shared=contact.approach_points(wall,scout)
    before_queries=queries
    for _=1,90 do assert(contact.approach_points(wall,scout)==shared) end
    assert(queries==before_queries,'moving walls must still share cached geometry across the crowd')
    moved_cases=moved_cases+1
end end
wall_lateral=0
-- Wider open fronts keep authored geometry. A smaller true opening, a larger
-- body or an interior obstacle must never force an unsafe fit. The thin divider
-- lies between the four proposed hull samples; only continuous row validation
-- detects it and prevents a row spanning two disconnected floor sections.
for _,case in ipairs({
    {lower=-192,upper=192,count=4,pitch=88,center=0},
    {lower=-128,upper=186,count=3},
    {lower=-192,upper=96,count=3},
    {lower=-192,upper=192,interior=true,count=3},
    {lower=-128,upper=192,divider_low=28,divider_high=36,count=3},
}) do
    contact.reset();actors={};rotation=0;clock=0
    lower,upper,interior_obstacle=case.lower,case.upper,case.interior==true
    divider_low,divider_high=case.divider_low,case.divider_high
    local wall=actor(1,0,0)
    local scout=actor(2,-400,0)
    local candidates=front_candidates(wall,scout)
    assert(#candidates==case.count,'unsafe or unnecessary repair must retain the original terrain capacity: '
        ..case.lower..':'..case.upper..':'..tostring(case.interior)..':'..tostring(case.divider_low)
        ..' expected='..case.count..' actual='..#candidates)
    for _,candidate in ipairs(candidates) do
        assert(full_body_clear(candidate.point),'fallback contacts must still pass full-body terrain checks')
        if case.pitch then
            assert(candidate.lane_pitch==case.pitch and candidate.lateral_center==case.center,
                'an already valid row must keep its authored geometry')
        end
    end
end
assert(writes==0 and hull_writes==0,'fitting contacts must never alter native positions or hull radii')
print('RICH_WALL_CONTACT_FIT_PASS rotations=4 recorded_three_to_four pitch84 shift32 layout_nil'
    ..' moved_wall_cases='..moved_cases..' partial_one_two_three continuous_divider_rejected'
    ..' full_native_bodies death_refill same_hull_different_padding ninety_waiters stable_queries=0'
    ..' cold_nav_budget='..cold_queries..' bounded_ttl_refresh partial_fallback unchanged_valid_rows no_position_or_hull_writes')
