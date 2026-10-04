package.path="scripts/vscripts/?.lua;"..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 0} end
local stamp=0
GameRules={GetGameTime=function() return stamp end}
GetGroundHeight=function() return 384 end
local paths=0
GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end,
    FindPathLength=function(_,a,b)
        paths=paths+1
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    end}
local function unit(id,x,y,radius)
    local u={p=Vector(x,y,384),radius=radius or 32}
    function u:entindex() return id end
    function u:GetAbsOrigin() return self.p end
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return not self.dead end
    function u:GetHullRadius() return self.radius end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    return u
end
local contact=require("systems/wall_melee_contact")
local wall=unit(1,0,0,128)
local front={}
local chosen={}
for i=1,4 do
    front[i]=unit(i+1,-400,(i-2.5)*64)
    local p=assert(contact.resolve(wall,front[i]))
    assert(p.claimed and p.point.x==-192 and p.point.y==(i-2.5)*64,
        "each monster gets its nearest lane on the reachable face")
    chosen[i]=p.point;front[i].p=p.point
    local reach=contact.attack_range(front[i],wall)
    local d=math.sqrt(p.point.x^2+p.point.y^2)
    assert(reach+front[i]:GetPaddedCollisionRadius()+wall:GetPaddedCollisionRadius()>=d,
        "edge and corner contacts must both be in native attack reach")
end
local before=paths
for _,u in ipairs(front) do assert(contact.resolve(wall,u).claimed) end
assert(paths==before,"retained contacts never recalculate paths each tick")
local fifth=unit(6,-380,40)
local waiting=contact.resolve(wall,fifth)
assert(not waiting.claimed and waiting.point.x==-264,"Hull32 overflow waits one body diameter plus eight behind the front")
assert(paths==before,"full front does not run path searches for every waiting monster")
local other_side=unit(7,350,0)
assert(contact.resolve(wall,other_side).point.x==-296,
    "a full engaged face never sends overflow through the gate to the rear")
front[3].dead=true
local refill=contact.resolve(wall,fifth)
assert(refill.claimed and refill.point.y==32,"dead front unit is replaced in its vacated lane")
-- No first-arrival orientation: a new wall is approached from any valid side.
contact.reset()
local far=unit(10,-900,0)
assert(contact.resolve(wall,far)==nil,"spawn-distance units cannot reserve contacts")
local north=unit(11,40,400)
local p=contact.resolve(wall,north)
assert(p.claimed and p.point.y==192 and p.point.x==32)
contact.release(1,11)
-- Nearest geometric point can be unreachable; choose the shortest real path.
GridNav.FindPathLength=function(_,a,b)
    if b.x<0 then return -1 end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
local west=unit(12,-400,0)
p=contact.resolve(wall,west)
assert(p.claimed and p.point.x>=0,"reject unreachable slots")
stamp=3
local other=unit(13,400,0)
assert(contact.resolve(wall,other).claimed,"stale claims release without a FIFO queue")
contact.clear(1)

local nav_queries,nav_samples,next_id=0,{},100
local function coordinate(face,normal,lateral)
    if face==1 then return Vector(-normal,lateral,384) end
    if face==2 then return Vector(normal,lateral,384) end
    if face==3 then return Vector(lateral,-normal,384) end
    return Vector(lateral,normal,384)
end
local function normal_of(face,p)
    if face==1 then return -p.x elseif face==2 then return p.x
    elseif face==3 then return -p.y else return p.y end
end
local function lateral_of(face,p) return face<=2 and p.y or p.x end
local function actor(face,normal,lateral,radius)
    next_id=next_id+1
    local p=coordinate(face,normal,lateral)
    return unit(next_id,p.x,p.y,radius)
