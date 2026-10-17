-- Offline behavioral regression: native moves stop short and other units really
-- block movement. Unlike the older contact tests, no actor is placed at its
-- assigned contact by the test. This is not a substitute for Workshop physics.
package.path = 'scripts/vscripts/?.lua;' .. package.path

Vector = function(x, y, z) return {x=x, y=y, z=z or 0} end
local clock, paths, nav_queries = 0, 0, 0
local entities, monsters, controllers = {}, {}, {}
local function copy(p) return Vector(p.x, p.y, p.z) end
local function distance(a, b)
    local dx, dy = a.x-b.x, a.y-b.y
    return math.sqrt(dx*dx+dy*dy)
end
GameRules = {GetGameTime=function() return clock end}
GetGroundHeight = function() return 384 end
GridNav = {
    IsTraversable=function(_, p)
        nav_queries = nav_queries+1
        return math.abs(p.y)<128
    end,
    IsBlocked=function(_, p)
        nav_queries = nav_queries+1
        return math.abs(p.x)<128 and math.abs(p.y)<128
    end,
    FindPathLength=function(_, a, b)
        paths = paths+1
        if a.x*b.x<0 then return -1 end
        return distance(a, b)
    end,
}
IsServer=function() return true end
class=function(t) return t end
LinkLuaModifier=function() end
DOTA_UNIT_CAP_MELEE_ATTACK=1
DOTA_TEAM_BADGUYS=3
DOTA_TEAM_GOODGUYS=2
DOTA_UNIT_ORDER_ATTACK_TARGET=2
DOTA_UNIT_ORDER_MOVE_TO_POSITION=3
MODIFIER_STATE_ROOTED=4
MODIFIER_STATE_DISARMED=5
MODIFIER_STATE_NO_UNIT_COLLISION=6
MODIFIER_ATTRIBUTE_PERMANENT=7
package.loaded['core/team_alignment']={
    are_enemies=function() return true end,
    enforce=function() error('unexpected team correction') end,
}
EntIndexToHScript=function(index) return entities[index] end
ExecuteOrderFromTable=function(order)
    local u=assert(entities[order.UnitIndex])
    u.orders=u.orders+1
    if order.OrderType==DOTA_UNIT_ORDER_MOVE_TO_POSITION and u.ai:GetStackCount()==5 then
        assert(not u.native_phased,'distant route must retain native unit collision')
        u.route_move_orders=u.route_move_orders+1
    end
    if order.OrderType==DOTA_UNIT_ORDER_MOVE_TO_POSITION and u.ai:GetStackCount()==3 then
        assert(u.native_phased,'approach MOVE was issued before native phase became active')
        u.contact_move_orders=u.contact_move_orders+1
        if u.cancel_first_contact_move and not u.cancelled_contact_move then
            -- A native MOVE can be accepted by the Lua API but immediately
            -- disappear while the new collision state is being applied.
            u.cancelled_contact_move=true
            u.cancelled_point=order.Position
            u.cancelled_time=clock
            u.cancelled_stops=u.stops
            u.order=nil
            return
        end
        if u.cancelled_contact_move and not u.recovered_contact_move then
            assert(order.Position==u.cancelled_point,'early recovery replaced its contact reservation')
            assert(clock-u.cancelled_time<=.51,'idle recovery did not run on the next observation')
            assert(u.stops==u.cancelled_stops,'move recovery unnecessarily stopped the unit')
            u.recovered_contact_move=true
        end
    end
    u.order={OrderType=order.OrderType,TargetIndex=order.TargetIndex,
        Position=order.Position and copy(order.Position)}
end

