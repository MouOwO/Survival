-- A real native route around an open wall must be able to pass a crowded
-- source row. NO_UNIT_COLLISION affects units only; the native route still
-- respects the square and terrain. Tools exercises the real engine path.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,paths,gate,path_length=0,0,false,700
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
GridNav={IsTraversable=function() return true end,
    IsBlocked=function(_,p) return math.abs(p.x)<128 and math.abs(p.y)<128 end,
    FindPathLength=function(_,a,b)
        paths=paths+1
        return b.x==184 and path_length or -1
    end}
package.loaded['systems/wall_navigation_service']={contact_layout=function()
    return {gate=gate,axis=1,min=-128,max=128,bounds={min_x=-128,max_x=128,min_y=-128,max_y=128}}
end}
local contact=require('systems/wall_melee_contact')
local index=0
local function unit(x,y,radius)
    index=index+1
    local u={index=index,p=Vector(x,y),radius=radius,survival_monster_hull_radius=radius}
    function u:entindex() return self.index end
    function u:IsNull() return false end
    function u:IsAlive() return true end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return self.radius end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:SetHullRadius(r) self.radius=r end
    function u:GetIdealSpeed() return 240 end
    function u:IsStunned() return self.stunned or false end
    function u:IsCommandRestricted() return false end
    function u:IsRooted() return false end
    return u
end
local function fixture()
    contact.reset();clock=0
    local wall,u=unit(0,0,128),unit(-420,0,32)
    local plan=assert(contact.resolve(wall,u))
    assert(plan.claimed and plan.point.x==184,'fixture must own an actually reachable opposite face')
    return wall,u,plan
end
local wall,u,plan=fixture()
local before=paths
assert(contact.entry_ready(wall,u,plan.point),'a native-proven open route remained solid behind its crowded source row')
assert(paths==before,'native route entry repeated the already completed route query')
for _=1,1000 do assert(contact.entry_ready(wall,u,plan.point)) end
assert(paths==before,'stable native route proof repeated path queries')

-- Follow a fixed native-style route around the square and through a rear
-- body. Its circular hull never intersects the square despite the final
-- destination's direct chord crossing it.
local corners={Vector(-184,-184),Vector(184,-184),plan.point}
local blocker=Vector(-302,-92)
local passed_body=false
for _,goal in ipairs(corners) do
    local start=u.p
    local dx,dy=goal.x-start.x,goal.y-start.y
    local steps=math.ceil(math.sqrt(dx*dx+dy*dy)/8)
    for step=1,steps do
        u.p=Vector(start.x+dx*step/steps,start.y+dy*step/steps)
        local nx=math.max(-128,math.min(128,u.p.x))
        local ny=math.max(-128,math.min(128,u.p.y))
        assert((u.p.x-nx)^2+(u.p.y-ny)^2>=u.radius*u.radius,'native route crossed the square')
        if (u.p.x-blocker.x)^2+(u.p.y-blocker.y)^2<52^2 then
            assert(contact.entry_ready(wall,u,plan.point),'legal route could not pass its blocking rear unit')
            passed_body=true
        end
    end
end
assert(passed_body,'fixture did not exercise crowd traversal')
assert(contact.settle(wall,u,plan.point),'legal native route did not settle at its real reserved contact')

-- Only a current, bounded, open-map path is proof. A sealed doorway or an
-- oversized detour must retain collision; external control and real wall
-- overlap must never gain phase from a cached route.
for _,kind in ipairs({'sealed','long','expired','relocated','controlled','inside'}) do
    gate=kind=='sealed';path_length=kind=='long' and 2000 or 700
    wall,u,plan=fixture()
    if kind=='expired' then clock=9
    elseif kind=='relocated' then wall.survival_wall_relocation_revision=1
    elseif kind=='controlled' then u.stunned=true
    elseif kind=='inside' then u.p=Vector(0,0) end
    before=paths
    assert(not contact.entry_ready(wall,u,plan.point),kind..' reused an unsafe native route proof')
    assert(paths==before,kind..' entry guard searched another path')
end
contact.reset()
print('WALL_NATIVE_ROUTE_ENTRY_PASS bounded_cached_path crowded_source real_square native_waypoints sealed_expiry_revision_control_guards')
