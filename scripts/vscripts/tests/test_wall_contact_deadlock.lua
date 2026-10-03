package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 0} end
local clock,paths,nav_queries=0,0,0
local corridor_half=128
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
GridNav={IsTraversable=function(_,p)
    nav_queries=nav_queries+1
    return math.abs(p.y)<corridor_half
end,IsBlocked=function() return false end,FindPathLength=function(_,a,b)
    paths=paths+1
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end}
local entities={}
local function unit(id,x,y,radius)
    local u={p=Vector(x,y,384),radius=radius or 32,orders=0,stops=0}
    function u:entindex() return id end
    function u:GetAbsOrigin() return self.p end
    function u:SetAbsOrigin(p) self.p=p end
    function u:IsNull() return false end
    function u:IsAlive() return not self.dead end
    function u:GetHullRadius() return self.radius end
    function u:IsStunned() return self.stunned end
    function u:IsCommandRestricted() return self.restricted end
    function u:IsRooted() return self.rooted or (self.ai and self.ai.contact_locked) end
    function u:IsDisarmed() return self.disarmed or (self.ai and self.ai.contact_waiting) end
    function u:GetTeamNumber() return 3 end
    function u:GetAttackCapability() return 1 end
    function u:GetForceAttackTarget() return self.force end
    function u:SetForceAttackTarget(target) self.force=target end
    function u:Script_GetAttackRange() return 128+(self.ai and self.ai.contact_range_delta or 0) end
    function u:GetAttacksPerSecond() return 1 end
    function u:Stop() self.stops=self.stops+1 end
    function u:IsIdle() return false end
    entities[id]=u;return u
end
local contact=require('systems/wall_melee_contact')
local wall=unit(1,0,0,128)
local front={}
for i=1,4 do
    local u=unit(i+1,-400,(i-2.5)*64);front[i]=u
    local plan=assert(contact.resolve(wall,u))
    assert(plan.claimed and plan.point.x==-192 and plan.point.y==(i-2.5)*64,
        'all four Hull32 contacts fit the actual 256-wide corridor')
    u.p=plan.point
end
for i=1,4 do for j=i+1,4 do
    local a,b=front[i],front[j]
    assert((a.p.x-b.p.x)^2+(a.p.y-b.p.y)^2>=(a.radius+b.radius)^2,
        'contact hulls must not overlap')
end end
local fifth=unit(10,-400,0)
assert(not contact.resolve(wall,fifth).claimed,'front remains capped at four')
local previous_paths,previous_nav=paths,nav_queries
for pass=1,3 do
    clock=pass*.5
    for _,u in ipairs(front) do assert(contact.resolve(wall,u).claimed) end
    assert(not contact.resolve(wall,fifth).claimed)
end
assert(paths==previous_paths and nav_queries==previous_nav,
    'normal contact ticks do not repeat paths or navigation sampling')

contact.reset();clock=0
local large={}
for i=1,3 do
    local u=unit(20+i,-400,(i-2)*128,64);large[i]=u
    local plan=assert(contact.resolve(wall,u))
    if i<=2 then assert(plan.claimed);u.p=plan.point
    else assert(not plan.claimed,'larger hulls naturally reduce front capacity') end
end
assert(math.abs(large[1].p.y-large[2].p.y)==128)
contact.reset()
local small,big=unit(31,-400,96)
local first=assert(contact.resolve(wall,small));small.p=first.point
big=unit(32,-400,-64,64)
local second=assert(contact.resolve(wall,big));assert(second.claimed);big.p=second.point
assert((small.p.x-big.p.x)^2+(small.p.y-big.p.y)^2>=(small.radius+big.radius)^2,
    'mixed radii share collision reservations on the same face')

-- A displaced admission remains exclusive until release. A nearer neighbour
-- must not create a second phased owner while the first is still moving.
contact.reset();clock=0;front={}
for i=1,4 do
    local u=unit(40+i,-400,(i-2.5)*64);front[i]=u
    local plan=assert(contact.resolve(wall,u));assert(plan.claimed);u.p=plan.point
end
front[4].p=Vector(-192,164,384)
local own=assert(contact.resolve(wall,front[4]))
assert(own.claimed and not contact.arrived(wall,front[4],own.point,false))
local replacement=unit(50,-217,91)
local replaced=assert(contact.resolve(wall,replacement))
assert(not replaced.claimed,
    'a new unit cannot steal an in-flight phased reservation and duplicate its owner')
contact.release(wall:entindex(),front[4]:entindex())
replaced=assert(contact.resolve(wall,replacement))
assert(replaced.claimed and replaced.point.y==96,'released contact can be claimed by a replacement')

-- Dynamic terrain/building changes invalidate a held point on the bounded
-- cache cadence and later make the vacated point available again.
contact.reset();clock=0
local changing=unit(55,-300,-96)
local first_point=assert(contact.resolve(wall,changing)).point;changing.p=first_point
local obstacle=true
GridNav.IsBlocked=function(_,p)
    return obstacle and p.x==first_point.x and p.y==first_point.y
