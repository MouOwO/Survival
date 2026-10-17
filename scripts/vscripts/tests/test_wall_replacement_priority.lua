-- Same-column native pilot regression: the nearest real rear actor must get
-- a death vacancy before an earlier callback from another blocked column.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,paths,path_rule=0,0,nil
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end,
    FindPathLength=function(_,a,b)
        paths=paths+1
        if path_rule then return path_rule(a,b) end
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    end}
package.loaded['systems/wall_navigation_service']={}
local contact=require('systems/wall_melee_contact')
local function unit(id,x,y)
    local u={p=Vector(x,y,384),reads=0}
    function u:entindex() return id end
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return not self.dead end
    function u:GetAbsOrigin() self.reads=self.reads+1;return self.p end
    function u:GetHullRadius() return 32 end
    function u:GetPaddedCollisionRadius() return 42 end
    function u:IsStunned() return self.stunned end
    function u:IsCommandRestricted() return self.restricted end
    function u:IsRooted() return self.rooted end
    function u:IsCurrentlyHorizontalMotionControlled() return self.horizontal end
    function u:IsCurrentlyVerticalMotionControlled() return self.vertical end
    function u:SetAbsOrigin() error('priority must not teleport') end
    function u:SetHullRadius() error('priority must not resize') end
    return u
end
local wall=unit(1,0,0)
local front={}
for index,y in ipairs({-132,-44,44,132}) do
    local u=unit(10+index,-184,y);front[index]=u
    local plan=assert(contact.resolve(wall,u,1))
    assert(plan.claimed);assert(contact.settle(wall,u,plan.point))
