-- Strict offline terrain geometry, not a Dota engine movement acceptance test.
-- Restore front owners' native hulls on exit without leaving an otherwise
-- movable body embedded in a wall/bank or bypassing new obstructions/control.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,next_id,terrain=0,0,nil
local function copy(p) return Vector(p.x,p.y,p.z) end
local function distance(a,b)
    local dx,dy=a.x-b.x,a.y-b.y
    return math.sqrt(dx*dx+dy*dy)
end
local function local_coordinates(p)
    if terrain.face==1 then return -p.x,p.y
    elseif terrain.face==2 then return p.x,p.y
    elseif terrain.face==3 then return -p.y,p.x
    else return p.y,p.x end
end
local function point(normal,lateral)
    if terrain.face==1 then return Vector(-normal,lateral,384)
    elseif terrain.face==2 then return Vector(normal,lateral,384)
    elseif terrain.face==3 then return Vector(lateral,-normal,384)
    else return Vector(lateral,normal,384) end
end
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function(p) return terrain.height and terrain.height(p) or 384 end
GridNav={
    IsTraversable=function(_,p)
        local _,lateral=local_coordinates(p)
        return math.abs(lateral)<terrain.half
    end,
    IsBlocked=function(_,p)
        return (math.abs(p.x)<128 and math.abs(p.y)<128)
            or (terrain.blocked and terrain.blocked(p)) or false
    end,
    FindPathLength=function(_,a,b)
        local n1=local_coordinates(a)
        local n2=local_coordinates(b)
        return n1*n2<0 and -1 or distance(a,b)
    end,
}
local function entity(p,radius)
    next_id=next_id+1
    local u={index=next_id,p=copy(p),radius=radius,original=radius,
        survival_monster_hull_radius=radius,position_writes=0,hull_writes=0}
    function u:entindex() return self.index end
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return not self.dead end
    function u:GetAbsOrigin() return self.p end
    function u:SetAbsOrigin(value) self.p=copy(value);self.position_writes=self.position_writes+1 end
    function u:GetHullRadius() return self.radius end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:SetHullRadius(value) self.radius=value;self.hull_writes=self.hull_writes+1 end
    function u:IsStunned() return self.stunned or false end
    function u:IsCommandRestricted() return self.restricted or false end
    function u:IsRooted() return false end
    function u:IsCurrentlyHorizontalMotionControlled() return self.horizontal or false end
    function u:IsCurrentlyVerticalMotionControlled() return self.vertical or false end
    return u
end
-- This fixture supplies the same fixed terrain cross-section that the real
-- navigation registration caches. Narrow lanes must not inherit open-floor64.
package.loaded['systems/wall_navigation_service']={contact_layout=function()
    return {gate=true,axis=terrain.face<=2 and 1 or 2,min=-terrain.half,max=terrain.half,center=0}
end}
local contact=require('systems/wall_melee_contact')
local function begin(width,face)
    contact.reset()
    clock=0
    terrain={half=width/2,face=face}
    return entity(Vector(0,0,384),128)
end
local function admitted(wall,radius,lateral)
    local u=entity(point(400,lateral),radius)
    local plan=assert(contact.resolve(wall,u))
    local pitch=math.min(64,terrain.half*.5)
    assert(plan.claimed and u:GetHullRadius()==math.min(radius,pitch*.5-12),
        'exit fixture did not receive a bounded front reservation')
    u.p=copy(plan.point)
    return u,plan.point
end
local function sample_clear(p)
    return GridNav:IsTraversable(p) and not GridNav:IsBlocked(p)
        and math.abs(GetGroundHeight(p)-384)<=32
end
local function full_clear(p,radius)
    local _,lateral=local_coordinates(p)
    if math.abs(lateral)+radius>terrain.half then return false end
    local nx=math.max(-128,math.min(128,p.x))
    local ny=math.max(-128,math.min(128,p.y))
    if (p.x-nx)^2+(p.y-ny)^2<radius*radius then return false end
    local inside=math.max(0,radius-1)
    for _,offset in ipairs({{0,0},{inside,0},{-inside,0},{0,inside},{0,-inside}}) do
        if not sample_clear(Vector(p.x+offset[1],p.y+offset[2],384)) then return false end
    end
    return true
