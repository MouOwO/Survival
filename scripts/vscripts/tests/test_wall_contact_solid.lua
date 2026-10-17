-- Real contact occupancy and production state contract. The2026-10-16 solid
-- policy replaces the old transient phasing and temporary Hull20 assertions.
-- Native Tools movement acceptance is a separate test.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock=0
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
GridNav={IsTraversable=function() return true end,IsBlocked=function(_,p)
    return math.abs(p.x)<128 and math.abs(p.y)<128
end,FindPathLength=function(_,a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end}
DOTA_UNIT_TARGET_TEAM_BOTH=3;DOTA_UNIT_TARGET_BASIC=1;DOTA_UNIT_TARGET_HERO=2
DOTA_UNIT_TARGET_FLAG_INVULNERABLE=1;DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=2
FIND_ANY_ORDER=0
local queries,neighbours,last_center=0,{},nil
FindUnitsInRadius=function(team,point,cache,radius)
    assert(team==3 and radius==512,'body admission must remain local')
    queries=queries+1;last_center=point
    return neighbours
end
local function unit(id,x,y,radius)
    local u={p=Vector(x,y,384),radius=radius or 32,writes=0,hull_writes=0}
    function u:entindex() return id end
    function u:IsNull() return false end
    function u:IsAlive() return not self.dead end
    function u:GetAbsOrigin() return self.p end
    function u:SetAbsOrigin() self.writes=self.writes+1;error('no contact teleport') end
    function u:GetHullRadius() return self.radius end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:SetHullRadius() self.hull_writes=self.hull_writes+1;error('no temporary hull') end
    function u:GetTeamNumber() return 3 end
    return u
end
package.loaded['systems/wall_navigation_service']={}
local contact=require('systems/wall_melee_contact')
local wall=unit(1,0,0,128)
local entrant=unit(2,-240,-44)
local plan=assert(contact.resolve(wall,entrant,1))
assert(plan.claimed and entrant.radius==32 and entrant:GetPaddedCollisionRadius()==42,
    'a claimed contact must keep its full physical and padded radius')
local point=plan.point
entrant.p=Vector(point.x-32,point.y,point.z)
local blocker=unit(3,point.x-16,point.y)
neighbours={entrant,blocker}
local before=queries
assert(not contact.settle(wall,entrant,point),'a live overlap at the real position must defer entry')
assert(queries==before+1 and last_center==wall:GetAbsOrigin() and entrant.writes==0,
    'body query must use a shared wall-local snapshot and never align the actor')
blocker.p=Vector(point.x-128,point.y,point.z)
assert(contact.settle(wall,entrant,point),'native32 acceptance may settle once the real occupant leaves')
assert(entrant.p.x==point.x-32 and entrant.writes==0 and entrant.hull_writes==0)

-- Native padding is avoidance space. Physical circles may fit when padding
-- halos gently compress, but real hard overlaps must never lock into attack.
blocker.p=Vector(entrant.p.x,entrant.p.y+70,point.z)
assert(contact.settle(wall,entrant,point),'physical bodies separated by70 remain legal despite padded halos')
blocker.p=Vector(entrant.p.x,entrant.p.y+60,point.z)
assert(not contact.settle(wall,entrant,point),'actual Hull32 circles with60 spacing overlap')
for _,mode in ipairs({1,2,3,4,5,6}) do
    blocker.contact_mode=mode;blocker.no_unit_collision=true
    assert(not contact.settle(wall,entrant,point),'neither a reservation mode nor a legacy flag exempts a live body')
end
-- Zero-hull native builders and cosmetic carriers are intentionally absent
-- from physical avoidance, even while their visible centers overlap.
blocker.radius=0;blocker.p=Vector(entrant.p.x,entrant.p.y,point.z)
assert(contact.settle(wall,entrant,point),'a coincident native Hull0 builder/carrier must not block admission')
blocker.radius=32
assert(not contact.settle(wall,entrant,point),'restoring a real Hull32 body at that same point must reject admission')
blocker.dead=true
assert(contact.settle(wall,entrant,point),'a dead corpse must release its physical blockage')
entrant.p=Vector(point.x-64,point.y,point.z)
before=queries
assert(not contact.settle(wall,entrant,point) and queries==before,
    'second-row distance64 must reject without a neighbour query')

-- An exact but never physically settled lease must expire. Other settled
-- owners remain stable rather than being rephased or resized to make room.
contact.reset();clock=0;neighbours={}
local fronts={}
for lane,lateral in ipairs({-132,-44,44}) do
    local u=unit(10+lane,-184,lateral)
    local p=assert(contact.resolve(wall,u,1))
    assert(p.claimed and p.point.y==lateral)
    neighbours[#neighbours+1]=u
    assert(contact.settle(wall,u,p.point))
    fronts[#fronts+1]=u
end
local held=unit(20,-184,132)
local held_plan=assert(contact.resolve(wall,held,1))
assert(held_plan.claimed and held_plan.point.y==132)
local hard_blocker=unit(21,-184,170)
neighbours[#neighbours+1]=held;neighbours[#neighbours+1]=hard_blocker
assert(not contact.settle(wall,held,held_plan.point))
for pass=1,6 do
    clock=pass*.5
    for _,u in ipairs(fronts) do assert(contact.resolve(wall,u,1).claimed) end
    local current=assert(contact.resolve(wall,held,1))
    if pass<6 then assert(current.claimed,'lease expired before the bounded no-progress window')
    else assert(not current.claimed and held.radius==32,'hard-blocked lease must expire with its original body') end
end

local env=setmetatable({},{__index=_G});env._G=env
env.class=function(t) return t end;env.LinkLuaModifier=function() end
env.MODIFIER_STATE_ROOTED=4;env.MODIFIER_STATE_DISARMED=5;env.MODIFIER_STATE_NO_UNIT_COLLISION=6
env.require=function(name) if name=='systems/wall_melee_contact' then return contact end return {} end
local chunk=assert(loadfile('scripts/vscripts/modifiers/modifier_enemy_wall_ai.lua'));setfenv(chunk,env)
local ai=chunk()
local m=setmetatable({no_unit_collision=true},{__index=ai})
function m:GetStackCount() return self.stack end
for mode=0,6 do
    m.stack=mode;local state=m:CheckState()
    assert(not state[6],'all movement/attack modes must retain native unit collision')
    assert(not not state[4]==(mode==2 or mode==6),'only active stationary attack states own a root')
    assert(not not state[5]==(mode==1 or mode==3 or mode==4 or mode==5),'nonattacking routes stay disarmed')
end
contact.reset()
print('WALL_CONTACT_SOLID_PASS fixed physical hulls, actual-body occupancy, padded compression, no phase exemptions, hard-block lease expiry, native32 acceptance, zero teleports')
