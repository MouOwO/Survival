-- Offset-wall queue regression using the real allocator and AI.
-- Shares the bounded movement model of test_wall_waiter_retreat.lua; this file
-- is standalone. The body-closed entry and wall translate on the real64 grid;
-- actual offset/open-side cases are in test_wall_gate_contact_layout.lua.
-- It does not claim to reproduce native Dota physics.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,paths,nav_queries,rear_queries=0,0,0,0
local entities,monsters,controllers={}, {}, {}
local obstacles={}
local face,blocked,target,wall_offset,shape=1,nil,nil,0,"straight"
local contact_center=0
local function copy(p) return Vector(p.x,p.y,p.z) end
local function distance(a,b)
    local x,y=a.x-b.x,a.y-b.y
    return math.sqrt(x*x+y*y)
end
local function raw(normal,along)
    if face==1 then return Vector(-normal,along,384) end
    if face==2 then return Vector(normal,along,384) end
    if face==3 then return Vector(along,-normal,384) end
    return Vector(along,normal,384)
end
local function coordinate(normal,along) return raw(normal,along+wall_offset) end
local function contact_coordinate(normal,along) return raw(normal,along+contact_center) end
local function normal(p)
    if face==1 then return -p.x elseif face==2 then return p.x
    elseif face==3 then return -p.y else return p.y end
end
local function world_lateral(p) return face<=2 and p.y or p.x end
-- The gate's front fits four Hull20/native-padded30 contact slots at
-- every tested offset. Behind it the walkable bank can bend to a narrow,
-- off-center rear corridor. Its centers fit a Hull32 body at world -64,
-- although none of the gate-centered +/-96, +/-32, 0 candidate centers fit.
local function terrain(p)
    local n,a=normal(p),world_lateral(p)
    local low,high=wall_offset-128,wall_offset+128
    if shape=="turn" then
        local t=math.max(0,math.min(1,(n-208)/72))
        low=wall_offset-128+24*t;high=wall_offset+128-130*t
    elseif shape=="sealed" and n>216 then return false end
    return a>low and a<high
end
local function full_clear(p,radius)
    for _,o in ipairs({{0,0},{radius-1,0},{1-radius,0},{0,radius-1},{0,1-radius}}) do
        if not terrain(Vector(p.x+o[1],p.y+o[2],p.z)) then return false end
    end
    return true
end
local function safe_native_step(from,to,radius)
    for i,o in ipairs({{0,0},{radius-1,0},{1-radius,0},{0,radius-1},{0,1-radius}}) do
        local next_sample=Vector(to.x+o[1],to.y+o[2],to.z)
        if not terrain(next_sample) then
            local current_sample=Vector(from.x+o[1],from.y+o[2],from.z)
            -- A center cannot cross terrain. A pre-existing peripheral bank
            -- overlap can leave, but a clear hull sample cannot enter a bank.
            if i==1 or terrain(current_sample) then return false end
        end
    end
    return true
end
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function(p)
    if shape=='cliff' and normal(p)>=218 and normal(p)<=238 then return 768 end
    return 384
