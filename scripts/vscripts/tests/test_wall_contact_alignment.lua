-- Admission safety at actual native MOVE positions. The2026-10-16 physical
-- contract replaces coordinate alignment: invalid hulls must wait, never snap
-- or shrink into a legal slot. This is geometry/control, not native physics.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,blocked,ground=0,nil,nil
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function(p) return ground and ground(p) or 384 end
GridNav={IsTraversable=function(_,p) return math.abs(p.y)<192 end,
    IsBlocked=function(_,p) return (math.abs(p.x)<128 and math.abs(p.y)<128)
        or (blocked and blocked(p)) or false end,
    FindPathLength=function(_,a,b)
        if a.x*b.x<0 then return -1 end
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    end}
package.loaded['systems/wall_navigation_service']={}
local contact=require('systems/wall_melee_contact')
local function unit(id,x,y,radius)
    local u={p=Vector(x,y,384),radius=radius or 32,writes=0,hull_writes=0}
    function u:entindex() return id end
    function u:IsNull() return false end
    function u:IsAlive() return true end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return self.radius end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:SetHullRadius() self.hull_writes=self.hull_writes+1;error('no tactical hull') end
    function u:SetAbsOrigin() self.writes=self.writes+1;error('no coordinate alignment') end
    function u:IsStunned() return self.stunned end
    function u:IsCommandRestricted() return self.restricted end
    function u:IsRooted() return self.rooted end
    function u:IsCurrentlyHorizontalMotionControlled() return self.horizontal end
    function u:IsCurrentlyVerticalMotionControlled() return self.vertical end
    return u
end
local wall=unit(1,0,0,128)
local function claim(lateral)
    contact.reset();blocked=nil;ground=nil;clock=clock+10
    local u=unit(2,-400,lateral)
    local plan=assert(contact.resolve(wall,u,1))
    assert(plan.claimed and plan.point.x==-184 and plan.point.y==lateral and u.radius==32)
    return u,plan.point
end
local function unchanged(u,before,label)
    assert(u.writes==0 and u.hull_writes==0 and u.p.x==before.x and u.p.y==before.y and u.p.z==before.z,
        label..': admission must never move or resize the actor')
end
local function reject(u,point,label)
    local before=Vector(u.p.x,u.p.y,u.p.z)
    assert(not contact.settle(wall,u,point),label..': invalid admission accepted')
    unchanged(u,before,label)
end
for _,sign in ipairs({-1,1}) do
    local u,point=claim(sign*132)
    u.p=Vector(-184,sign*160,384)
    assert(contact.arrived(wall,u,point,false))
    local before=Vector(u.p.x,u.p.y,u.p.z)
    assert(contact.settle(wall,u,point),'a native-valid body near its slot may attack from its actual position')
    assert(contact.settle(wall,u,point),'repeated safe admission must remain idempotent')
    unchanged(u,before,'native valid arrival')
    u.p=Vector(-184,sign*166,384)
    assert(GridNav:IsTraversable(u.p) and not GridNav:IsBlocked(u.p),'fixture must have a valid native center')
    assert(contact.arrived(wall,u,point,false),'the invalid hull must still be within the admission tolerance')
    reject(u,point,'peripheral bank overlap')
end
do
    local u,point=claim(44);u.p=Vector(-150,44,384)
    assert(not GridNav:IsBlocked(u.p),'fixture center must be outside the wall')
    reject(u,point,'existing physical wall overlap')
end
do
    local u,point=claim(44);u.p=Vector(184,44,384)
    reject(u,point,'opposite wall side')
end
do
    local u,point=claim(44);u.p=Vector(-248,44,384)
    reject(u,point,'second row64 behind slot')
end
-- All following arrivals are inside the native32 stopping allowance. Safe
-- endpoint tests alone cannot authorize attack across a newly blocked chord.
do
    local u,point=claim(44);u.p=Vector(-216,44,384)
    blocked=function(p) return math.abs(p.x+200)<.5 and math.abs(p.y-44)<.5 end
    reject(u,point,'center segment obstacle')
end
do
    local u,point=claim(44);u.p=Vector(-216,44,384)
    ground=function(p) return math.abs(p.x+200)<.5 and 448 or 384 end
    reject(u,point,'center segment elevation discontinuity')
end
do
    local u,point=claim(44);u.p=Vector(-216,44,384)
    blocked=function(p) return math.abs(p.x+200)<.5 and math.abs(p.y-75)<.5 end
    reject(u,point,'new peripheral segment penetration')
end
for _,at_goal in ipairs({false,true}) do
    local u,point=claim(44);u.p=Vector(at_goal and -184 or -216,44,384)
    blocked=function(p) return math.abs(p.x+184)<.5 and math.abs(p.y-44)<.5 end
    reject(u,point,at_goal and 'unsafe actual destination' or 'newly blocked cached destination')
end
do
    local u,point=claim(44);u.p=Vector(-216,44,448)
    reject(u,point,'different elevation plane')
end
for _,control in ipairs({'stunned','restricted','rooted','horizontal','vertical'}) do
    local u,point=claim(44);u.p=Vector(-216,44,384);u[control]=true
    reject(u,point,'external control '..control)
end
do
    local u,point=claim(44);u.p=Vector(-216,44,384)
    contact.release(wall:entindex(),u:entindex())
    assert(u.radius==32,'release must keep the original body')
    reject(u,point,'released reservation')
end
contact.reset()
print('WALL_CONTACT_ALIGNMENT_PASS no snaps or resizing, native positions, full bank/wall hull rejection, endpoint/segment terrain, heights, external control priority, released reservation')
