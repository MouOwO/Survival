package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 0} end
local clock,nav_queries=0,0
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
local obstacles,entities={},{}
GridNav={IsTraversable=function(_,p)
    nav_queries=nav_queries+1;return math.abs(p.y)<128
end,IsBlocked=function(_,p)
    nav_queries=nav_queries+1
    for _,o in ipairs(obstacles) do
        if not o.removed and p.x>=o.p.x-64 and p.x<o.p.x+64
            and p.y>=o.p.y-64 and p.y<o.p.y+64 then return true end
    end
    return false
end,FindPathLength=function(_,a,b)
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end}
SpawnEntityFromTableSynchronous=function(_,kv)
    local o={p=kv.origin,IsNull=function(self) return self.removed end}
    obstacles[#obstacles+1]=o;return o
end
DoEntFireByInstanceHandle=function() end
UTIL_Remove=function(o) o.removed=true end
IsServer=function() return true end;class=function(t) return t end;LinkLuaModifier=function() end
DOTA_UNIT_CAP_MELEE_ATTACK=1;DOTA_TEAM_BADGUYS=3
DOTA_UNIT_ORDER_ATTACK_TARGET=2;DOTA_UNIT_ORDER_MOVE_TO_POSITION=3
MODIFIER_STATE_ROOTED=4;MODIFIER_STATE_DISARMED=5;MODIFIER_STATE_NO_UNIT_COLLISION=6
package.loaded['core/team_alignment']={are_enemies=function() return true end,enforce=function() end}
EntIndexToHScript=function(index) return entities[index] end
ExecuteOrderFromTable=function(order)
    local u=entities[order.UnitIndex];u.orders=u.orders+1
end
local function unit(id,x,y,radius,capability)
    local u={p=Vector(x,y,384),radius=radius,capability=capability or 1,orders=0,stops=0,corrections=0}
    function u:entindex() return id end
    function u:GetAbsOrigin() return self.p end
    function u:SetAbsOrigin(p) self.p=p;self.corrections=self.corrections+1 end
    function u:IsNull() return false end
    function u:IsAlive() return true end
    function u:GetHullRadius() return self.radius end
    function u:GetAttackCapability() return self.capability end
    function u:GetMoveCapability() return 1 end
    function u:GetTeamNumber() return 3 end
    function u:GetForceAttackTarget() return self.force end
    function u:SetForceAttackTarget(target) self.force=target end
    function u:Script_GetAttackRange() return (self.capability==2 and 550 or 128)+(self.ai and self.ai.contact_range_delta or 0) end
    function u:GetAttacksPerSecond() return 1 end
    function u:IsStunned() return false end
    function u:IsCommandRestricted() return false end
    function u:IsRooted() return self.ai and self.ai.contact_locked end
    function u:IsDisarmed() return self.ai and self.ai.contact_waiting end
    function u:IsIdle() return false end
    function u:Stop() self.stops=self.stops+1 end
    function u:SetSize() end
    function u:RemoveModifierByName() end
    entities[id]=u;return u
end
local navigation=require('systems/wall_navigation_service')
local contact=require('systems/wall_melee_contact')
local ai=require('modifiers/modifier_enemy_wall_ai')
local wall=unit(1,0,0,128)
navigation.create(wall)
local cases={
    {name='ground_melee',radius=32,x=-192,y=32},
    {name='ground_ranged',radius=32,x=-220,y=0,capability=2},
    {name='flying_combat_with_ground_navigation',radius=32,x=-220,y=0,movement='flying'},
    {name='challenge_without_unit_collision',radius=0,x=-200,y=0,no_collision=1},
    {name='large_hull_melee',radius=128,x=-288,y=0},
}
for i,case in ipairs(cases) do
    contact.reset();clock=0
    local u=unit(10+i,case.x,case.y,case.radius,case.capability)
    u.survival_wave_movement_type=case.movement or 'ground'
    local m=setmetatable({GetParent=function() return u end,StartIntervalThink=function() end},{__index=ai})
    u.ai=m;m:OnCreated({wall_entindex=1,no_unit_collision=case.no_collision})
    m:OnIntervalThink()
    assert(u.orders==1 and u.corrections<=1 and m.boundary_position.x==u.p.x)
    local initial_corrections=u.corrections
    if case.no_collision then assert(m:CheckState()[MODIFIER_STATE_NO_UNIT_COLLISION]) end
    local before_orders,before_stops=u.orders,u.stops
    local before_nav=nav_queries
    -- Movement across the entire wall can finish outside its far edge in one
    -- observation. This must still return to the previously observed front.
    u.p=Vector(-case.x,case.y,384);clock=.5;m:OnIntervalThink()
    assert(u.p.x<0 and u.corrections==initial_corrections+1,case.name..' crosses the square only through boundary correction')
    assert(m.boundary_position.x==u.p.x,'snapshot uses the corrected position')
    local displaced_contact=m.ai_state=='approach'
    assert(u.orders==before_orders and u.stops==before_stops,
        'a displaced contact waits for native phase; native chase does not restart')
    if displaced_contact then
        assert(m.phase_order_frame,'displaced contact must schedule its phase frame')
        clock=clock+1/30;m:OnIntervalThink()
        assert(not m.phase_order_frame,'the deferred phase frame must return to the normal cadence')
    end
    if case.capability==2 then assert(u:Script_GetAttackRange()==550,'ranged reach unchanged') end
    local boundary_nav=nav_queries
    for pass=1,3 do
        clock=.5+pass*.25
        if m.ai_state=='attack' then m:OnAttackStart({attacker=u,target=wall}) end
        m:OnIntervalThink()
        assert(u.corrections==initial_corrections+(displaced_contact and 2 or 1)
            and u.orders==before_orders+(displaced_contact and 1 or 0)
            and u.stops==before_stops+(displaced_contact and 1 or 0),
            'only a displaced precise contact aligns once and resumes its attack')
        if pass==1 then boundary_nav=nav_queries end
    end
    assert(nav_queries==boundary_nav,'normal frames do no extra boundary GridNav work')
    assert(boundary_nav>before_nav,'only real penetration checks corrected destination')
    m:OnDestroy();assert(m.boundary_position==nil,'destroy clears previous-wall position')
end

-- A new wall must not see the position recorded against the previous wall.
contact.reset();clock=0
local other_wall=unit(2,1000,0,128);navigation.create(other_wall)
local u=unit(30,-192,32,32)
local m=setmetatable({GetParent=function() return u end,StartIntervalThink=function() end},{__index=ai})
u.ai=m;m:OnCreated({wall_entindex=1});m:OnIntervalThink()
m:SetWallEntIndex(2);assert(m.boundary_position==nil)
u.p=Vector(1192,32,384);clock=.5;m:OnIntervalThink()
assert(u.corrections==0 and u.p.x==1192,'first observation at a new wall does not use old crossing history')
navigation.clear(wall);navigation.clear(other_wall)
print('ENEMY_WALL_BOUNDARY_AI_PASS ground/ranged/flying/challenge/large hull protection, stable orders, bounded nav work, retarget cleanup')