end
GridNav={
    IsTraversable=function(_,p)
        nav_queries=nav_queries+1
        return terrain(p)
    end,
    IsBlocked=function(_,p)
        nav_queries=nav_queries+1
        for _,o in ipairs(obstacles) do
            if not o.deleted and p.x>=o.p.x-64 and p.x<o.p.x+64
                and p.y>=o.p.y-64 and p.y<o.p.y+64 then return true end
        end
        -- The registered native entities above own the wall blockage. The
        -- underlying terrain queried before registration must remain free.
        return (blocked and blocked(p)) or false
    end,
    FindPathLength=function(_,a,b)
        paths=paths+1
        if normal(a)*normal(b)<0 then return -1 end
        return distance(a,b)
    end,
}
SpawnEntityFromTableSynchronous=function(name,kv)
    assert(name=='point_simple_obstruction' and kv.StartDisabled==0)
    local obstacle={p=copy(kv.origin),IsNull=function(self) return self.deleted==true end}
    obstacles[#obstacles+1]=obstacle
    return obstacle
end
DoEntFireByInstanceHandle=function(_,input) assert(input=='Disable') end
UTIL_Remove=function(obstacle) assert(not obstacle.deleted);obstacle.deleted=true end
IsServer=function() return true end
class=function(t) return t end
LinkLuaModifier=function() end
DOTA_UNIT_CAP_MELEE_ATTACK=1
DOTA_TEAM_BADGUYS=3;DOTA_TEAM_GOODGUYS=2
DOTA_UNIT_ORDER_ATTACK_TARGET=2;DOTA_UNIT_ORDER_MOVE_TO_POSITION=3
MODIFIER_STATE_ROOTED=4;MODIFIER_STATE_DISARMED=5
MODIFIER_STATE_NO_UNIT_COLLISION=6;MODIFIER_ATTRIBUTE_PERMANENT=7
DOTA_UNIT_TARGET_TEAM_BOTH=3;DOTA_UNIT_TARGET_BASIC=2;DOTA_UNIT_TARGET_HERO=1
DOTA_UNIT_TARGET_FLAG_NONE=0;FIND_ANY_ORDER=0
package.loaded['core/team_alignment']={
    are_enemies=function() return true end,
    enforce=function() error('unexpected team correction') end,
}
EntIndexToHScript=function(index) return entities[index] end
FindUnitsInRadius=function(_,origin,_,radius)
    rear_queries=rear_queries+1
    local nearby={}
    for _,u in ipairs(monsters) do
        if u:IsAlive() and distance(origin,u.p)<=radius+u.radius then nearby[#nearby+1]=u end
    end
    return nearby
end
ExecuteOrderFromTable=function(order)
    local u=assert(entities[order.UnitIndex])
    u.orders=u.orders+1
    if order.OrderType==DOTA_UNIT_ORDER_MOVE_TO_POSITION then
        local mode=u.ai:GetStackCount()
        if mode==3 or mode==4 then
            assert(u.native_phased,'phased MOVE preceded its native state frame')
        end
        if mode==4 then
            u.retreat_orders=u.retreat_orders+1
            assert(u:GetHullRadius()==u.original_radius,'retreat changed the waiting body hull')
            assert(not u:IsRooted() and u:IsDisarmed(),'retreat must move without permission to attack')
            assert(u:Script_GetAttackRange()==128,'retreat inherited the front attack range')
            if u.cancel_first_retreat and not u.cancelled_retreat then
                u.cancelled_retreat=true;u.cancelled_point=copy(order.Position)
                u.cancelled_time=clock;u.cancelled_stops=u.stops;u.order=nil
                return
            elseif u.cancelled_retreat and not u.recovered_retreat then
                assert(distance(order.Position,u.cancelled_point)<.01,'cancelled retreat changed its safe goal')
                assert(clock-u.cancelled_time<=.51,'cancelled retreat did not recover at its next observation')
                assert(u.stops==u.cancelled_stops,'retreat recovery unnecessarily stopped the unit')
                u.recovered_retreat=true
            end
        end
    end
    u.order={OrderType=order.OrderType,TargetIndex=order.TargetIndex,
        Position=order.Position and copy(order.Position)}
end
local function unit(id,p,radius)
    local u={p=copy(p),radius=radius or 32,original_radius=radius or 32,
        survival_monster_hull_radius=radius or 32,orders=0,stops=0,
        corrections=0,hits=0,next_attack=0,hull_writes=0,retreat_orders=0}
    function u:entindex() return id end
    function u:GetAbsOrigin() return self.p end
    function u:SetAbsOrigin(value) self.p=copy(value);self.corrections=self.corrections+1 end
    function u:IsNull() return false end
    function u:IsAlive() return not self.dead end
    function u:GetHullRadius() return self.radius end
    function u:SetHullRadius(value) self.radius=value;self.hull_writes=self.hull_writes+1 end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:GetTeamNumber() return 3 end
    function u:GetAttackCapability() return DOTA_UNIT_CAP_MELEE_ATTACK end
    function u:GetForceAttackTarget() return self.force end
    function u:SetForceAttackTarget(value) self.force=value end
    function u:Script_GetAttackRange() return 128+(self.ai and self.ai.contact_range_delta or 0) end
    function u:GetAttacksPerSecond() return 1 end
    function u:IsStunned() return self.stunned==true end
    function u:IsCommandRestricted() return self.restricted==true end
    function u:IsCurrentlyHorizontalMotionControlled() return self.horizontal==true end
    function u:IsCurrentlyVerticalMotionControlled() return self.vertical==true end
    function u:FindModifierByName(name) if name=='modifier_enemy_wall_ai' then return self.ai end end
    function u:IsRooted()
        return self.rooted==true or (self.ai and self.ai:CheckState()[MODIFIER_STATE_ROOTED])
    end
    function u:IsDisarmed()
        return self.disarmed==true or (self.ai and self.ai:CheckState()[MODIFIER_STATE_DISARMED])
    end
    function u:IsIdle() return not self.order end
    function u:Stop() self.stops=self.stops+1;self.order=nil end
    entities[id]=u;return u
end
local contact=require('systems/wall_melee_contact')
local navigation=require('systems/wall_navigation_service')
local ai=require('modifiers/modifier_enemy_wall_ai')
local function controller(u)
    local m=setmetatable({stack=0},{__index=ai})
    function m:GetParent() return u end
    function m:GetStackCount() return self.stack end
    function m:SetStackCount(value) self.stack=value end
    function m:StartIntervalThink(interval)
        self.interval=interval;self.next_think=clock+(interval==0 and .05 or interval)
    end
    function m:ForceRefresh()
        local previous_target,state,first=self.wall_entindex,self.ai_state,self.first_observation
        if self.OnRefresh then self:OnRefresh({}) end
        assert(self.wall_entindex==previous_target and self.ai_state==state and self.first_observation==first,
            'native state refresh reinitialized the AI')
        u.phase_refresh_pending=true
    end
    function m:SetHasCustomTransmitterData() end
    function m:SendBuffRefreshToClients() end
    u.ai=m;monsters[#monsters+1]=u;controllers[#controllers+1]=m
    m:OnCreated({wall_entindex=target:entindex()});return m
end
local function controlled(u)
    return u:IsRooted() or u:IsStunned() or u:IsCommandRestricted()
        or u:IsCurrentlyHorizontalMotionControlled() or u:IsCurrentlyVerticalMotionControlled()
end
local function move(u,goal,dt)
    if controlled(u) then return end
    local remaining=distance(u.p,goal)
    if remaining<=32 then return end -- Native MOVE can finish 32 units before its goal.
    local step=math.min((u.speed or 240)*dt,remaining-32)
    local next_p=Vector(u.p.x+(goal.x-u.p.x)*step/remaining,
        u.p.y+(goal.y-u.p.y)*step/remaining,384)
    if not safe_native_step(u.p,next_p,u.radius) or normal(next_p)<128+u.radius then return end
    if math.abs(GetGroundHeight(next_p,u)-u.p.z)>32 then return end
    if GridNav:IsBlocked(next_p) then return end
    if not u.native_phased then
        for _,other in ipairs(monsters) do
            if other~=u and other:IsAlive() and not other.native_phased then
                local separation=distance(next_p,other.p)
                local body=u:GetPaddedCollisionRadius()+other:GetPaddedCollisionRadius()
                if separation<body-.01 and separation<distance(u.p,other.p)-.01 then return end
            end
        end
    end
    u.p=next_p
end
local function frame(dt)
    clock=math.floor((clock+dt)*1000+.5)/1000
    for _,u in ipairs(monsters) do
        if u.phase_refresh_pending then
            u.native_phased=u.ai:CheckState()[MODIFIER_STATE_NO_UNIT_COLLISION]==true
            u.phase_refresh_pending=false
        end
    end
    for _,m in ipairs(controllers) do
        if m:GetParent():IsAlive() and m.next_think and clock+.0001>=m.next_think then
            m.next_think=clock+(m.interval==0 and .05 or m.interval);m:OnIntervalThink()
        end
    end
    for _,u in ipairs(monsters) do
        if u:IsAlive() and u.order then
            if u.order.OrderType==DOTA_UNIT_ORDER_MOVE_TO_POSITION then move(u,u.order.Position,dt)
            else
                local wall=entities[u.order.TargetIndex]
                if wall and wall:IsAlive() then
                    if distance(u.p,wall.p)>u:Script_GetAttackRange()+.01 then move(u,wall.p,dt)
                    elseif not u:IsStunned() and not u:IsCommandRestricted()
                        and not u:IsDisarmed() and clock>=u.next_attack then
                        assert(u.ai.ai_state=='attack','waiting or retreating unit attacked through the front')
                        u.hits=u.hits+1;u.next_attack=clock+1
                        u.ai:OnAttackStart({attacker=u,target=wall})
                    end
                end
            end
        end
    end
end
local function run(seconds) for _=1,math.floor(seconds/.05+.5) do frame(.05) end end
local function total(field)
    local value=0;for _,u in ipairs(monsters) do value=value+u[field] end;return value
end
local function fronts(label)
    local result,lanes={},{}
    for _,u in ipairs(monsters) do
        if u:IsAlive() and u.ai.ai_state=='attack' then
            result[#result+1]=u
            local along=world_lateral(u.p)-contact_center
            assert(math.abs(normal(u.p)-184)<.01,label..': front was displaced from the wall face')
            assert(along==-96 or along==-32 or along==32 or along==96,label..': wrong front lane')
            assert(not lanes[along],label..': duplicated front lane');lanes[along]=true
            assert(u.hits>0 and u.radius==20 and u:GetPaddedCollisionRadius()==30 and not u.native_phased,
                label..': contact must attack with its real native padded collision')
            assert(full_clear(u.p,u:GetPaddedCollisionRadius()),label..': padded front body overlaps a terrain bank')
        end
    end
    assert(#result==4,label..': expected four actual attacking contacts')
    for i=1,#result do for j=i+1,#result do
        assert(distance(result[i].p,result[j].p)>=result[i]:GetPaddedCollisionRadius()+result[j]:GetPaddedCollisionRadius()+4,
            label..': front bodies lack their native padded avoidance margin')
    end end
    return result
end

local function setup(side,offset,kind)
    if target then navigation.clear(target) end
    obstacles={}
    contact.reset();entities,monsters,controllers={},{},{}
    clock=0;face=side;wall_offset=offset;shape=kind;blocked=nil
    target=unit(1,coordinate(0,0),128)
    -- Every shape is a terrain-bounded gate. Register its real obstruction
    -- geometry, so the AI receives its proven approach face rather than the
    -- open-floor policy (the straight-path fixture cannot model side detours).
    navigation.create(target)
    local layout=assert(navigation.contact_layout(target),'fixture must register its real terrain-bounded gate')
    contact_center=wall_offset
    assert(#obstacles==4,'wall must register only its physical square')
    -- Seed already arrived attackers. The test concerns an established front,
    -- not the spawn route around the bend, which needs native path following.
    for index,along in ipairs({-96,-32,32,96}) do
        controller(unit(10+index,contact_coordinate(184,along)))
    end
    run(3);return fronts('initial '..kind..' face '..side..' offset '..offset)
end
local function rear(u,label)
    local attackers=fronts(label)
    assert(normal(u.p)>=184+30+42+8-.01,label..': fifth remained inside the padded front row')
    for _,front in ipairs(attackers) do
        assert(distance(u.p,front.p)>=u:GetPaddedCollisionRadius()+front:GetPaddedCollisionRadius()-.01,
            label..': fifth overlaps a native padded front attacker')
    end
    assert(u.ai.ai_state=='waiting' and not u.native_phased,label..': safe waiter retained retreat phase')
    assert(u:IsDisarmed() and not u:IsRooted(),label..': rear waiter gained the front native state')
    assert(u.hits==0 and u.force==nil and u:Script_GetAttackRange()==128,
        label..': fifth gained permission to attack')
    assert(u.radius==32 and u.hull_writes==0 and u.corrections==0,
        label..': waiter was shrunk or teleported')
    assert(full_clear(u.p,u.radius),label..': waiter finished inside the bank')
end
local function stable(label)
    local orders,corrections,path_count,query_count=total('orders'),total('corrections'),paths,rear_queries
    local prior_hits=total('hits');run(10);fronts(label)
    assert(total('hits')>prior_hits,label..': front stopped attacking')
    assert(total('orders')==orders,label..': stable rear/front reissued orders')
    assert(total('corrections')==corrections,label..': stable actors kept writing coordinates')
    assert(paths==path_count,label..': stable queue repeated path searches')
    assert(rear_queries==query_count,label..': stable queue repeated rear-body queries')
end

-- Negative control: moving the wall alone in a straight, wide passage does
-- not reproduce this bug. Do not mistake every offset for invalid navigation.
local controls,turns=0,0
for side=1,4 do
    for _,offset in ipairs({-128,-64,0,64,128}) do
        setup(side,offset,'straight')
        local fifth=unit(30,contact_coordinate(400,0));controller(fifth);run(3)
        fifth.p=contact_coordinate(184,-96);fifth.ai:OnIntervalThink();run(4)
        local label='straight face '..side..' offset '..offset
        rear(fifth,label);stable(label);controls=controls+1
    end
end
print('OFFSET_STRAIGHT_CONTROLS_PASS cases='..controls)

-- A full-cell tangent displacement no longer creates a fake fourth
-- contact or a virtual shoulder. Its three-front/real-bypass regression is
-- covered by test_wall_gate_contact_layout.lua, using an independent path graph.
-- A turn after the gate leaves all four original attack contacts legal, but
-- makes every fixed rear endpoint fail full-hull clearance. The center of
-- the intruding body remains native-navigation legal. A full-hull safe short
-- retreat to the actual rear corridor exists and is independently checked.
-- Before the production fix, waiting_point returns false, wait_retreat is
-- false as a consequence, and AI never even tries its retreat alternatives.
for side=1,4 do
    for _,offset in ipairs({-128,-64,0,64,128}) do
        local initial=setup(side,offset,'turn')
        local fifth=unit(30,contact_coordinate(400,-64));controller(fifth);run(3)
        assert(fifth.ai.ai_state=='waiting','fixture failed to establish an ordinary rear waiter')
        fifth.p=contact_coordinate(184,-96)
        local known_safe=contact_coordinate(296,-64)
        assert(GridNav:IsTraversable(fifth.p) and not GridNav:IsBlocked(fifth.p),
            'intruding center is not on legal native terrain')
        assert(contact.can_retreat(target,fifth,known_safe),
            'turn fixture has no independently verified full-hull short retreat')
        for _,along in ipairs({-96,-32,0,32,96}) do
            assert(not full_clear(contact_coordinate(296,along),32),
                'turn fixture accidentally left a fixed rear candidate legal')
        end
        fifth.ai:OnIntervalThink();run(5)
        local label='turn face '..side..' offset '..offset
        rear(fifth,label)
        assert(fifth.retreat_orders>=1 and fifth.retreat_orders<=4,
            label..': safe recovery did not finish with bounded real motion')
        stable(label)
        -- The rear detour is not an extra attack slot. A death grants exactly
        -- one replacement, using the vacated front point rather than a fifth.
        local victim=initial[2];local old_lane=world_lateral(victim.p)-contact_center
        victim.dead=true;victim.ai:OnDeath({unit=victim});run(4)
        local attackers=fronts(label..' death promotion');local promoted=0
        for _,u in ipairs(attackers) do
            if u==fifth then
                promoted=promoted+1
                assert(world_lateral(u.p)-contact_center==old_lane,label..': replacement did not use vacated contact')
            end
        end
        assert(promoted==1 and fifth.hits>0,label..': fifth did not replace exactly one dead contact')
        stable(label..' stable replacement');turns=turns+1
    end
end

-- The native center can be legal while a pushed waiting body's outer hull
-- is already in the bank. A verified exit may leave that existing peripheral
-- overlap; it cannot authorize crossing a newly encountered center obstacle.
for side=1,4 do
    setup(side,64,'turn')
    local fifth=unit(30,contact_coordinate(400,-64));controller(fifth);run(3)
    fifth.p=contact_coordinate(184,120)
    assert(terrain(fifth.p) and not full_clear(fifth.p,32),
        'peripheral-overlap fixture must have a legal center and an invalid hull edge')
    assert(contact.can_retreat(target,fifth,contact_coordinate(296,-72)),
        'pre-existing peripheral overlap has no safe verified exit')
    fifth.ai:OnIntervalThink();run(5)
    rear(fifth,'existing peripheral overlap face '..side)
    stable('stable peripheral-overlap exit face '..side)
end

-- A genuinely closed rear is not permission to phase through terrain.
setup(1,64,'sealed')
local trapped=unit(30,contact_coordinate(184,0));controller(trapped);run(4)
fronts('sealed rear')
assert(trapped.hits==0 and trapped.retreat_orders==0 and not trapped.native_phased,
    'truly blocked rear enabled attack or phased traversal')
assert(normal(trapped.p)==184 and trapped.corrections==0,'blocked waiter was teleported')
setup(1,64,'cliff')
local cliff=unit(30,contact_coordinate(184,0));controller(cliff);run(4)
fronts('cliff rear')
assert(cliff.hits==0 and cliff.retreat_orders==0 and not cliff.native_phased,
    'clear endpoints phased a waiting body across an actual height discontinuity')
assert(normal(cliff.p)<218 and cliff.p.z==384 and cliff.corrections==0,
    'waiting MOVE crossed the actual height discontinuity or teleported')
for _,m in ipairs(controllers) do m:SetWallEntIndex(-1);m:OnDestroy() end
contact.reset()
navigation.clear(target)
for _,o in ipairs(obstacles) do assert(o.deleted,'gate test leaked a navigation obstruction') end
print('WALL_OFFSET_WAITER_PASS straight='..controls..' turns='..turns..' four_faces five_grid_translations native_acceptance32 full_hull turn_exit peripheral_overlap sealed_terrain cliff death_promotion stable_orders=0 stable_paths=0')
