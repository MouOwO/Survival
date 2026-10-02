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
assert(not waiting.claimed and waiting.point.x==-192,"overflow stays at local approach, no rear queue")
assert(paths==before,"full front does not run path searches for every waiting monster")
local other_side=unit(7,350,0)
assert(contact.resolve(wall,other_side).point.x==-192,
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
print("WALL_MELEE_CONTACT_PASS four reachable lanes, range at corners, bounded path work, death/stale release, directional paths")