end
local far=unit(20,-276,44)
local near=unit(21,-276,132)
assert(not contact.resolve(wall,far,1).claimed)
assert(not contact.resolve(wall,near,1).claimed)
local others={}
for id=30,79 do
    local u=unit(id,-400,(id-55)*.1);others[#others+1]=u
    assert(not contact.resolve(wall,u,1).claimed)
end
front[4].dead=true;clock=.5
local before=paths
assert(not contact.resolve(wall,far,1).claimed,'earlier callback must yield the vacant same-column contact to the nearest observed actor')
assert(paths==before,'a nonpriority actor must not repeat native path queries')
local reads={};for _,u in ipairs(others) do reads[u:entindex()]=u.reads end
for pass=1,40 do assert(not contact.resolve(wall,far,1).claimed) end
for _,u in ipairs(others) do assert(u.reads==reads[u:entindex()],'a retained nominee must not rescan waiting actors') end
assert(paths==before)
local replacement=assert(contact.resolve(wall,near,1))
assert(replacement.claimed and replacement.point.y==132,'the real same-column nearest actor must own the death vacancy')
assert(paths==before+1,'only the selected replacement needs its one valid native route')
near.p=replacement.point;assert(contact.settle(wall,near,replacement.point))
contact.reset()

local function setup()
    contact.reset();clock=0;paths=0;path_rule=nil
    wall=unit(1,0,0);front={}
    for index,y in ipairs({-132,-44,44,132}) do
        local u=unit(100+index,-184,y);front[index]=u
        local plan=assert(contact.resolve(wall,u,1));assert(plan.claimed)
        assert(contact.settle(wall,u,plan.point))
    end
end
local function observe(u) assert(not contact.resolve(wall,u,1).claimed);return u end
local function tick(stamp)
    clock=stamp
    for _,u in ipairs(front) do if u:IsAlive() then assert(contact.resolve(wall,u,1).claimed) end end
end
-- Two same-frame deaths are independent vacancies. Choose the closest real
-- rear for one, consume that lease, then choose the other without stealing it.
setup()
local a=observe(unit(20,-276,-132));local b=observe(unit(21,-276,132))
local late=observe(unit(22,-400,0))
front[1].dead=true;front[4].dead=true;clock=.5
assert(not contact.resolve(wall,late,1).claimed)
assert(not contact.resolve(wall,b,1).claimed,'deterministic nearest tie must preserve the first nominee until its own callback')
local pa=assert(contact.resolve(wall,a,1));assert(pa.claimed and pa.point.y==-132)
a.p=pa.point;assert(contact.settle(wall,a,pa.point))
local pb=assert(contact.resolve(wall,b,1));assert(pb.claimed and pb.point.y==132)
assert(pa.point~=pb.point,'simultaneous deaths cannot assign one slot twice')

-- External control beginning AFTER nomination must not hold the queue hostage.
for _,control in ipairs({'stunned','restricted','rooted','horizontal','vertical'}) do
    setup()
    near=observe(unit(20,-276,132));far=observe(unit(21,-360,132))
    front[4].dead=true;clock=.5
    assert(not contact.resolve(wall,far,1).claimed)
    near[control]=true
    local pf=assert(contact.resolve(wall,far,1))
    assert(pf.claimed,control..' nominee must yield to another available actor')
    far.dead=true;near[control]=false;clock=1
    local pn=assert(contact.resolve(wall,near,1))
    assert(pn.claimed,'a recovered actor must participate in a later real vacancy')
end

for _,invalid in ipairs({'dead','removed','outside','detached','reused'}) do
    setup()
    near=observe(unit(20,-276,132));far=observe(unit(21,-360,132))
    near.survival_wall_contact_owner={wall_entindex=1}
    front[4].dead=true;clock=.5
    assert(not contact.resolve(wall,far,1).claimed)
    if invalid=='outside' then near.p=Vector(-600,132,384)
    elseif invalid=='detached' then near.survival_wall_contact_owner.wall_entindex=99
    elseif invalid=='reused' then
        near.removed=true
        local replacement=unit(20,-480,0)
        assert(not contact.resolve(wall,replacement,1).claimed,'a reused index must replace the old observation handle')
    else near[invalid]=true end
    assert(contact.resolve(wall,far,1).claimed,'invalid '..invalid..' nominee must not starve another waiter')
end

-- A failed native path excludes that nominee during the existing2s backoff;
-- another actor can claim immediately. Later recovery reuses the real path.
setup()
near=observe(unit(20,-276,132));far=observe(unit(21,-360,132))
front[4].dead=true;clock=.5
path_rule=function(a,b)
    if a==near.p then return -1 end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
assert(not contact.resolve(wall,far,1).claimed)
assert(not contact.resolve(wall,near,1).claimed,'unreachable nominee must fail without owning the vacancy forever')
assert(contact.resolve(wall,far,1).claimed,'a native path failure must let another nominee through immediately')
-- With the vacancy unchanged, repeated observations preserve the2s cache.
-- A newly consumed/released contact may invalidate that older failure epoch.
setup()
near=observe(unit(20,-276,132));far=observe(unit(21,-360,132))
front[4].dead=true;clock=.5
path_rule=function(a,b)
    if a==near.p then return -1 end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
assert(not contact.resolve(wall,far,1).claimed)
assert(not contact.resolve(wall,near,1).claimed)
path_rule=nil
local blocked_paths=paths
for _,stamp in ipairs({1,1.5,2}) do
    tick(stamp)
    assert(not contact.resolve(wall,near,1).claimed)
end
assert(paths==blocked_paths,'same failed nominee must not repeat native paths during its backoff')
tick(2.6)
assert(contact.resolve(wall,near,1).claimed,'the recovered route must retry after2s without an external wakeup')

-- A stationary, truly blocked owner releases its lease and keeps its retry
-- backoff. It cannot immediately re-nominate itself ahead of a movable rear.
setup()
near=observe(unit(20,-276,132));far=observe(unit(21,-360,132))
front[4].dead=true;clock=.5
assert(not contact.resolve(wall,far,1).claimed)
assert(contact.resolve(wall,near,1).claimed)
for _,stamp in ipairs({1,1.5,2,2.5,3}) do
    tick(stamp);assert(contact.resolve(wall,near,1).claimed)
    assert(not contact.resolve(wall,far,1).claimed)
end
tick(3.5)
assert(not contact.resolve(wall,near,1).claimed,'stationary owner must release its stale lease')
assert(contact.resolve(wall,far,1).claimed,'stalled previous owner must not immediately reclaim through priority')

-- A moved/removed wall or reset drops observations and cached entity handles.
for _,clear in ipairs({'clear','reset','new_wall_handle'}) do
    setup()
    near=observe(unit(20,-276,132));far=observe(unit(21,-360,132))
    front[4].dead=true;clock=.5
    assert(not contact.resolve(wall,far,1).claimed)
    if clear=='clear' then contact.clear(wall:entindex())
    elseif clear=='reset' then contact.reset()
    else wall=unit(1,0,0) end
    local old_reads=near.reads
    local fresh=unit(200,-400,44)
    assert(contact.resolve(wall,fresh,1).claimed,'fresh wall state must not retain an old nominee')
    assert(near.reads==old_reads,'fresh wall state must release previous entity handles')
end
contact.reset()
print('WALL_REPLACEMENT_PRIORITY_PASS nearest physical waiter, simultaneous deaths, stable cached work, five control types, entity lifecycle/retarget/reuse, path failure/backoff/recovery, stalled owner, wall clear/reset, no bypass')