end
local function assert_safe_short_exit(before,after,radius)
    assert(distance(before,after)<=128,'exit alignment exceeded its bounded short segment')
    local steps=math.max(1,math.ceil(distance(before,after)/16))
    local inside=math.max(0,radius-1)
    for index,offset in ipairs({{0,0},{inside,0},{-inside,0},{0,inside},{0,-inside}}) do
        local cleared=false
        for step=0,steps do
            local fraction=step/steps
            local p=Vector(before.x+(after.x-before.x)*fraction+offset[1],
                before.y+(after.y-before.y)*fraction+offset[2],384)
            local clear=sample_clear(p)
            assert(clear or (index~=1 and not cleared and step~=steps),
                'exit segment crossed a center obstacle or newly penetrated a peripheral obstacle')
            cleared=cleared or clear
        end
    end
end
local function native_can_step_out(u)
    if not full_clear(u.p,u:GetHullRadius()) then return false end
    local normal,lateral=local_coordinates(u.p)
    return full_clear(point(normal+12,lateral),u:GetHullRadius())
end
local function exit(wall,u,operation)
    if operation=='release' then contact.release(wall:entindex(),u:entindex())
    elseif operation=='clear' then contact.clear(wall:entindex())
    elseif operation=='reset' then contact.reset()
    else error('unknown exit operation '..operation) end
end
local function assert_restored(u,label)
    assert(u:GetHullRadius()==u.original,label..': original native hull was not restored')
    assert(u.survival_monster_hull_radius==u.original,label..': policy metadata was changed')
end

local checked=0
-- All faces and both real passage widths. Full bodies which were already safe
-- must not be moved; unsafe outer contacts receive exactly one bounded move.
for _,width in ipairs({192,256}) do
    for face=1,4 do
        for _,radius in ipairs({32,64}) do
            for _,operation in ipairs({'release','clear','reset'}) do
                local wall=begin(width,face)
                local u=admitted(wall,radius,72)
                local before=copy(u.p)
                local needed=not full_clear(before,radius)
                exit(wall,u,operation)
                local label=width..' width face '..face..' Hull'..radius..' '..operation
                assert_restored(u,label)
                assert(full_clear(u.p,radius),label..': restored front body intersects the bank or wall')
                assert(native_can_step_out(u),label..': restored body cannot take its first native retreat step')
                assert(u.position_writes==(needed and 1 or 0),label..': alignment was missing or repeated')
                if needed then assert_safe_short_exit(before,u.p,radius) end
                local writes=u.position_writes
                contact.release(wall:entindex(),u:entindex())
                contact.clear(wall:entindex());contact.reset()
                assert(u.position_writes==writes,label..': repeated cleanup wrote position again')
                checked=checked+1
            end
        end
    end
end

-- A blocked destination never authorizes an unsafe forced exit, whether an
-- explicit owner release, wall destruction, or global reset triggered cleanup.
for _,operation in ipairs({'release','clear','reset'}) do
    local wall=begin(192,1)
    local u=admitted(wall,64,72)
    local before=copy(u.p)
    terrain.blocked=function(p)
        local normal,lateral=local_coordinates(p)
        return math.abs(normal-224)<=2 and math.abs(lateral)<96
    end
    exit(wall,u,operation)
    assert_restored(u,'blocked '..operation)
    assert(u.position_writes==0 and distance(u.p,before)==0,
        'blocked '..operation..': an unavailable exit still forced the owner into an obstacle')
    checked=checked+1
end

