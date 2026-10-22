-- A terrain-filtered three-contact face must replace a death even when the
-- nearby rear actors already own unfulfilled routes to another wall face.
-- This models the real north tangent -64 failure, not native crowd physics.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,paths,path_rule=0,0,nil
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
GridNav={IsTraversable=function() return true end,
    -- A bounded 276-wide opening really has only three full-body contacts.
    -- An unbounded upper bank now permits a legitimate shifted four-slot fit.
    IsBlocked=function(_,p) return p.x< -100 and (p.y< -100 or p.y>176) end,
    FindPathLength=function(_,a,b)
        paths=paths+1
        if path_rule then return path_rule(a,b) end
        -- Both approach ends are terrain-reachable; other-face detours are
        -- unavailable in this allocator fixture. Native tests cover routes.
        -- Rear goals on this same approach also have a real native route;
        -- perpendicular-face detours remain unavailable in this fixture.
        if b.x~=-184 and b.x~=184 and not (a.x<0 and b.x< -184) then return -1 end
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    end}
package.loaded['systems/wall_navigation_service']={}
local contact=require('systems/wall_melee_contact')
local function actor(id,x,y)
    local u={p=Vector(x,y,384)}
    function u:entindex() return id end
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return not self.dead end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return 32 end
    function u:GetPaddedCollisionRadius() return 42 end
    function u:IsStunned() return self.stunned end
    function u:IsCommandRestricted() return self.restricted end
    function u:IsRooted() return self.rooted end
    function u:IsCurrentlyHorizontalMotionControlled() return self.horizontal end
    function u:IsCurrentlyVerticalMotionControlled() return self.vertical end
    function u:SetAbsOrigin() error('replacement must use native movement') end
    function u:SetHullRadius() error('replacement must retain Hull32') end
    return u
end
local wall,front,near,far
local function setup()
    contact.reset();clock=0;paths=0;path_rule=nil
    wall=actor(1,0,0);front={}
    for i,y in ipairs({-44,44,132}) do
        local u=actor(10+i,-184,y);front[i]=u
        local p=assert(contact.resolve(wall,u))
        assert(p.claimed and p.point.x==-184 and p.point.y==y)
        assert(contact.settle(wall,u,p.point))
    end
    near=actor(20,-276,-44);far=actor(21,-360,-44)
    for _,u in ipairs({near,far}) do
        clock=clock+.5 -- A separate observation bucket for real route budgets.
        local p=assert(contact.resolve(wall,u))
        assert(p.claimed and p.point.x==184,'a full three-contact face must initially preserve a real other-face route')
    end
end
local function tick(t)
    clock=t
    for _,u in ipairs(front) do if u:IsAlive() then
        local p=assert(contact.resolve(wall,u))
        assert(p.claimed and p.point.x==-184,'settled original attackers must remain stable')
    end end
end
local function kill_front()
    front[1].dead=true
    contact.release(wall:entindex(),front[1]:entindex())
    tick(clock+.5)
end

setup()
-- No real vacancy: neither in-flight owner may cancel its route or consume a
-- fresh path merely because its physical position is still on the near face.
local before=paths
for pass=1,4 do
    tick(clock+.5)
    for _,u in ipairs({near,far}) do
        local p=assert(contact.resolve(wall,u))
        assert(p.claimed and p.point.x==184)
    end
end
assert(paths==before,'no vacancy must mean no replacement path work')

setup();kill_front()
before=paths
local pf=assert(contact.resolve(wall,far))
assert(pf.claimed and pf.point.x==184,'an earlier far callback must keep yielding to the closer body')
assert(paths==before,'the non-nominated owner must not search replacement paths')
local pn=assert(contact.resolve(wall,near))
assert(pn.claimed and pn.point.x==-184 and pn.point.y==-44,
    'a real three-contact vacancy must preempt the nearest unfulfilled remote claim')
assert(paths==before+1,'only the selected near vacancy needs a native path')
assert(near.p.x==-276,'claim transfer must not move the native body')
near.p=Vector(-216,-44,384)
assert(contact.settle(wall,near,pn.point),'ordinary native arrival can settle the replacement')
-- Its former remote key is released exactly once and remains claimable.
local newcomer=actor(30,400,-44)
local other=assert(contact.resolve(wall,newcomer,2))
assert(other.claimed and other.point.x==184,'old remote reservation must not leak')

-- A failed local route retains the original reservation and yields nomination
-- to another physical candidate. It must never free then lose a viable route.
setup();kill_front()
path_rule=function(a,b)
    if b.x==-184 and a==near.p then return -1 end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
pn=assert(contact.resolve(wall,near))
assert(pn.claimed and pn.point.x==184,'failed local transfer must retain its old native route')
pf=assert(contact.resolve(wall,far))
assert(pf.claimed and pf.point.x==-184,'failed nominee must let another valid rear body fill the hole')

-- A geometrically close point can still require a real long detour. Do not
-- replace a normal route unless the new native path is demonstrably shorter
-- than even the straight-line lower bound of that existing destination.
setup();kill_front()
path_rule=function(a,b)
    if b.x==-184 and a==near.p then return 800 end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
pn=assert(contact.resolve(wall,near))
assert(pn.claimed and pn.point.x==184,'a misleading near point must not replace a genuinely shorter existing route')
pf=assert(contact.resolve(wall,far));assert(pf.claimed and pf.point.x==-184)