end
local function corridor(face,blocked)
    GridNav.IsTraversable=function(_,p)
        nav_queries=nav_queries+1;nav_samples[#nav_samples+1]=p
        return math.abs(lateral_of(face,p))<128
    end
    GridNav.IsBlocked=function(_,p)
        nav_queries=nav_queries+1
        return (math.abs(p.x)<128 and math.abs(p.y)<128) or (blocked and blocked(p)) or false
    end
    GridNav.FindPathLength=function(_,a,b)
        paths=paths+1
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    end
end
local function fill_front(face)
    contact.reset();stamp=0;corridor(face)
    local result={}
    for lane=1,4 do
        local u=actor(face,400,(lane-2.5)*64,32)
        local plan=assert(contact.resolve(wall,u))
        assert(plan.claimed and normal_of(face,plan.point)==192)
        u.p=plan.point;result[#result+1]=u
    end
    return result
end
local function await_plan(u)
    local plan=assert(contact.resolve(wall,u))
    assert(not plan.claimed,'waiting regression unexpectedly claimed a full contact row')
    return plan.point
end

-- Every wall face uses the same compact spacing. Native arrivals from behind
-- can stop 32 early; retreating units need their own extra allowance so they
-- do not stop inside the phased attacker's body.
for face=1,4 do
    fill_front(face)
    local rear=actor(face,400,40,32)
    local rear_goal=await_plan(rear)
    assert(normal_of(face,rear_goal)==264 and lateral_of(face,rear_goal)==32,
        'rear arrivals use a 72-unit contact-to-wait-goal gap on every face')
    local close=actor(face,224,40,32)
    local close_goal=await_plan(close)
    assert(normal_of(face,close_goal)==296 and lateral_of(face,close_goal)==32,
        'an existing inner waiter receives its own 104-unit retreat goal')
    assert(normal_of(face,close_goal)-32-192>=32+32+8,
        'native retreat acceptance must leave both bodies separated')
    assert(normal_of(face,rear_goal)+32-192==104,
        'ordinary native rear arrivals must not inherit the inner retreat allowance')
    local before_paths,before_nav=paths,nav_queries
    for pass=1,3 do
        stamp=pass*.5
        assert(await_plan(rear)==rear_goal and await_plan(close)==close_goal)
        assert(await_plan(actor(face,410+pass,45,32))==rear_goal,
            'different rear units of the same size must share validated geometry')
    end
    assert(paths==before_paths and nav_queries==before_nav,
        'cached full-row wait geometry must not run path or navigation work per waiter')
end

-- Two Hull64 bodies fill the physical row even though the global admission
-- cap is four. This takes the candidate-cache waiting branch, not full-count.
contact.reset();stamp=0;corridor(1)
for _,lateral in ipairs({-64,64}) do
    local u=actor(1,400,lateral,64)
    local plan=assert(contact.resolve(wall,u))
    assert(plan.claimed);u.p=plan.point
end
local small_behind_large=actor(1,400,40,32)
local large_row_goal=await_plan(small_behind_large)
assert(large_row_goal.x==-328 and large_row_goal.y==32,
    'physically full large-body front must use its real rear envelope for a small waiter')
local candidate_paths,candidate_nav=paths,nav_queries
for pass=1,3 do
    stamp=pass*.5
    assert(await_plan(small_behind_large)==large_row_goal)
end
assert(paths==candidate_paths and nav_queries==candidate_nav,
    'physically full front below the global cap must reuse candidate wait geometry')

-- Changing waiter size must sample that body's real hull. Large waiters also
-- move inward laterally instead of inheriting an outer Hull32 attack lane.
fill_front(1)
local small_waiter=actor(1,400,96,16)
local small_goal=await_plan(small_waiter)
assert(small_goal.x==-248 and small_goal.y==96)
local before_nav=nav_queries
nav_samples={}
local large_waiter=actor(1,400,96,64)
local large_goal=await_plan(large_waiter)
assert(large_goal.x==-296 and large_goal.y==64,
    'large waiter requires its own normal spacing and a hull-safe lateral goal')
assert(nav_queries>before_nav,'a small cached hull must not skip navigation checks for a larger waiter')
local sampled_outer_hull=false
for _,sample in ipairs(nav_samples) do
    if sample.x==-296 and sample.y==127 then sampled_outer_hull=true end
end
assert(sampled_outer_hull,'large waiter navigation must sample the actual outer hull')
before_nav=nav_queries
assert(await_plan(actor(1,420,96,64))==large_goal and nav_queries==before_nav,
    'identical large waiters reuse the validated larger-body goal')
local too_wide=actor(1,450,0,129)
assert(await_plan(too_wide)==too_wide.p,'a body wider than the passage must stay put rather than get an invalid wait goal')

-- Cache keys must not confuse an inner Hull32 waiter with an outer Hull32.5
-- waiter: hull multipliers are not rounded by monster_hull_scale.apply.
fill_front(1)
local inner_integer=actor(1,224,40,32)
assert(await_plan(inner_integer).x==-296)
before_nav=nav_queries
local fractional=actor(1,400,40,32.5)
local fractional_goal=await_plan(fractional)
assert(fractional_goal.x==-264.5 and nav_queries>before_nav,
    'fractional hull size must not collide with the integer inner-wait cache key')

-- A nearby small contact is not the entire front. A large unit in the next
-- lane sticks out farther; waiting spacing must cover all four contact hulls.
contact.reset();stamp=0;corridor(1)
local mixed={}
for _,spec in ipairs({{32,-32},{64,64},{1,-3},{1,-1}}) do
    local u=actor(1,400,spec[2],spec[1])
    local plan=assert(contact.resolve(wall,u))
    assert(plan.claimed,'mixed front fixture must have four distinct valid contacts')
    u.p=plan.point;mixed[#mixed+1]=u
end
local mixed_waiter=actor(1,400,-80,64)
local mixed_goal=await_plan(mixed_waiter)
assert(mixed_goal.x==-360 and mixed_goal.y==-32,
    'waiter must stand behind the adjacent large contact, even when the nearest contact is small')
for _,u in ipairs(mixed) do
    local dx,dy=mixed_goal.x-u.p.x,mixed_goal.y-u.p.y
    assert(dx*dx+dy*dy>=(mixed_waiter.radius+u.radius+8)^2,
        'mixed-body waiting goal overlaps a different front lane')
end
-- A changed envelope invalidates existing size caches without a timer or a
-- new path query. The existing fixed waiting AI goal is tested separately.
mixed[2].radius=80
before_nav=nav_queries
assert(await_plan(mixed_waiter).x==-376 and nav_queries>before_nav,
    'changed front hull extent must invalidate the cached wait geometry')

-- A blocked destination falls back to each caller's own position, including
-- a cached negative result. Other sizes/retreat modes still get their own test.
fill_front(1)
corridor(1,function(p) return p.x==-264 and p.y==32 end)
local blocked_waiter=actor(1,400,40,32)
assert(await_plan(blocked_waiter)==blocked_waiter.p,'blocked compact wait goal must fall back to the caller position')
before_nav=nav_queries
local second_blocked=actor(1,440,40,32)
assert(await_plan(second_blocked)==second_blocked.p and nav_queries==before_nav,
    'negative cache must not share the first waiter position or resample every caller')
local inner_unblocked=actor(1,224,40,32)
assert(await_plan(inner_unblocked).x==-296,'blocked normal goal must not poison the separate retreat goal')

fill_front(1)
corridor(1,function(p) return p.x==-296 and p.y==127 end)
local small_unblocked=actor(1,400,96,16)
assert(await_plan(small_unblocked).x==-248)
local peripheral_blocked=actor(1,400,96,64)
assert(await_plan(peripheral_blocked)==peripheral_blocked.p,
    'a clear center cannot authorize a waiting goal whose larger hull touches an obstacle')
before_nav=nav_queries
local repeat_large=actor(1,420,96,64)
assert(await_plan(repeat_large)==repeat_large.p and nav_queries==before_nav)
contact.reset()
print("WALL_MELEE_CONTACT_PASS four-face compact waits, inward retreat tolerance, mixed/fractional hulls, bounded cached navigation, obstacle fallback, contact lifecycle")