local function unit(id, x, y, radius)
    local u={p=Vector(x,y,384),radius=radius or 32,orders=0,stops=0,
        original_radius=radius or 32,hull_changes=0,
        corrections=0,hits=0,next_attack=0,contact_move_orders=0,route_move_orders=0}
    function u:entindex() return id end
    function u:GetAbsOrigin() return self.p end
    function u:SetAbsOrigin(p) self.p=copy(p);self.corrections=self.corrections+1 end
    function u:IsNull() return false end
    function u:IsAlive() return not self.dead end
    function u:GetHullRadius() return self.radius end
    function u:SetHullRadius(radius) self.radius=radius;self.hull_changes=self.hull_changes+1 end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:GetTeamNumber() return 3 end
    function u:GetAttackCapability() return DOTA_UNIT_CAP_MELEE_ATTACK end
    function u:GetForceAttackTarget() if not self.hide_force_target then return self.force end end
    function u:SetForceAttackTarget(target) self.force=target end
    function u:Script_GetAttackRange() return 128+(self.ai and self.ai.contact_range_delta or 0) end
    function u:GetAttacksPerSecond() return 1 end
    function u:IsStunned() return self.stunned==true end
    function u:IsCommandRestricted() return self.restricted==true end
    function u:IsRooted()
        return self.rooted==true or (self.ai and self.ai:CheckState()[MODIFIER_STATE_ROOTED])
    end
    function u:IsDisarmed()
        return self.disarmed==true or (self.ai and self.ai:CheckState()[MODIFIER_STATE_DISARMED])
    end
    function u:IsIdle() return not self.order end
    function u:Stop() self.stops=self.stops+1;self.order=nil end
    entities[id]=u
    return u
end

