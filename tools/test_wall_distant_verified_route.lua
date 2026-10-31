-- Real contact allocator, rear queue, registry and AI. Native navigation,
-- movement/state propagation and attack delivery are simulated, not certified.
-- The native N1 regression was first observed at distance641: reachable front,
-- no front owners, but the first legal rear endpoint remained beyond512.
package.path='scripts/vscripts/?.lua;'..package.path
local contact_source=arg[1] or 'scripts/vscripts/systems/wall_melee_contact.lua'
local ai_source=arg[2] or 'scripts/vscripts/modifiers/modifier_enemy_wall_ai.lua'
local clock,paths,can_paths,orders,nav_reads,origin_reads=0,0,0,0,0,0
local partial_terrain=false
local entities,actors,controllers={},{},{}
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function copy(p) return Vector(p.x,p.y,p.z) end
local origin=Vector(0,4096,384)
GameRules={GetGameTime=function() return clock end}
GetMapName=function() return 'template_map' end
GetGroundHeight=function() return 384 end
GridNav={IsTraversable=function(_,p)
        nav_reads=nav_reads+1
        return not partial_terrain or p.x>=origin.x-128
            or (p.y-origin.y>=-128 and p.y-origin.y<164)
    end,
    IsBlocked=function(_,p)
        nav_reads=nav_reads+1
        return math.abs(p.x-origin.x)<128 and math.abs(p.y-origin.y)<128
    end,
    CanFindPath=function() can_paths=can_paths+1;return true end,
    FindPathLength=function(_,a,b)
        paths=paths+1
        -- The front has a verified real route, while short rear endpoints on
        -- the stair have no path. A legal rear endpoint exists only beyond512.
        local normal=math.abs(b.x-origin.x)
        if normal>256 and distance(b,origin)<=512 then return -1 end
        return distance(a,b)
    end}
