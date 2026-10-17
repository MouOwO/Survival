-- A routed contact can stall beside a bank before reaching its own face.
-- Releasing that slot must not enlarge its live body into the bank. This is
-- an offline native-clearance regression; real movement is tested in Tools.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,allow_paths,terrain_reads=0,true,0
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
GridNav={
    IsTraversable=function(_,p)
        terrain_reads=terrain_reads+1
        return p.x>=128 or math.abs(p.y)<192
    end,
    IsBlocked=function(_,p) return math.abs(p.x)<128 and math.abs(p.y-64)<128 end,
    FindPathLength=function(_,a,b)
        if not allow_paths or b.x~=184 then return -1 end
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    end,
}
package.loaded['systems/wall_navigation_service']={contact_layout=function()
    return {gate=false,axis=1,bounds={min_x=-128,max_x=128,min_y=-128,max_y=128}}
end}
local next_id=0
local function entity(x,y,radius)
    next_id=next_id+1
    local u={index=next_id,p=Vector(x,y),radius=radius,survival_monster_hull_radius=radius,
        hull_writes=0,position_writes=0,survival_wall_contact_owner={}}
    function u:entindex() return self.index end
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return not self.dead end
    function u:GetAbsOrigin() return self.p end
    function u:SetAbsOrigin(p) self.p=p;self.position_writes=self.position_writes+1 end
    function u:GetHullRadius() return self.radius end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:SetHullRadius(r) self.radius=r;self.hull_writes=self.hull_writes+1 end
    function u:IsStunned() return false end
    function u:IsCommandRestricted() return false end
    function u:IsRooted() return false end
    function u:GetTeamNumber() return 3 end
    return u
end
local contact=require('systems/wall_melee_contact')
local function stalled()
    contact.reset();clock=0;allow_paths=true
    local wall=entity(0,64,128)
    local u=entity(-350,-120,32)
    local plan=assert(contact.resolve(wall,u))
    assert(plan.claimed and plan.point.x==184 and u.radius==20,'fixture needs a far-face tactical claim')
    u.p=Vector(-129,-171)
    clock=.5;assert(contact.resolve(wall,u).claimed)
    allow_paths=false;clock=4
    plan=assert(contact.resolve(wall,u))
    assert(not plan.claimed,'stalled far-face reservation was not retired')
    assert(u.radius==20,'retirement enlarged a live routed body into the bank')
    assert(u.survival_monster_hull_radius==32,'temporary release changed permanent hull policy')
    assert(u.position_writes==0,'deferred restoration teleported the routed actor')
    return wall,u
end

local wall,u=stalled()
assert(type(contact.restore_hull)=='function','existing AI observations need a bounded restoration hook')
local before=terrain_reads
for pass=1,20 do clock=4+pass*.5;contact.restore_hull(u) end
assert(u.radius==20 and u.position_writes==0,'unsafe or stationary restoration forced the actor into terrain')
assert(terrain_reads-before<=30,'unchanged blocked restoration repeated terrain work every observation')
u.p=Vector(220,-171)
assert(contact.restore_hull(u) and u.radius==32,'native movement into clear ground did not restore policy hull')
before=terrain_reads
for _=1,1000 do contact.restore_hull(u) end
assert(terrain_reads==before,'normal actors retained restoration overhead')

-- Reclaiming while still narrow must preserve the original32, not save20 as
-- its new permanent size; forced destruction/cleanup always restores it.
wall,u=stalled();allow_paths=true;clock=8
assert(contact.resolve(wall,u).claimed and u.radius==20,'released actor could not reclaim a real slot')
contact.release(wall:entindex(),u:entindex())
assert(u.radius==32,'reclaim lost the original collision policy')
for _,cleanup in ipairs({'unit','wall','reset','external'}) do
    wall,u=stalled()
    if cleanup=='unit' then contact.restore_hull(u,true)
    elseif cleanup=='wall' then contact.clear(wall:entindex())
    elseif cleanup=='reset' then contact.reset()
    else u:SetHullRadius(48);contact.restore_hull(u) end
    assert(u.radius==(cleanup=='external' and 48 or 32),cleanup..' leaked or overwrote collision policy')
    before=terrain_reads
    contact.restore_hull(u)
    assert(terrain_reads==before,cleanup..' left a restoration record')
end
contact.reset()
print('WALL_DEFERRED_HULL_PASS far_face_bank safe_restore cached_stationary reclaim cleanup external_policy')
