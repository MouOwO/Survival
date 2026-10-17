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
    local u={p=Vector(x,y,384),radius=radius or 32,hull_writes=0}
    function u:entindex() return id end
    function u:GetAbsOrigin() return self.p end
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return not self.dead end
    function u:GetHullRadius() return self.radius end
    function u:SetHullRadius(radius) self.radius=radius;self.hull_writes=self.hull_writes+1 end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    return u
end
local contact=require("systems/wall_melee_contact")
local wall=unit(1,0,0,128)
local front={}
local chosen={}
for i=1,4 do
    front[i]=unit(i+1,-400,(i-2.5)*88)
    local p=assert(contact.resolve(wall,front[i]))
    assert(p.claimed and p.point.x==-184 and p.point.y==(i-2.5)*88,
        "each monster gets its nearest lane on the reachable face")
    assert(front[i]:GetHullRadius()==32 and front[i].hull_writes==0,
        "admitted contacts must retain the fixed native collision body")
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
local waiting=contact.resolve(wall,fifth,1) -- A sealed gate retains its local queue.
assert(not waiting.claimed and waiting.point.x==-276 and fifth:GetHullRadius()==32,
    "Hull32 overflow keeps its real hull and waits beyond the solid front")
assert(paths==before,"full front does not run path searches for every waiting monster")
local other_side=unit(7,350,0)
local independent=assert(contact.resolve(wall,other_side))
assert(independent.claimed and independent.point.x==184,
    "a full west face cannot consume another face's four contacts")
front[3].dead=true
local refill=contact.resolve(wall,fifth,1)
assert(refill.claimed and refill.point.y==44,"dead front unit is replaced in its vacated lane")
assert(front[3]:GetHullRadius()==32,"death cleanup restores the original physical hull")
-- No first-arrival orientation: a new wall is approached from any valid side.
contact.reset()
for _,u in ipairs(front) do assert(u:GetHullRadius()==32,"reset restores every admitted hull") end
assert(fifth:GetHullRadius()==32 and other_side:GetHullRadius()==32,"reset restores replacement and independent-face owners")
local far=unit(10,-900,0)
local staging=contact.resolve(wall,far)
assert(staging and not staging.claimed and staging.point.x==-320 and far:GetHullRadius()==32,
    "spawn-distance units stage outside the near face without reserving contacts or changing hull")
local north=unit(11,40,400)
local p=contact.resolve(wall,north)
assert(p.claimed and p.point.y==184 and p.point.x==44)
contact.release(1,11)
assert(north:GetHullRadius()==32,"release restores a contact's real collision hull")
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
assert(west:GetHullRadius()==32 and other:GetHullRadius()==32,"clear restores stale and active contact hulls")
-- A direct external native adjustment and the formal hull-scale policy each
-- survive later stable contact observations and cleanup.
local adjusted=unit(14,400,24)
adjusted.survival_monster_hull_radius=32
assert(contact.resolve(wall,adjusted).claimed and adjusted:GetHullRadius()==32)
adjusted:SetHullRadius(64)
assert(contact.resolve(wall,adjusted).claimed and adjusted:GetHullRadius()==64)
assert(contact.resolve(wall,adjusted).claimed and adjusted:GetHullRadius()==64)
contact.release(1,14)
assert(adjusted:GetHullRadius()==64,"stable observations must not discard a direct external hull adjustment")
assert(contact.resolve(wall,adjusted).claimed)
adjusted.survival_monster_hull_radius=96
adjusted:SetHullRadius(96)
assert(contact.resolve(wall,adjusted).claimed and adjusted:GetHullRadius()==96)
contact.release(1,14)
assert(adjusted:GetHullRadius()==96,"release must preserve a new configured hull-scale policy")

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
    local u=unit(next_id,p.x,p.y,radius);u.gate_face=face;return u