IsServer=function() return true end
class=function(t) return t end
LinkLuaModifier=function() end
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
DOTA_UNIT_CAP_MELEE_ATTACK=1
DOTA_UNIT_ORDER_ATTACK_TARGET,DOTA_UNIT_ORDER_MOVE_TO_POSITION=2,3
MODIFIER_STATE_ROOTED,MODIFIER_STATE_DISARMED,MODIFIER_STATE_NO_UNIT_COLLISION=4,5,6
package.loaded['core/team_alignment']={are_enemies=function() return true end,enforce=function() end}
package.loaded['systems/player_context_service']={is_defeated=function() return false end}
package.loaded['systems/enemy_attack_observer']={is_ready=function() return false end}
package.loaded['systems/wall_navigation_service']={contact_face=function() return 1 end}
package.loaded['systems/wall_melee_contact']=assert(loadfile(contact_source))()
local contact=package.loaded['systems/wall_melee_contact']
local targets=require('systems/wall_target_service')
local AI=assert(loadfile(ai_source))()
EntIndexToHScript=function(id) return entities[id] end
local function unit(id,x,y,wall)
    local u={id=id,p=Vector(origin.x+x,origin.y+y,384),hull=wall and 128 or 32,
        native={},orders=0,hits=0,survival_is_wave_monster=not wall,
        survival_player_id=0,survival_building_id=wall and 'wall' or nil}
    function u:entindex() return self.id end
    function u:IsNull() return false end
    function u:IsAlive() return not self.dead end
    function u:GetAbsOrigin() origin_reads=origin_reads+1;return self.p end
    function u:GetHullRadius() return self.hull end
    function u:GetPaddedCollisionRadius() return self.hull+10 end
    function u:GetTeamNumber() return self.survival_building_id and 2 or 3 end
    function u:HasModifier() return false end
    function u:IsInvulnerable() return false end
    function u:GetAttackCapability() return 1 end
    function u:IsStunned() return false end
    function u:IsCommandRestricted() return false end
    function u:IsRooted() return self.native[4]==true end
    function u:IsDisarmed() return self.native[5]==true end
    function u:GetForceAttackTarget() return self.force end
    function u:SetForceAttackTarget(t) self.force=t end
    function u:Stop() self.order=nil end
    function u:IsIdle() return self.order==nil end
    function u:GetAttacksPerSecond() return 1 end
    function u:Script_GetAttackRange() return 128+(self.ai and self.ai.contact_range_delta or 0) end
    function u:SetIdleAcquire(v) self.idle_acquire=v end
    function u:SetAcquisitionRange(v) self.acquisition=v end
    function u:SetAbsOrigin() error('production must not teleport') end
    function u:SetHullRadius() error('production must not shrink collision') end
    entities[id]=u;actors[#actors+1]=u;return u
end
local wall=unit(101,0,0,true)
targets.register({building_id='wall',entindex=101,player_id=0,unit=wall})
local function state()
    local function up(fn,key)
        for i=1,60 do local name,value=debug.getupvalue(fn,i);if not name then break end
            if name==key then return value end end
    end
    return up(up(contact.resolve,'state_for'),'states')[101]
end
local function count(t) local n=0;for _ in pairs(t or {}) do n=n+1 end;return n end
local function resolve_route(u)
    local index=targets.resolve(u,0,-1,{},true)
    assert(index==101 and u.survival_wall_route,'real registry must verify a front waypoint')
end
ExecuteOrderFromTable=function(order)
    local u=assert(entities[order.UnitIndex]);orders=orders+1;u.orders=u.orders+1
    assert(not u:IsRooted() or order.OrderType~=3,'native MOVE issued under own stale root')
    assert(not u:IsDisarmed() or order.OrderType~=2,'native ATTACK issued under old disarm')
    u.order=order
end
local function controller(u)
    local m=setmetatable({stack=0},{__index=AI});u.ai=m;controllers[#controllers+1]=m
    function m:GetParent() return u end
    function m:GetStackCount() return self.stack end
    function m:SetStackCount(v) self.stack=v end
    function m:ForceRefresh() u.next_native=self:CheckState();self:OnRefresh() end
    function m:StartIntervalThink(interval) self.interval=interval;self.due=clock+(interval==0 and 1/30 or interval) end
    function m:SetHasCustomTransmitterData() end
    function m:SendBuffRefreshToClients() end
    m:OnCreated({wall_entindex=101,wall_target_player_id=0});return m
end
local function frame(move)
    clock=clock+1/30
    for _,u in ipairs(actors) do if u.next_native then u.native=u.next_native;u.next_native=nil end end
    for _,m in ipairs(controllers) do
        if clock+.000001>=m.due then m:OnIntervalThink();m.due=clock+(m.interval==0 and 1/30 or m.interval) end
    end
    if not move then return end
    for _,u in ipairs(actors) do if u.ai and u.order then
        if u.order.OrderType==3 and not u:IsRooted() then
            local goal=u.order.Position;local length=distance(u.p,goal)
            local step=math.min(8,math.max(0,length-32))
            -- Native-motion fixture, not a production placement call. Every
            -- accepted step respects the wall square and every live body.
            local p=Vector(u.p.x+(goal.x-u.p.x)*step/math.max(1,length),
                u.p.y+(goal.y-u.p.y)*step/math.max(1,length),384)
            local clear=math.abs(p.x-origin.x)>=128+u.hull or math.abs(p.y-origin.y)>=128+u.hull
            for _,other in ipairs(actors) do if other~=u and other~=wall and not other.dead
                and distance(p,other.p)<u.hull+other.hull then clear=false end end
            if clear then u.p=p end
        elseif u.order.OrderType==2 and not u:IsDisarmed() and u.idle_acquire
            and distance(u.p,origin)<=u:Script_GetAttackRange() then
            u.hits=u.hits+1;u.ai:HandleAttackStart({attacker=u,target=wall})
        end
    end end
end

-- First arrival must route before taking any contact or rear reservation.
local first=unit(201,-641,0);resolve_route(first)
local initial=assert(contact.resolve(wall,first,1))
assert(initial.routing and not initial.claimed and initial.point==first.survival_wall_route.point,
    '641-distance first arrival must route to verified front, not reserve an unreachable rear hold')
assert(state().count==0 and count(state().rear_queue and state().rear_queue.records)==0,
    'distant route must not preclaim front or allocate a rear queue')
local m=controller(first)
for _=1,3 do frame(false) end
assert(m.ai_state=='route' and first.order.OrderType==3 and not first:IsRooted())
local stable_paths,stable_can,stable_orders,stable_nav=paths,can_paths,orders,nav_reads
local before_origin_reads=origin_reads
for _=1,120 do frame(false) end
local stable_origin_reads=origin_reads-before_origin_reads
assert(paths==stable_paths and can_paths==stable_can and orders==stable_orders and nav_reads==stable_nav,
    'stable distant route must not repeat path/nav/order work')
local count_before=state().count
for _=1,240 do frame(true) end
assert(count_before==0 and state().count==1 and m.ai_state=='attack' and first.hits>0,
    'ordinary motion must enter512, obtain a real contact and issue an attack')
assert(first.hull==32 and not m:CheckState()[MODIFIER_STATE_NO_UNIT_COLLISION])
assert(first.idle_acquire and first.acquisition==0,'native wall attack flag with zero search radius')

-- Existing full-front overflow still belongs to the rear queue. Routing must
-- never fake a fifth claim, erase existing rear ownership or bypass bodies.
contact.reset();controllers={};actors={wall};targets.reset()
targets.register({building_id='wall',entindex=101,player_id=0,unit=wall})
local front={}
for i=1,4 do
    local u=unit(210+i,-300,(i-2.5)*88)
    local plan=assert(contact.resolve(wall,u,1));assert(plan.claimed);u.p=copy(plan.point)
    assert(contact.settle(wall,u,plan.point));front[#front+1]=u
end
assert(state().count==4)
local fifth=unit(220,-641,0);resolve_route(fifth)
assert(contact.resolve(wall,fifth,1).routing and state().count==4,
    'distant fifth keeps native routing without claiming a full face')
fifth.p=Vector(origin.x-400,origin.y,384)
local overflow
for _=1,12 do
    clock=clock+.5
    for _,u in ipairs(front) do assert(contact.resolve(wall,u,1).claimed) end
    overflow=contact.resolve(wall,fifth,1)
end
assert(not overflow.routing and not overflow.claimed and state().count==4,
    'inside admission area a full face must use the real overflow queue')
local record=state().rear_queue and state().rear_queue.records[220]
assert(record and distance(record.point,origin)>512,'fixture must have a real distant rear endpoint')
fifth.p=copy(record.point)
local queue_count=count(state().rear_queue.records)
local retained=contact.resolve(wall,fifth,1)
assert(not retained.routing and not retained.claimed and retained.point==record.point
    and count(state().rear_queue.records)==queue_count and state().count==4,
    'already reserved rear endpoint must remain stable outside512')

-- A reserved rear owner outside512 must see a real vacancy without releasing
-- its place prematurely. Per-call counters exclude existing near-owner work.
local function rear_vacancy_case(deaths,partial)
    partial_terrain=partial;contact.reset();controllers={};actors={wall};targets.reset()
    targets.register({building_id='wall',entindex=101,player_id=0,unit=wall})
    local front={}
    for i=1,(partial and 3 or 4) do
        local u=unit(400+i,-300,partial and 0 or (i-2.5)*88)
        local plan=assert(contact.resolve(wall,u,1));assert(plan.claimed)
        u.p=copy(plan.point);assert(contact.settle(wall,u,plan.point));front[#front+1]=u
    end
    assert(state().faces[1].count==(partial and 3 or 4))
    local rear=unit(420,-400,0);resolve_route(rear)
    for _=1,16 do
        clock=clock+.5
        for _,u in ipairs(front) do assert(contact.resolve(wall,u,1).claimed) end
        assert(not contact.resolve(wall,rear,1).claimed)
    end
    local queue=assert(state().rear_queue)
    local record=assert(queue.records[420]);assert(distance(record.point,origin)>512)
    rear.p=copy(record.point)
    for i=1,deaths do front[i].dead=true;contact.release(101,front[i]:entindex()) end
    local plan=contact.resolve(wall,rear,1)
    assert((plan.routing==true)==(deaths>0) and not plan.claimed,
        'only a true terrain-valid vacant front key wakes a distant rear owner')
    assert(queue.records[420]==record,'route must retain original rear reservation until a real claim')
    local queued,next_order=queue.records,queue.next_order
    local far_nav,far_paths,far_can=0,0,0
    for _=1,120 do
        clock=clock+1/30
        for _,u in ipairs(front) do if not u.dead then assert(contact.resolve(wall,u,1).claimed) end end
        local n,p,c=nav_reads,paths,can_paths
        local again=contact.resolve(wall,rear,1)
        far_nav=far_nav+nav_reads-n;far_paths=far_paths+paths-p;far_can=far_can+can_paths-c
        assert((again.routing==true)==(deaths>0) and not again.claimed)
    end
    assert(far_nav==0 and far_paths==0 and far_can==0 and queue.records==queued
        and queue.records[420]==record and queue.next_order==next_order,
        'stable120 far calls must do no extra nav/path/queue allocation, including full partial3 terrain')
    if deaths>0 then
        local m=controller(rear)
        for _=1,240 do
            for _,u in ipairs(front) do if not u.dead then assert(contact.resolve(wall,u,1).claimed) end end
            frame(true)
        end
        assert(m.ai_state=='attack' and rear.hits>0 and not queue.records[420],
            'native-motion fixture must enter512, receive a real contact, then release old rear reservation')
    else
        assert(state().faces[1].count==3 and not plan.routing,
            'terrain-valid capacity3 is full and must not be treated as a fourth vacancy')
    end
end
rear_vacancy_case(1,false)
rear_vacancy_case(4,false)
rear_vacancy_case(0,true)
partial_terrain=false

contact.reset()
for side=1,4 do for lane=1,4 do
    local along=(lane-2.5)*88
    local u=unit(300+side*10+lane,side<=2 and (side==1 and -300 or 300) or along,
        side<=2 and along or (side==3 and -300 or 300))
    local plan=assert(contact.resolve(wall,u,side));assert(plan.claimed)
    u.p=copy(plan.point);assert(contact.settle(wall,u,plan.point))
end end
assert(state().count==16)
for side=1,4 do
    local u=unit(350+side,side<=2 and (side==1 and -400 or 400) or 0,
        side<=2 and 0 or (side==3 and -400 or 400))
    local plan=assert(contact.resolve(wall,u,side))
    assert(not plan.claimed and not plan.routing and state().faces[side].count==4 and state().count==16,
        'four faces must retain their independent four-owner capacity')
end

-- A stale verified route cannot reuse its old waypoint after relocation.
local fresh=unit(230,-641,0);resolve_route(fresh)
local old=fresh.survival_wall_route.point
wall.survival_wall_relocation_revision=1
local relocated=contact.resolve(wall,fresh,1)
assert(relocated.routing and not relocated.claimed and relocated.point~=old,
    'relocation invalidates the verified waypoint and uses ordinary safe staging')
print(string.format('WALL_DISTANT_VERIFIED_ROUTE_PASS distance641 -> route -> real claim -> attack; four_faces16/rear retained; relocation; stable120frames paths=0 nav=0 orders=0 origin_reads=%d; total paths=%d can_paths=%d',stable_origin_reads,paths,can_paths))