-- An existing settled opposite-face attacker cannot be stolen. External
-- control, dead handles and another wall also cannot nominate a transfer.
for _,invalid in ipairs({'settled','stunned','restricted','rooted','horizontal','vertical','dead','removed','retargeted'}) do
    setup()
    if invalid=='settled' then
        local p=assert(contact.resolve(wall,near))
        near.p=p.point;assert(contact.settle(wall,near,p.point))
    elseif invalid=='retargeted' then
        near.survival_wall_contact_owner={wall_entindex=99}
    else near[invalid]=true end
    kill_front()
    pf=assert(contact.resolve(wall,far))
    assert(pf.claimed and pf.point.x==-184,'invalid '..invalid..' owner must not hold the near vacancy')
end

-- Moving genuinely around the corner changes physical face; that owner must
-- retain its route while another same-side rear can handle the death vacancy.
setup();near.p=Vector(184,44,384);kill_front()
pf=assert(contact.resolve(wall,far))
assert(pf.claimed and pf.point.x==-184)
pn=assert(contact.resolve(wall,near))
assert(pn.claimed and pn.point.x==184,'a body already on its destination face must not reverse around the wall')

-- Two actual holes transfer two different remote owners, with no duplicate
-- slot and no release of the one surviving settled front actor.
setup()
for i=1,2 do front[i].dead=true;contact.release(wall:entindex(),front[i]:entindex()) end
tick(clock+.5)
pf=assert(contact.resolve(wall,far));assert(pf.point.x==184)
pn=assert(contact.resolve(wall,near));assert(pn.point.x==-184)
pf=assert(contact.resolve(wall,far));assert(pf.point.x==-184 and pf.point.y~=pn.point.y)

-- Transfers spend the existing shared sixteen-path bucket. An exhausted
-- bucket retains both the nomination and old reservation until the next tick.
setup();kill_front()
path_rule=function() return -1 end
before=paths
for id=300,309 do contact.resolve(wall,actor(id,44,-350),3) end
assert(paths-before==16,'a burst must exhaust only the existing shared budget')
local exhausted=paths
pn=assert(contact.resolve(wall,near))
assert(pn.claimed and pn.point.x==184 and paths==exhausted,'zero remaining budget must defer the transfer without losing its old claim')
path_rule=nil;tick(clock+.5)
pn=assert(contact.resolve(wall,near));assert(pn.claimed and pn.point.x==-184)
assert(paths==exhausted+1)

-- All blocked local routes retain their remote leases. The shared existing
-- failure sweep wakes nomination after the two-second backoff expires.
setup();kill_front()
path_rule=function(a,b)
    if b.x==-184 then return 1537 end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
for _,u in ipairs({near,far}) do
    local p=assert(contact.resolve(wall,u));assert(p.claimed and p.point.x==184)
end
before=paths
pn=assert(contact.resolve(wall,near));assert(pn.point.x==184 and paths==before)
path_rule=nil;tick(clock+2.1)
pn=assert(contact.resolve(wall,near));assert(pn.claimed and pn.point.x==-184)

-- Releasing a nominated remote owner must drop it from the vacancy choice.
for _,cleanup in ipairs({'release','clear','reset'}) do
    setup();kill_front()
    pf=assert(contact.resolve(wall,far));assert(pf.point.x==184)
    if cleanup=='release' then
        contact.release(wall:entindex(),near:entindex())
        pf=assert(contact.resolve(wall,far));assert(pf.claimed and pf.point.x==-184)
    else
        if cleanup=='clear' then contact.clear(wall:entindex()) else contact.reset() end
        local fresh=actor(99,-300,-44)
        local p=assert(contact.resolve(wall,fresh));assert(p.claimed and p.point.x==-184)
    end
end

-- Native MOVE may stop32 short of its nominal contact, and that actual body
-- stays fixed. A rear goal derived from the nominal point would be only60
-- from the real front (inside Hull32+32); retain the real rear envelope.
setup()
for _,u in ipairs(front) do u.p=Vector(u.p.x-32,u.p.y,384) end
tick(clock+.5)
local waiting=actor(500,-500,-44)
local wp=assert(contact.resolve(wall,waiting,1))
assert(not wp.claimed and wp.point.x<=-308,
    'native stopping offsets must be included in the settled front rear edge')
for _,u in ipairs(front) do
    assert((wp.point.x-u.p.x)^2+(wp.point.y-u.p.y)^2>=84*84,
        'rear waiting target must not overlap a real front body or its native padded clearance')
end
local compressed=actor(501,-280,-44)
local retreat=assert(contact.resolve(wall,compressed,1))
assert(not retreat.claimed and retreat.wait_retreat and retreat.point.x<=-340,
    'a waiter inside the actual rear envelope must retreat instead of aiming inside the front body')
contact.reset()
print('WALL_PARTIAL_FACE_REPLACEMENT_PASS terrain capacity3, remote-claim vacancy transfer, nearest priority, stable routes/attackers, atomic old-key release, native-shorter-path checks, simultaneous holes, shared budget, failure backoff/recovery, lifecycle protection, actual native-stop rear envelope, no phasing/resizing/teleports')
