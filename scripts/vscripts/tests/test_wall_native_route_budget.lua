-- Native reachability for a local contact may not authorize a whole-map
-- detour. Check real allocator bounds and shared failure/backoff work.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,calls,path_length=0,0,1537
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end,
    FindPathLength=function() calls=calls+1;return path_length end}
package.loaded['systems/wall_navigation_service']={}
local contact=require('systems/wall_melee_contact')
local function unit(id,x,y)
    local u={p=Vector(x,y,384)}
    function u:entindex() return id end
    function u:IsNull() return false end
    function u:IsAlive() return true end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return 32 end
    function u:GetPaddedCollisionRadius() return 42 end
    function u:SetHullRadius() error('route admission must not resize a body') end
    function u:SetAbsOrigin() error('route admission must not move an actor') end
    return u
end
local wall=unit(1,0,0)
local rear=unit(2,-400,0)
local plan=assert(contact.resolve(wall,rear,1))
assert(not plan.claimed,'a1537-unit native detour must not claim a local contact')
assert(calls==4,'one failed face performs only its bounded four native routes')
for pass=1,20 do
    clock=pass*.05
    assert(not contact.resolve(wall,rear,1).claimed)
end
assert(calls==4,'unchanged blocked arrivals must share the existing two-second failure cache')
clock=2.5;path_length=1536
assert(contact.resolve(wall,rear,1).claimed,'a bounded legitimate1536-unit corner route remains accepted')
contact.reset();clock=0;calls=0;path_length=100000
for index=1,90 do
    local u=unit(10+index,-400,index*.01)
    assert(not contact.resolve(wall,u,1).claimed)
end
assert(calls<=16,'a burst of local failures must respect the per-wall half-second path budget')
contact.reset()
print('WALL_NATIVE_ROUTE_BUDGET_PASS1536 local path cap, valid corner route, cached stationary failures,90-arrival shared budget')