end
local function corridor(face,blocked)
    GridNav.IsTraversable=function(_,p)
        nav_queries=nav_queries+1;nav_samples[#nav_samples+1]=p
        return math.abs(lateral_of(face,p))<192
    end
    GridNav.IsBlocked=function(_,p)
        nav_queries=nav_queries+1
        return (math.abs(p.x)<128 and math.abs(p.y)<128) or (blocked and blocked(p)) or false
    end
    GridNav.FindPathLength=function(_,a,b)
        paths=paths+1
        if normal_of(face,a)*normal_of(face,b)<0 then return -1 end
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    end
end
local function fill_front(face)
    contact.reset();stamp=0;corridor(face)
    local result={}
    for lane=1,4 do
        local u=actor(face,400,(lane-2.5)*88,32)
        local plan=assert(contact.resolve(wall,u))
        assert(plan.claimed and normal_of(face,plan.point)==184 and u:GetHullRadius()==32
            and u.hull_writes==0)
        u.p=plan.point;result[#result+1]=u
    end
    return result
end
local function await_plan(u)
    local plan=assert(contact.resolve(wall,u,u.gate_face))
    assert(not plan.claimed,'waiting regression unexpectedly claimed a full contact row')
    return plan.point
end

-- Every wall face uses the same compact spacing. Native arrivals from behind
-- can stop 32 early; retreating units need their own extra allowance so they
-- do not stop inside the solid attacker's padded collision body.
for face=1,4 do
    fill_front(face)
    local rear=actor(face,400,40,32)
    local rear_goal=await_plan(rear)
    assert(normal_of(face,rear_goal)==276 and lateral_of(face,rear_goal)==44,
        'rear arrivals use a92-unit padded contact-to-wait-goal gap on every face')
    local close=actor(face,224,40,32)
    local close_goal=await_plan(close)
    assert(normal_of(face,close_goal)==308 and lateral_of(face,close_goal)==44,
        'an existing inner waiter receives its own124-unit retreat goal')
    assert(normal_of(face,close_goal)-32-184>=42+42+8,
        'native retreat acceptance must leave both bodies separated')
    assert(normal_of(face,rear_goal)+32-184==124,
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

-- The384 corridor cannot hold four Hull64 bodies at88 pitch. Full-body terrain
-- checks remove its outer lanes and physical separation leaves one large
-- owner; a smaller owner can use the genuinely separated outer contact.
contact.reset();stamp=0;corridor(1)
local large_front=actor(1,400,-44,64)
local large_plan=assert(contact.resolve(wall,large_front,1))
assert(large_plan.claimed and large_plan.point.x==-216 and large_plan.point.y==-44
    and large_front:GetHullRadius()==64 and large_front.hull_writes==0)
large_front.p=large_plan.point
local denied_large=actor(1,400,44,64)
assert(not contact.resolve(wall,denied_large,1).claimed and denied_large.radius==64,
    'a second large body must not shrink through a physically blocked lane')
local small_front=actor(1,400,132,32)
local small_plan=assert(contact.resolve(wall,small_front,1))
assert(small_plan.claimed and small_plan.point.x==-184 and small_plan.point.y==132
    and small_front.radius==32 and small_front.hull_writes==0,
    'a separated small body may still take the legal remaining contact')
small_front.p=small_plan.point
local small_behind_large=actor(1,400,40,32)
local large_row_goal=await_plan(small_behind_large)
assert(large_row_goal.x==-340 and large_row_goal.y==-44 and small_behind_large:GetHullRadius()==32,
    'a real large-body envelope must move the unchanged small waiter farther back')
local candidate_paths,candidate_nav=paths,nav_queries
for pass=1,3 do
    stamp=pass*.5
    assert(await_plan(small_behind_large)==large_row_goal)
end
assert(paths==candidate_paths and nav_queries==candidate_nav,
    'large-body front must reuse bounded wait geometry')
contact.reset()
assert(large_front.radius==64 and large_front.hull_writes==0 and small_front.radius==32
    and denied_large.radius==64,'large contact cleanup must preserve every real native body')

-- Changing waiter size must sample that body's real hull. Large waiters also
-- move inward laterally instead of inheriting an outer Hull32 attack lane.
fill_front(1)
local small_waiter=actor(1,400,96,16)
local small_goal=await_plan(small_waiter)
assert(small_goal.x==-260 and small_goal.y==132)
local before_nav=nav_queries
nav_samples={}
local large_waiter=actor(1,400,96,64)
local large_goal=await_plan(large_waiter)
assert(large_goal.x==-308 and large_goal.y==112,
    'large waiter requires its own normal spacing and a hull-safe lateral goal')
assert(nav_queries>before_nav,'a small cached hull must not skip navigation checks for a larger waiter')
local sampled_outer_hull=false
for _,sample in ipairs(nav_samples) do
    if sample.x==-308 and sample.y==175 then sampled_outer_hull=true end
end
assert(sampled_outer_hull,'large waiter navigation must sample the actual outer hull')
before_nav=nav_queries
assert(await_plan(actor(1,420,96,64))==large_goal and nav_queries==before_nav,
    'identical large waiters reuse the validated larger-body goal')
local too_wide=actor(1,450,0,193)
assert(await_plan(too_wide)==too_wide.p,'a body wider than the passage must stay put rather than get an invalid wait goal')

-- Cache keys must not confuse an inner Hull32 waiter with an outer Hull32.5
-- waiter: hull multipliers are not rounded by monster_hull_scale.apply.
fill_front(1)
local inner_integer=actor(1,224,40,32)
assert(await_plan(inner_integer).x==-308)
before_nav=nav_queries
local fractional=actor(1,400,40,32.5)
local fractional_goal=await_plan(fractional)
assert(fractional_goal.x==-276.5 and nav_queries>before_nav,
    'fractional hull size must not collide with the integer inner-wait cache key')

-- A nearby small contact is not the entire front. Waiting spacing must cover
-- the largest actual navigation envelope among all four admitted contacts.
contact.reset();stamp=0;corridor(1)
local mixed={}
for _,spec in ipairs({{32,-132},{48,-44},{16,44},{1,132}}) do
    local u=actor(1,400,spec[2],spec[1])
    local plan=assert(contact.resolve(wall,u))
    assert(plan.claimed,'mixed front fixture must have four distinct valid contacts')
    u.p=plan.point;mixed[#mixed+1]=u
end
local mixed_waiter=actor(1,400,-80,64)
local mixed_goal=await_plan(mixed_waiter)
assert(mixed_goal.x==-340 and mixed_goal.y==-44,
    'waiter must stand behind the adjacent large contact, even when the nearest contact is small')
for _,u in ipairs(mixed) do
    local dx,dy=mixed_goal.x-u.p.x,mixed_goal.y-u.p.y
    assert(dx*dx+dy*dy>=(mixed_waiter:GetPaddedCollisionRadius()+u:GetPaddedCollisionRadius()+8)^2,
        'mixed-body waiting goal overlaps a different front lane')
end
-- A changed envelope invalidates existing size caches without a timer or a
-- new path query. The existing fixed waiting AI goal is tested separately.
mixed[2].radius=80
before_nav=nav_queries
assert(await_plan(mixed_waiter).x==-372 and nav_queries>before_nav,
    'changed front hull extent must invalidate the cached wait geometry')

-- A blocked destination falls back to each caller's own position, including
-- a cached negative result. Other sizes/retreat modes still get their own test.
fill_front(1)
local wait_obstacle=true
corridor(1,function(p) return wait_obstacle and p.x==-276 and p.y==44 end)
local blocked_waiter=actor(1,400,40,32)
assert(await_plan(blocked_waiter)==blocked_waiter.p,'blocked compact wait goal must fall back to the caller position')
before_nav=nav_queries
local second_blocked=actor(1,440,40,32)
assert(await_plan(second_blocked)==second_blocked.p and nav_queries==before_nav,
    'negative cache must not share the first waiter position or resample every caller')
local inner_unblocked=actor(1,224,40,32)
assert(await_plan(inner_unblocked).x==-308,'blocked normal goal must not poison the separate retreat goal')
wait_obstacle=false;stamp=2
before_nav=nav_queries
local before_paths=paths
assert(await_plan(blocked_waiter).x==-276 and nav_queries>before_nav,
    'a removed waiting obstruction must recover on the bounded navigation-cache cadence')
assert(paths==before_paths,'waiting geometry refresh must not trigger pathfinding')

fill_front(1)
corridor(1,function(p) return p.x==-308 and p.y==175 end)
local small_unblocked=actor(1,400,96,16)
assert(await_plan(small_unblocked).x==-260)
local peripheral_blocked=actor(1,400,96,64)
assert(await_plan(peripheral_blocked)==peripheral_blocked.p,
    'a clear center cannot authorize a waiting goal whose larger hull touches an obstacle')
before_nav=nav_queries
local repeat_large=actor(1,420,96,64)
assert(await_plan(repeat_large)==repeat_large.p and nav_queries==before_nav)
contact.reset()
print("WALL_MELEE_CONTACT_PASS four-face compact waits, inward retreat tolerance, mixed/fractional hulls, bounded cached navigation, obstacle fallback, contact lifecycle")
