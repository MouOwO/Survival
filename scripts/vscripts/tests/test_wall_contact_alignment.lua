-- Safe recovery from a native-valid center whose peripheral hull samples are
-- already outside the bank. Exercise real contact admission and alignment;
-- this models geometry, not the complete Dota navigation/physics engine.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,blocked,ground=0,nil,nil
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function(p)
    return ground and ground(p) or 384
end
GridNav={
    IsTraversable=function(_,p) return math.abs(p.y)<128 end,
    IsBlocked=function(_,p)
        return (math.abs(p.x)<128 and math.abs(p.y)<128)
            or (blocked and blocked(p)) or false
    end,
    FindPathLength=function(_,a,b)
        if a.x*b.x<0 then return -1 end
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    end,
}
local contact=require('systems/wall_melee_contact')
local function unit(id,x,y,radius)
    local u={p=Vector(x,y,384),radius=radius or 32,writes=0}
    function u:entindex() return id end
    function u:IsNull() return false end
    function u:IsAlive() return true end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return self.radius end
    function u:SetAbsOrigin(p) self.p=Vector(p.x,p.y,p.z);self.writes=self.writes+1 end
    return u
end
local wall=unit(1,0,0,128)
local function claim(lateral)
    contact.reset();blocked=nil;ground=nil;clock=clock+10
    local u=unit(2,-400,lateral)
    local plan=assert(contact.resolve(wall,u))
    assert(plan.claimed and plan.point.x==-192 and plan.point.y==lateral)
    return u,plan.point
end
local function unchanged(u,before,label)
    assert(u.writes==0 and u.p.x==before.x and u.p.y==before.y and u.p.z==before.z,
        label..': unsafe alignment moved the unit')
end
local function reject(u,point,label)
    local before=Vector(u.p.x,u.p.y,u.p.z)
    assert(not contact.settle(wall,u,point),label..': unsafe alignment accepted')
    unchanged(u,before,label)
end

for _,sign in ipairs({-1,1}) do
    local u,point=claim(sign*96)
    u.p=Vector(-192,sign*110,384)
    assert(GridNav:IsTraversable(u.p) and not GridNav:IsBlocked(u.p),'native center must be navigable')
    assert(contact.arrived(wall,u,point,false),'fourteen-unit correction must be in settle range')
    assert(contact.settle(wall,u,point),'existing bank overlap must allow a short inward alignment')
    assert(u.p.x==point.x and u.p.y==point.y and u.writes==1,'bank recovery must align once')
    assert(contact.settle(wall,u,point) and u.writes==1,'already aligned contact must not write position again')
end

-- Existing peripheral overlap into the wall may move out along a safe center
-- segment. The center itself must never enter the wall or cross to its rear.
do
    local u,point=claim(32)
    u.p=Vector(-150,32,384)
    assert(not GridNav:IsBlocked(u.p),'overlapping hull still has an exterior center')
    assert(contact.settle(wall,u,point),'an already overlapping wall edge must be allowed to clear outward')
    assert(u.p.x==-192 and u.p.y==32 and u.writes==1)
end
do
    local u,point=claim(32)
    u.p=Vector(192,32,384)
    reject(u,point,'opposite wall side')
end

-- Both endpoints have clear hulls, but the short center segment intersects a
-- newly placed obstruction. The small sampled obstruction isolates this rule.
do
    local u,point=claim(32)
    u.p=Vector(-256,32,384)
    blocked=function(p) return math.abs(p.x+240)<2 and math.abs(p.y-32)<2 end
    reject(u,point,'center segment obstacle')
end
do
    local u,point=claim(32)
    u.p=Vector(-256,32,384)
    ground=function(p) return math.abs(p.x+240)<2 and 448 or 384 end
    reject(u,point,'center segment elevation change')
end

-- Peripheral recovery is one-way: a sample that started clear may never
-- become blocked, and one that has cleared its old overlap cannot reenter.
do
    local u,point=claim(32)
    u.p=Vector(-256,32,384)
    blocked=function(p) return math.abs(p.x+240)<2 and math.abs(p.y-63)<2 end
    reject(u,point,'new peripheral penetration')
end
do
    local u,point=claim(32)
    u.p=Vector(-256,32,384)
    blocked=function(p)
        return math.abs(p.y-63)<2 and (math.abs(p.x+256)<2 or math.abs(p.x+224)<2)
    end
    reject(u,point,'peripheral reentry after clearing')
end

-- The destination must be revalidated even if the unit happens to be at the
-- exact cached point. A newly blocked contact does not authorize an attack.
for _,already_aligned in ipairs({false,true}) do
    local u,point=claim(32)
    u.p=Vector(already_aligned and -192 or -224,32,384)
    blocked=function(p) return math.abs(p.x+192)<2 and math.abs(p.y-32)<2 end
    reject(u,point,already_aligned and 'unsafe exact destination' or 'unsafe destination')
end
do
    local u,point=claim(32)
    u.p=Vector(-224,32,384)
    contact.release(wall:entindex(),u:entindex())
    reject(u,point,'released admission')
end
contact.reset()
print('WALL_CONTACT_ALIGNMENT_PASS existing bank/wall overlap recovery, exact endpoint validation, center obstacles/heights, no new peripheral penetration, released admission')