end
local queries_before=nav_queries
clock=1.5
assert(contact.resolve(wall,changing).point==first_point and nav_queries==queries_before,
    'held navigation is not rechecked every observation')
clock=2
local changed=assert(contact.resolve(wall,changing))
assert(changed.claimed and changed.point.y~=first_point.y and changed.point.x==first_point.x,
    'an obstructed contact is released and another same-face point selected')
changing.p=changed.point;obstacle=false;clock=4.5
local newcomer=unit(56,-400,-96)
local restored=assert(contact.resolve(wall,newcomer))
assert(restored.claimed and restored.point.y==first_point.y,
    'short-lived candidate cache observes a removed obstacle')
GridNav.IsBlocked=function() return false end

-- Exercise the actual AI and contact service together, including its state flags.
IsServer=function() return true end
class=function(t) return t end
LinkLuaModifier=function() end
EntIndexToHScript=function(index) return entities[index] end
DOTA_UNIT_CAP_MELEE_ATTACK=1;DOTA_TEAM_BADGUYS=3
DOTA_UNIT_ORDER_ATTACK_TARGET=2;DOTA_UNIT_ORDER_MOVE_TO_POSITION=3
MODIFIER_STATE_ROOTED=4;MODIFIER_STATE_DISARMED=5;MODIFIER_STATE_NO_UNIT_COLLISION=6
package.loaded['core/team_alignment']={are_enemies=function() return true end,enforce=function() end}
ExecuteOrderFromTable=function(order)
    local u=entities[order.UnitIndex];u.orders=u.orders+1;u.last_order=order
end
local ai=require('modifiers/modifier_enemy_wall_ai')
local function controller(u)
    local m=setmetatable({GetParent=function() return u end,StartIntervalThink=function() end}, {__index=ai})
    u.ai=m;m:OnCreated({wall_entindex=1});return m
end
local function finish_phase_frame(m)
    while m.phase_order_frame do clock=clock+1/30;m:OnIntervalThink() end
end
local function think(m)
    m:OnIntervalThink();finish_phase_frame(m)
end
contact.reset();clock=0
local stalled=unit(60,-300,-96);local m=controller(stalled)
m:OnIntervalThink()
assert(m.ai_state=='approach' and stalled.orders==0 and m.phase_order_frame,
    'new admission must wait one native state frame before moving')
finish_phase_frame(m)
assert(stalled.orders==1,'native movement starts after the phase frame')
local original=m.contact_move
for i=1,5 do clock=i*.5;think(m) end
assert(stalled.orders==1,'a collision wait does not issue repeated approach orders')
clock=3;think(m)
assert(m.ai_state=='approach' and m.contact_move.y~=original.y and m.contact_move.x==original.x,
    'after three stalled seconds choose another point on the same front')
assert(stalled.orders==2 and stalled.stops==0,'one new destination order, no repeated Stop')

for _,control in ipairs({'stunned','restricted','rooted'}) do
    contact.reset();clock=0
    local controlled=unit(70,-300,-96);local cm=controller(controlled)
    think(cm);local point=cm.contact_move
    controlled[control]=true
    for i=1,12 do clock=i*.5;think(cm) end
    assert(cm.ai_state=='approach' and cm.contact_move==point and controlled.orders==1,
        'control status protects a claim and does not change its goal')
    controlled[control]=false;clock=6.5;think(cm)
    assert(cm.contact_move==point,'control release receives normal progress grace')
end

contact.reset();clock=0;front={}
local controllers={}
for i=1,4 do
    local u=unit(80+i,-400,(i-2.5)*64);front[i]=u
    controllers[i]=controller(u);think(controllers[i])
    u.p=controllers[i].contact_move;think(controllers[i])
    assert(controllers[i].ai_state=='attack' and u.ai:CheckState()[MODIFIER_STATE_ROOTED])
end
local overflow=unit(90,-400,0);local waiting=controller(overflow);think(waiting)
assert(waiting.ai_state=='waiting' and waiting:CheckState()[MODIFIER_STATE_DISARMED])
local orders={};for i,u in ipairs(front) do orders[i]=u.orders end
local waiting_orders=overflow.orders
for pass=1,20 do
    clock=pass*.5
    for i,am in ipairs(controllers) do
        am:OnAttackStart({attacker=front[i],target=wall});think(am)
        assert(front[i].orders==orders[i] and front[i].stops==1,
            'arrived attackers keep native attack windup/cooldown without new orders')
    end
    think(waiting);assert(overflow.orders==waiting_orders)
end
front[3].dead=true;clock=10.5;think(waiting)
assert(waiting.ai_state=='approach' and overflow.orders==waiting_orders+1,
    'one death frees its front point and wakes a waiting monster once')
print('WALL_CONTACT_DEADLOCK_PASS narrow four contacts, mixed/large hulls, exclusive admission, bounded stall recovery, control protection, stable attacks')