local contact=require('systems/wall_melee_contact')
-- This fixture is a sealed narrow west approach; navigation registration is
-- covered separately. Supply the same proven gate direction to the real AI.
package.loaded['systems/wall_navigation_service']={contact_face=function() return 1 end}
local ai=require('modifiers/modifier_enemy_wall_ai')
local wall=unit(1,0,0,128)
local function controller(u, target)
    local m=setmetatable({stack=0}, {__index=ai})
    function m:GetParent() return u end
    function m:GetStackCount() return self.stack end
    function m:SetStackCount(v) self.stack=v end
    function m:StartIntervalThink(interval)
        self.interval=interval
        self.next_think=clock+(interval==0 and .05 or interval)
    end
    function m:ForceRefresh()
        local target,state,first=self.wall_entindex,self.ai_state,self.first_observation
        if self.OnRefresh then self:OnRefresh({}) end
        assert(self.wall_entindex==target and self.ai_state==state and self.first_observation==first,
            'modifier state refresh reinitialized the AI or lost its target')
        u.phase_refresh_pending=true
    end
    function m:SetHasCustomTransmitterData() end
    function m:SendBuffRefreshToClients() end
    u.ai=m
    monsters[#monsters+1]=u
    controllers[#controllers+1]=m
    m:OnCreated({wall_entindex=(target or wall):entindex()})
    return m
end
local function phased(u)
    return u.native_phased==true
end
local function move(u, goal, dt)
    if u:IsRooted() or u:IsStunned() or u:IsCommandRestricted() then return end
    local remaining=distance(u.p,goal)
    -- Model MOVE_TO_POSITION's acceptance radius instead of teleporting to a
    -- perfect result. The regression used to leave the outside lanes blocked.
    if remaining<=32 then return end
    local step=math.min(240*dt,remaining-32)
    local next_p=Vector(u.p.x+(goal.x-u.p.x)*step/remaining,
        u.p.y+(goal.y-u.p.y)*step/remaining,384)
    if math.abs(next_p.y)>128-u.radius or next_p.x>-128-u.radius then return end
    if not phased(u) then
        for _,other in ipairs(monsters) do
            if other~=u and other:IsAlive() and not phased(other) then
                local separation=distance(next_p,other.p)
                local body=u:GetPaddedCollisionRadius()+other:GetPaddedCollisionRadius()
                -- Old spawn rows may already overlap native padded bodies.
                -- They may move out of that overlap, never deeper into it.
                if separation<body-.01 and separation<distance(u.p,other.p)-.01 then return end
            end
        end
    end
    u.p=next_p
end
local function frame(dt)
    clock=math.floor((clock+dt)*1000+.5)/1000
    -- Engine modifier states become visible on the next server frame. Think
    -- interval zero also runs on that frame, after the new phase state exists.
    for _,u in ipairs(monsters) do
        if u.phase_refresh_pending then
            u.native_phased=u.ai:CheckState()[MODIFIER_STATE_NO_UNIT_COLLISION]==true
            u.phase_refresh_pending=false
        end
    end
    for _,m in ipairs(controllers) do
        if m:GetParent():IsAlive() and m.next_think and clock+.0001>=m.next_think then
            m.next_think=clock+(m.interval==0 and .05 or m.interval)
            m:OnIntervalThink()
        end
    end
    for _,u in ipairs(monsters) do
        if u:IsAlive() and u.order then
            if u.order.OrderType==DOTA_UNIT_ORDER_MOVE_TO_POSITION then
                move(u,u.order.Position,dt)
            else
                local target=entities[u.order.TargetIndex]
                if target and target:IsAlive() then
                    if distance(u.p,target.p)>u:Script_GetAttackRange()+.01 then
                        move(u,target.p,dt)
                    elseif not u:IsStunned() and not u:IsCommandRestricted()
                        and not u:IsDisarmed() and clock>=u.next_attack then
                        assert(u.ai.ai_state=='attack','a rear/chasing monster attacked through the front')
                        u.hits=u.hits+1
                        u.next_attack=clock+1
                        u.ai:OnAttackStart({attacker=u,target=target})
                    end
                end
            end
        end
    end
end
local function observe()
    for _,m in ipairs(controllers) do if m:GetParent():IsAlive() then m:OnIntervalThink() end end
end
local function run(seconds)
    local frames=math.floor(seconds/.05+.5)
    for i=1,frames do
        frame(.05)
    end
end
local function front()
    local result={}
    for _,u in ipairs(monsters) do
        if u:IsAlive() and u.ai.ai_state=='attack' then result[#result+1]=u end
    end
    return result
end
local function total(field)
    local result=0
    for _,u in ipairs(monsters) do result=result+u[field] end
    return result
end
local function assert_front(label)
    local actors=front()
    assert(#actors==4,label..': expected four attacking contacts, got '..#actors)
    local occupied={}
    for _,u in ipairs(actors) do
        assert(u.hits>0,label..': every contact must actually land attacks')
        assert(math.abs(u.p.x+184)<.01,label..': contact is not precisely aligned normal to wall')
        assert(u.p.y==-96 or u.p.y==-32 or u.p.y==32 or u.p.y==96,
            label..': contact is not precisely aligned to a lane')
        assert(u:GetHullRadius()==20 and u:GetPaddedCollisionRadius()==30,
            label..': front must include the native +10 padding in the 64-unit pitch')
        assert(math.abs(u.p.y)+u:GetPaddedCollisionRadius()<=128,
            label..': native padded front must fit the doorway')
        assert(not occupied[u.p.y],label..': two contacts occupy the same lane')
        occupied[u.p.y]=true
        assert(not phased(u) and u:IsRooted(),label..': locked attackers must retain collision')
    end
    local phase_count=0
    for _,u in ipairs(monsters) do
        if u:IsAlive() and phased(u) then phase_count=phase_count+1 end
        if u.ai.ai_state=='waiting' then
            assert(u.ai:CheckState()[MODIFIER_STATE_DISARMED],label..': overflow is not disarmed')
            assert(not phased(u),label..': overflow must retain normal collision')
            assert(u:GetHullRadius()==u.original_radius,label..': overflow inherited the tactical hull')
            local goal_gap=-u.ai.contact_move.x-184
            local minimum_gap=u:GetPaddedCollisionRadius()+30+8
            if distance(u.p,wall.p)>512 then
                assert(goal_gap==320-184 and u.ai.wait_envelope==0,
                    label..': distant solid staging must target the near-face entrance without claiming a contact')
            else
                assert(goal_gap>=minimum_gap and goal_gap<=minimum_gap+32,
                    label..': overflow goal must be compact and outside padded front hulls goal='..goal_gap..' minimum='..minimum_gap)
            end
            for _,attacker in ipairs(actors) do
                assert(distance(u.p,attacker.p)>=u:GetPaddedCollisionRadius()+attacker:GetPaddedCollisionRadius()-.01,
                    label..': waiting unit overlaps a solid front attacker')
            end
        end
    end
    assert(phase_count<=4,label..': phase work must be bounded by four claims')
    for i=1,#actors do for j=i+1,#actors do
        assert(distance(actors[i].p,actors[j].p)>=actors[i]:GetPaddedCollisionRadius()+actors[j]:GetPaddedCollisionRadius()+4,
            label..': native padded front bodies must leave an avoidance margin')
    end end
    return actors
end

-- Two middle monsters arrive before the rest, displaced eighteen units outward.
-- The old +/-20 arrival tolerance roots them in those positions; 30-unit gaps
-- prevent the outer tactical contacts from fitting. Populate a genuine 90-unit
-- crowd behind them, with the center columns processed before the outer ones.
controller(unit(10,-224,-42))
controller(unit(11,-224,42))
for i=1,88 do
    local row=math.floor((i-1)/4)
    local lanes={-32,32,-96,96}
    local u=unit(11+i,-320-row*64,lanes[(i-1)%4+1])
    u.cancel_first_contact_move=true
    controller(u)
end
observe()
for _,u in ipairs(monsters) do
    if u.ai.ai_state=='approach' then
        assert(u.contact_move_orders==0 and not phased(u),'phase transition must defer the first native MOVE')
    end
end
run(.6)
local recovered=0
for _,u in ipairs(monsters) do
    if u.cancelled_contact_move then
        assert(u.recovered_contact_move and u.contact_move_orders==2,
            'one silently cancelled approach must receive exactly one early retry')
        assert(u.ai.contact_move==u.cancelled_point and contact.resolve(wall,u).point==u.cancelled_point,
            'early recovery must keep the same live contact')
        recovered=recovered+1
    end
end
assert(recovered==2,'the two outside contacts must exercise native move cancellation')
run(1.9)
local initial_front=assert_front('initial 90-monster crowd')
for _,u in ipairs(initial_front) do
    if u.cancelled_contact_move then
        assert(u.contact_move_orders==2,'recovered native movement kept reissuing orders')
    end
end
run(5.5)
local closest_waiter=math.huge
for _,u in ipairs(monsters) do
    if u.ai.ai_state=='waiting' then closest_waiter=math.min(closest_waiter,-u.p.x-184) end
end
assert(closest_waiter>=30+42 and closest_waiter<=30+42+8+32,
    'MOVE stopping tolerance still leaves an empty row behind the four attackers distance='..closest_waiter)
local first_attackers={}
for _,u in ipairs(initial_front) do first_attackers[u:entindex()]=true end
for _,u in ipairs(monsters) do
    assert(u.hits==0 or first_attackers[u:entindex()],'an overflow monster attacked the wall')
end

-- Settled combat must not produce orders, position writes, or further path
-- searches. Navigation checks may refresh only on the existing cached cadence.
local orders_before,positions_before,paths_before=total('orders'),total('corrections'),paths
local hull_changes_before=total('hull_changes')
local nav_before=nav_queries
run(10)
assert_front('stable crowd')
assert(total('orders')==orders_before,'stable crowd reissued native orders')
assert(total('corrections')==positions_before,'stable front writes its position every observation')
assert(total('hull_changes')==hull_changes_before,'stable contacts rewrite native hulls every observation')
assert(paths==paths_before,'stable full front repeated path queries')
local stable_nav=nav_queries-nav_before
assert(stable_nav<1500,'navigation work scales with all waiting monsters rather than cached wall geometry')

-- A long stun preserves a front claim without teleporting or restarting the
-- attack order. An external knockback must leave the attack state and return
-- by native movement before a new short, safe alignment.
local controlled=initial_front[1]
controlled.stunned=true
local before_orders,before_positions=controlled.orders,controlled.corrections
run(4)
assert(controlled.ai.ai_state=='attack','a stun should not discard its front claim')
assert(controlled.orders==before_orders and controlled.corrections==before_positions,
    'control caused repeated attack orders or position writes')
controlled.stunned=false
run(1)
controlled.p=Vector(controlled.p.x-120,controlled.p.y,384)
local displaced=copy(controlled.p)
observe()
assert(controlled.ai.ai_state=='approach','external displacement must release rooted attack state')
assert(distance(controlled.p,displaced)<.01,'a distant knockback was teleported straight into contact')
run(4)
assert_front('return after external displacement')

-- Death must make exactly one new attacker eligible without allowing the
-- whole horde through. The native collision wall of waiters cannot trap its
-- replacement because only that claimant is allowed to pass through units.
local victim=front()[2]
victim.dead=true
victim.ai:OnDeath({unit=victim})
assert(victim:GetHullRadius()==victim.original_radius,'death must restore the previous front owner immediately')
run(5)
local replaced=assert_front('death replacement')
local new_attackers=0
for _,u in ipairs(replaced) do if not first_attackers[u:entindex()] then new_attackers=new_attackers+1 end end
assert(new_attackers==1,'death did not promote exactly one replacement attacker')

-- Changing target releases all temporary collision/root/disarm/range state
-- immediately. Repeated no-target notifications are idempotent.
local next_wall=unit(2,1024,0,128)
for _,m in ipairs(controllers) do
    m:SetWallEntIndex(next_wall:entindex())
    local u=m:GetParent()
    assert(u:GetHullRadius()==u.original_radius,'target change retained the tactical collision hull')
    assert(not m:CheckState()[MODIFIER_STATE_NO_UNIT_COLLISION] and not u:IsRooted() and not u:IsDisarmed(),
        'target change retained temporary contact state')
    assert(u:Script_GetAttackRange()==128 and u.force==nil,'target change retained range or force attack target')
    m:SetWallEntIndex(-1)
    local stops=u.stops
    m:SetWallEntIndex(-1)
    assert(u.stops==stops,'repeated release stopped the unit again')
    m:OnDestroy()
end
contact.reset()

-- Ordinary movement progresses during its first observation and must not get
-- the new idle retry. A nil force-target getter also cannot suppress clearing
-- the previously assigned force target before issuing this genuine MOVE.
-- This is an independent single-unit case. Destroyed controllers from the
-- previous 90-body crowd must not remain as live blocking fixture entities.
monsters,controllers={},{}
local progressing=unit(250,-480,-96)
progressing.force=wall
progressing.hide_force_target=true
local progressing_ai=controller(progressing)
observe()
assert(progressing.contact_move_orders==0 and not phased(progressing),
    'vacancy entry must still defer MOVE until the native phase frame')
assert(progressing_ai.ai_state=='approach' and progressing.route_move_orders==0,
    'a vacancy owner already outside its own face must enter within the allocator local range')
run(.05)
assert(progressing.force==nil,'a nil getter incorrectly suppressed clearing the old force target')
assert(progressing.route_move_orders==0 and progressing.contact_move_orders==1
    and progressing_ai.ai_state=='approach' and phased(progressing))
run(.25)
assert(progressing.p.x>-480 and progressing_ai.ai_state=='approach' and phased(progressing),
    'own-face vacancy entry must advance without the arbitrary 256-unit dead zone')
assert(progressing.contact_move_orders==1 and progressing.route_move_orders==0,
    'progressing own-face entry received an unnecessary retry or corner stage')
run(.4)
assert(progressing_ai.ai_state=='approach' and phased(progressing)
    and progressing.route_move_orders==0 and progressing.contact_move_orders==1,
    'own-face progress must keep one live contact and one native MOVE')
run(1.85)
assert(progressing_ai.ai_state=='attack' and progressing.hits>0 and not phased(progressing)
    and progressing.route_move_orders+progressing.contact_move_orders<=2,
    'normal own-face entry must restore solid attack using at most two MOVE orders')
local solo_orders,solo_positions,solo_paths=progressing.orders,progressing.corrections,paths
local solo_hits=progressing.hits
run(2)
assert(progressing.hits>solo_hits and progressing.orders==solo_orders
    and progressing.corrections==solo_positions and paths==solo_paths,
    'settled own-face entry must attack without repeated orders, coordinates or paths')
progressing_ai:SetWallEntIndex(-1)
progressing_ai:OnDestroy()
contact.reset()

-- Controls already present during admission must postpone the one-time
-- alignment; only releasing that control allows movement/attack to resume.
for i,control in ipairs({'stunned','restricted','rooted'}) do
    local u=unit(300+i,-224,32)
    u[control]=true
    local m=controller(u)
    observe()
    run(3)
    assert(u.corrections==0 and u.hits==0 and m.ai_state=='approach',
        control..' during admission must prevent alignment and attacking')
    u[control]=false
    run(2)
    assert(m.ai_state=='attack' and u.hits>0 and distance(u.p,m.contact_move)<.01,
        control..' release must resume the retained contact')
    m:SetWallEntIndex(-1)
    m:OnDestroy()
    contact.reset()
end

-- Large original hulls must fill all four tactical contacts. Their rear units
-- retain real collision and full fronts must still reuse cached navigation.
local large={}
for i=1,8 do
    local lateral={-64,-21,21,64}
    local u=unit(400+i,-400-math.floor((i-1)/4)*128,lateral[(i-1)%4+1],64)
    controller(u)
    large[#large+1]=u
end
observe()
run(8)
assert_front('large-body four-contact crowd')
local large_paths,large_nav=paths,nav_queries
run(4)
assert(paths==large_paths,'large full front repeatedly searched paths for its extra waiters')
assert(nav_queries-large_nav<300,'large full front repeatedly sampled navigation for each waiter')
for _,u in ipairs(large) do
    u.ai:SetWallEntIndex(-1);u.ai:OnDestroy()
    assert(u:GetHullRadius()==64,'large contact cleanup failed to restore the original Hull64')
end
contact.reset()

-- No reachable contact near the wall must remain disarmed. Falling back to
-- normal ATTACK_TARGET would bypass admission and reintroduce front crowding.
local traversable=GridNav.IsTraversable
GridNav.IsTraversable=function(self,p)
    if p.x>-240 then nav_queries=nav_queries+1;return false end
    return traversable(self,p)
end
local obstructed=unit(500,-300,0)
local blocked_ai=controller(obstructed)
observe()
assert(blocked_ai.ai_state=='waiting' and obstructed:IsDisarmed(),
    'no contact candidates must not fall back to unconstrained chase/attack')
run(2)
assert(obstructed.hits==0 and not phased(obstructed) and obstructed:GetHullRadius()==32,
    'blocked admission granted collision/attack privileges')
GridNav.IsTraversable=traversable
run(4)
assert(blocked_ai.ai_state=='attack' and obstructed.hits>0,'removed obstruction did not restore admission')
blocked_ai:SetWallEntIndex(-1)
blocked_ai:OnDestroy()
contact.reset()

-- Static unreachable paths are backed off per unit. Even when candidate
-- navigation samples are clear, a closed route must not search every think.
local find_path=GridNav.FindPathLength
GridNav.FindPathLength=function() paths=paths+1;return -1 end
local trapped=unit(501,-400,0)
local trapped_ai=controller(trapped)
observe()
local failed_paths=paths
for i=1,3 do clock=clock+.5;observe() end
assert(paths==failed_paths,'stationary failed paths were queried again before the backoff elapsed')
assert(trapped_ai.ai_state=='waiting' and trapped:IsDisarmed() and trapped:GetHullRadius()==32,
    'unreachable paths bypassed admission or retained the tactical hull')
GridNav.FindPathLength=find_path
run(3)
assert(trapped_ai.ai_state=='attack' and trapped.hits>0,'failed path cache never recovered')
trapped_ai:SetWallEntIndex(-1)
trapped_ai:OnDestroy()
contact.reset()
print(string.format('WALL_CONTACT_CROWD_PASS units=90 four_attackers_by=2.5s cancelled_moves=2 one_retry_same_claim nearest_waiter_distance=%.2f stable_orders=0 stable_position_writes=0 stable_paths=0 stable_nav=%d total_paths=%d total_nav=%d',
    closest_waiter,stable_nav,paths,nav_queries))