-- Safe destination samples alone are insufficient: the short segment must
-- reject center obstructions, new peripheral penetration, and reentry after
-- a previously overlapping hull sample has already cleared its old obstacle.
for _,kind in ipairs({'center','peripheral','reentry','height'}) do
    local wall=begin(192,1)
    local u=admitted(wall,64,72)
    local before=copy(u.p)
    local function obstruction(p)
        local normal,lateral=local_coordinates(p)
        if kind=='center' or kind=='height' then
            return normal>=196 and normal<=212 and lateral>=25 and lateral<=65
        elseif kind=='peripheral' then
            return normal>=260 and normal<=272 and lateral>=25 and lateral<=65
        else
            return normal>=143 and normal<=158 and lateral>=-1 and lateral<=65
        end
    end
    if kind=='height' then terrain.height=function(p) return obstruction(p) and 512 or 384 end
    else terrain.blocked=obstruction end
    for _,lateral in ipairs({24,8,0}) do
        assert(full_clear(point(224,lateral),64),kind..': fixture must have a clear destination')
    end
    contact.release(wall:entindex(),u:entindex())
    assert_restored(u,kind..' obstruction')
    assert(u.position_writes==0 and distance(u.p,before)==0,
        kind..': exit bypassed an unsafe short segment')
    checked=checked+1
end

-- Corpses still have valid native entities, but alignment must not move them.
-- Remote/illegal positions and external control must not be pulled into the
-- old contact. Cleanup restores the collision policy even if motion is unsafe.
for _,state in ipairs({'dead','remote','inside_wall','stunned','restricted','horizontal','vertical'}) do
    local wall=begin(192,1)
    local u=admitted(wall,64,72)
    if state=='remote' then u.p=point(500,72)
    elseif state=='inside_wall' then u.p=point(120,72)
    else u[state]=true end
    local before=copy(u.p)
    assert(not u:IsNull(),'cleanup fixture must still hold a valid native entity')
    contact.release(wall:entindex(),u:entindex())
    assert_restored(u,state..' cleanup')
    assert(u.position_writes==0 and distance(u.p,before)==0,
        state..': cleanup changed a controlled, dead, remote, or illegal center position')
    checked=checked+1
end

-- A body larger than the entire passage cannot acquire a legal full-hull exit.
-- It must retain its configured radius and location, never cross the wall or
-- silently shrink the permanent collision policy to make an exit appear valid.
for _,width in ipairs({192,256}) do
    local wall=begin(width,1)
    local u=admitted(wall,width/2+1,72)
    local before=copy(u.p)
    contact.release(wall:entindex(),u:entindex())
    assert_restored(u,'body wider than '..width..' passage')
    assert(u.position_writes==0 and distance(u.p,before)==0,
        'an oversized body was forced through a geometrically unavailable exit')
    checked=checked+1
end

-- Stalled in-flight reservations take the same exit path. Fill the other
-- three slots so the retired owner cannot immediately reacquire a new one.
-- Navigation and position are stable until the three-second stall expires.
for _,blocked in ipairs({false,true}) do
    local wall=begin(192,1)
    local u=admitted(wall,64,72)
    u.p=point(200,72)
    local before=copy(u.p)
    local others={}
    for _,lateral in ipairs({-72,-24,24}) do
        local other,destination=admitted(wall,32,lateral)
        assert(contact.settle(wall,other,destination),'stationary exit fixture must actually settle')
        others[#others+1]=other
    end
    if blocked then
        terrain.blocked=function(p)
            local normal,lateral=local_coordinates(p)
            return math.abs(normal-224)<=2 and math.abs(lateral)<96
        end
    end
    local plan
    for pass=1,8 do
        clock=pass*.5
        for _,other in ipairs(others) do assert(contact.resolve(wall,other).claimed) end
        plan=contact.resolve(wall,u)
        if pass<=6 then
            assert(plan.claimed and u.position_writes==0,
                'an active reservation was aligned before its bounded stall timeout')
        end
    end
    assert(plan and not plan.claimed,'stalled owner did not release its unavailable reservation')
    assert_restored(u,blocked and 'blocked stall exit' or 'normal stall exit')
    if blocked then
        assert(u.position_writes==0 and distance(u.p,before)==0,'stall exit bypassed its blocked destination')
    else
        assert(u.position_writes==1 and native_can_step_out(u),'stalled owner remained embedded after restoration')
        assert_safe_short_exit(before,u.p,64)
    end
    checked=checked+1
end
contact.reset()
print('WALL_CONTACT_EXIT_PASS geometry_cases='..checked
    ..' widths=192/256 faces=4 hulls=32/64 bounded_single_alignment=1 controlled_and_blocked_alignment=0')
