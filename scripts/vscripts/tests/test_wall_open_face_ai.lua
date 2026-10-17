-- Real AI and allocator. Native MOVE follows an outside-corner path, accepts
-- its final goal 32 units early, and observes square and Hull+10 padded-body
-- collision measured in the engine. No raw-hull overlap oracle is used.
-- This checks the state/movement integration offline, not engine rendering.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
class=function(t) return t end
LinkLuaModifier=function() end
IsServer=function() return true end
DOTA_UNIT_CAP_MELEE_ATTACK=1
DOTA_TEAM_BADGUYS=3
DOTA_TEAM_GOODGUYS=2
DOTA_UNIT_ORDER_ATTACK_TARGET=2
DOTA_UNIT_ORDER_MOVE_TO_POSITION=3
MODIFIER_STATE_ROOTED=4
MODIFIER_STATE_DISARMED=5
MODIFIER_STATE_NO_UNIT_COLLISION=6
MODIFIER_ATTRIBUTE_PERMANENT=7
DOTA_UNIT_TARGET_TEAM_BOTH=1
DOTA_UNIT_TARGET_BASIC=2
DOTA_UNIT_TARGET_HERO=4
FIND_ANY_ORDER=0
package.loaded['core/team_alignment']={are_enemies=function() return true end,
    enforce=function() error('unexpected team correction') end}
local clock,paths,corner_moves,body_queries,avoidance_steps=0,0,0,0,0
local entities,monsters,controllers={},{},{}
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
local function copy(p) return Vector(p.x,p.y,p.z) end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function crosses(a,b)
    -- The largest original Hull32 body has the engine-measured +10 padding.
    local low,high,half=0,1,170
    for _,axis in ipairs({'x','y'}) do
        local start,delta=a[axis],b[axis]-a[axis]
        if math.abs(delta)<.000001 then
            if start<=-half or start>=half then return false end
        else
            local enter,leave=(-half-start)/delta,(half-start)/delta
            if enter>leave then enter,leave=leave,enter end
            low,high=math.max(low,enter),math.min(high,leave)
            if high-low<.000001 then return false end
        end
    end
    return high-low>.000001
end
local function route(a,b)
    local nodes={copy(a),copy(b)}
    for _,x in ipairs({-170,170}) do for _,y in ipairs({-170,170}) do
        nodes[#nodes+1]=Vector(x,y)
    end end
    local lengths,visited,previous={[1]=0},{},{}
    for _=1,#nodes do
        local current,best
        for index=1,#nodes do
            if not visited[index] and lengths[index]
                and (not best or lengths[index]<best) then current,best=index,lengths[index] end
        end
        if not current then return nil,-1 end
        if current==2 then
            local result,index={},2
            while index~=1 do
                table.insert(result,1,nodes[index]);index=assert(previous[index])
            end
            return result,best
        end
        visited[current]=true
        for index=1,#nodes do
            if not visited[index] and not crosses(nodes[current],nodes[index]) then
                local candidate=best+distance(nodes[current],nodes[index])
                if not lengths[index] or candidate<lengths[index] then
                    lengths[index],previous[index]=candidate,current
                end
            end
        end
    end
    return nil,-1
end
local path_bursts={}
GridNav={IsTraversable=function() return true end,
    IsBlocked=function(_,p) return math.abs(p.x)<128 and math.abs(p.y)<128 end,
    FindPathLength=function(_,a,b)
        paths=paths+1
        path_bursts[clock]=(path_bursts[clock] or 0)+1
        assert(path_bursts[clock]<=16,'one AI observation burst exceeded the shared path budget')
        local _,length=route(a,b)
        return length
    end}
FindUnitsInRadius=function(_,p,_,radius)
    body_queries=body_queries+1
    local result={}
    for _,u in ipairs(monsters) do
        if u:IsAlive() and distance(u.p,p)<=radius then result[#result+1]=u end
    end
    return result
end
EntIndexToHScript=function(index) return entities[index] end
ExecuteOrderFromTable=function(order)
    local u=assert(entities[order.UnitIndex])
    u.orders=u.orders+1
    if order.OrderType==DOTA_UNIT_ORDER_MOVE_TO_POSITION then
        if u.ai.contact_mode==3 or u.ai.contact_mode==4 then
            assert(u.native_phased,'contact MOVE issued before native phase became active')
        end
        local points=assert(route(u.p,order.Position),'native MOVE goal has no route around the wall')
        if #points>1 then corner_moves=corner_moves+1 end
        u.order={kind=order.OrderType,goal=copy(order.Position),points=points,index=1}
    else
        u.order={kind=order.OrderType,target=assert(entities[order.TargetIndex])}
    end
end
local function entity(id,p,radius)
    local u={p=copy(p),radius=radius,survival_monster_hull_radius=radius,
        orders=0,stops=0,corrections=0,hits=0,next_attack=0}
    function u:entindex() return id end
    function u:GetAbsOrigin() return self.p end
    function u:SetAbsOrigin(p)
        assert(distance(self.p,p)<=64.001,'contact alignment teleported a remote actor to its slot')
        self.p=copy(p);self.corrections=self.corrections+1
    end
    function u:IsNull() return false end
    function u:IsAlive() return not self.dead end
    function u:GetHullRadius() return self.radius end
    function u:SetHullRadius(value) self.radius=value end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:GetTeamNumber() return 3 end
    function u:GetAttackCapability() return DOTA_UNIT_CAP_MELEE_ATTACK end
    function u:GetForceAttackTarget() return self.force end
    function u:SetForceAttackTarget(target) self.force=target end
    function u:Script_GetAttackRange() return 128+(self.ai and self.ai.contact_range_delta or 0) end
    function u:GetAttacksPerSecond() return 1 end
    function u:IsStunned() return false end
    function u:IsCommandRestricted() return false end
    function u:IsRooted() return self.native_rooted or false end
    function u:IsDisarmed() return self.native_disarmed or false end
    function u:IsIdle() return not self.order or self.order.idle==true end
    function u:Stop() self.stops=self.stops+1;self.order=nil end
    function u:FindModifierByName(name) if name=='modifier_enemy_wall_ai' then return self.ai end end
    entities[id]=u
    return u
end
local contact=require('systems/wall_melee_contact')
local ai=require('modifiers/modifier_enemy_wall_ai')
local wall=entity(1,Vector(0,0),128)
local function controller(u)
    local m=setmetatable({stack=0},{__index=ai})
    function m:GetParent() return u end
    function m:GetStackCount() return self.stack end
    function m:SetStackCount(value) self.stack=value end
    function m:StartIntervalThink(interval)
        self.interval=interval;self.next_think=clock+(interval==0 and .05 or interval)
    end
    function m:ForceRefresh()
        local target,state=self.wall_entindex,self.ai_state
        self:OnRefresh({})
        assert(self.wall_entindex==target and self.ai_state==state,'state refresh restarted the AI')
        u.state_pending=true
    end
    function m:SetHasCustomTransmitterData() end
    function m:SendBuffRefreshToClients() end
    u.ai=m;monsters[#monsters+1]=u;controllers[#controllers+1]=m
    m:OnCreated({wall_entindex=wall:entindex()})
end
for index=1,17 do
    local row=math.floor((index-1)/4)
    -- Initial native spawn clearance must separate padded Hull32 bodies too;
    -- a 64-unit spawn grid would already overlap before our first AI tick.
    local lateral=({-126,-42,42,126})[(index-1)%4+1]
    local p=index==17 and Vector(-400,252) or Vector(-224-row*84,lateral)
    controller(entity(100+index,p,32))
end
local function wall_clear(u,next_p)
    local x=next_p.x-math.max(-128,math.min(128,next_p.x))
    local y=next_p.y-math.max(-128,math.min(128,next_p.y))
    return x*x+y*y>=u:GetPaddedCollisionRadius()^2-.01
end
local function can_move(u,next_p,alternative)
    if alternative and math.abs(next_p.x)<170 and math.abs(next_p.y)<170 then return false end
    if not wall_clear(u,next_p) then
        assert(alternative,'native movement cut through the square wall')
        return false
    end
    if not u.native_phased then
        for _,other in ipairs(monsters) do
            if other~=u and other:IsAlive() and not other.native_phased
                and distance(next_p,other.p)<u:GetPaddedCollisionRadius()+other:GetPaddedCollisionRadius()-.01 then return false,other end
        end
    end
    return true
end
-- Source 2 MOVE has dynamic-body avoidance; a straight segment integrator
-- cannot model a solid actor travelling past a stationary front row. Only a
-- genuinely body-blocked step may steer locally. Every alternative is at most
-- one speed-budget step and checks the complete segment against wall/body
-- collision; this grants neither phasing, slot alignment nor an extra order.
local function avoid_body(u,goal,step,blocker)
    local dx,dy=goal.x-u.p.x,goal.y-u.p.y
    local length=math.sqrt(dx*dx+dy*dy)
    dx,dy=dx/length,dy/length
    if not u.avoid_sign then
        local cross=dx*(blocker.p.y-u.p.y)-dy*(blocker.p.x-u.p.x)
        u.avoid_sign=cross>0 and -1 or (cross<0 and 1 or (u:entindex()%2==0 and 1 or -1))
    end
    -- Keep one side until it is actually blocked; switching side for a
    -- smaller steering angle each frame produces an artificial oscillation.
    for _,sign in ipairs({u.avoid_sign,-u.avoid_sign}) do
        for _,degrees in ipairs({30,60,90,120,150}) do
            local angle=degrees*math.pi/180*sign
            local vx,vy=dx*math.cos(angle)-dy*math.sin(angle),dx*math.sin(angle)+dy*math.cos(angle)
            local safe=true
            for sample=1,math.max(1,math.ceil(step/4)) do
                local part=step*sample/math.max(1,math.ceil(step/4))
                if not can_move(u,Vector(u.p.x+vx*part,u.p.y+vy*part),true) then safe=false;break end
            end
            if safe then
                u.avoid_sign=sign
                avoidance_steps=avoidance_steps+1
                return Vector(u.p.x+vx*step,u.p.y+vy*step)
            end
        end
    end
end
local function move(u,dt)
    if u:IsRooted() then return end
    local order,budget=u.order,240*dt
    while budget>.0001 and order.index<=#order.points do
        local goal=order.points[order.index]
        local remaining=distance(u.p,goal)
        local acceptance=order.index==#order.points and 32 or 0
        if remaining<=acceptance+.0001 then
            if acceptance>0 then order.idle=true;return end
            order.index=order.index+1
        else
            local step=math.min(budget,remaining-acceptance)
            local next_p=Vector(u.p.x+(goal.x-u.p.x)*step/remaining,
                u.p.y+(goal.y-u.p.y)*step/remaining)
            local clear,blocker=can_move(u,next_p)
            if not clear then
                next_p=blocker and avoid_body(u,goal,step,blocker)
                if not next_p then return end
            else u.avoid_sign=nil end
            u.p=next_p;budget=budget-step
        end
    end
end
local function frame()
    clock=math.floor((clock+.05)*1000+.5)/1000
    for _,u in ipairs(monsters) do
        if u.state_pending then
            local state=u.ai:CheckState()
            u.native_phased=state[MODIFIER_STATE_NO_UNIT_COLLISION]==true
            u.native_rooted=state[MODIFIER_STATE_ROOTED]==true
            u.native_disarmed=state[MODIFIER_STATE_DISARMED]==true
            u.state_pending=false
        end
    end
    for _,m in ipairs(controllers) do
        if clock+.0001>=m.next_think then
            m.next_think=clock+(m.interval==0 and .05 or m.interval)
            m:OnIntervalThink()
        end
    end
    for _,u in ipairs(monsters) do
        if u.order and u.order.kind==DOTA_UNIT_ORDER_MOVE_TO_POSITION then move(u,.05)
        elseif u.order and not u:IsDisarmed() and clock>=u.next_attack then
            assert(u.ai.ai_state=='attack','unclaimed overflow attacked through the front')
            assert(distance(u.p,wall.p)<=u:Script_GetAttackRange(),'attack slot lacks native center reach')
            u.hits=u.hits+1;u.next_attack=clock+1
            u.ai:OnAttackStart({attacker=u,target=wall})
        end
    end
end
local function run(seconds) for _=1,math.floor(seconds/.05+.5) do frame() end end
local function total(field)
    local count=0
    for _,u in ipairs(monsters) do count=count+u[field] end
    return count
end
run(14)
local sides,lanes={0,0,0,0},{{},{},{},{}}
local attacking,waiting=0,0
for _,u in ipairs(monsters) do
    if u.ai.ai_state=='attack' then
        attacking=attacking+1
        local x,y=u.p.x,u.p.y
        local side=math.abs(x)>=math.abs(y) and (x<0 and 1 or 2) or (y<0 and 3 or 4)
        sides[side]=sides[side]+1
        lanes[side][#lanes[side]+1]=side<=2 and y or x
        assert(u.hits>0 and u.native_rooted and not u.native_phased and u.radius==20
            and u:GetPaddedCollisionRadius()==30,
            'settled attacker must hit and regain physical collision with its bounded hull')
    else
        waiting=waiting+1
        assert(u.ai.ai_state=='waiting' and u.hits==0 and not u.native_phased and u.radius==32,
            'overflow must wait with its original physical collision hull')
    end
end
assert(attacking==16 and waiting==1,'one entrance did not form sixteen actual attackers and one waiter')
for side=1,4 do
    assert(sides[side]==4,'reachable wall face has fewer than four actual attackers')
    table.sort(lanes[side])
    for column=2,4 do
        assert(math.abs(lanes[side][column]-lanes[side][column-1]-64)<.001,
            'native padded four-column contacts did not preserve 64-unit lane pitch')
    end
end
for index,u in ipairs(monsters) do
    for other=index+1,#monsters do
        assert(distance(u.p,monsters[other].p)>=u:GetPaddedCollisionRadius()+monsters[other]:GetPaddedCollisionRadius()-.01,
            'settled solid actors still overlap padded native collision bodies')
    end
end
assert(corner_moves>0,'opposite-side owners never followed native outer-corner paths')
assert(body_queries>0,'settling bypassed local solid-body clearance checks')
local stable_orders,stable_paths,stable_positions=total('orders'),paths,total('corrections')
local stable_stops=total('stops')
local before_hits=total('hits')
run(10)
assert(total('orders')==stable_orders,'stable four-face combat repeated native orders')
assert(paths==stable_paths,'stable full wall repeated path searches')
assert(total('corrections')==stable_positions,'stable contact rewrote actor positions')
assert(total('stops')==stable_stops,'stable contact repeatedly stopped a native attack')
assert(total('hits')-before_hits>=16*9,'settled front lost native attacks during the stable interval')
assert(avoidance_steps>0,'solid cross-face travel never exercised dynamic-body avoidance')

-- Harmless native separation is external physics, not a production position
-- setter. A genuinely settled owner may retain up to 64 units of drift without
-- resetting its attack, phasing through neighbours, or snapping every think.
local shifted=monsters[1]
local anchor=copy(shifted.ai.contact_move)
local shift_orders,shift_stops,shift_writes=total('orders'),total('stops'),total('corrections')
for _,amount in ipairs({8,16,24,40,56,64}) do
    shifted.p=Vector(anchor.x-amount,anchor.y,anchor.z)
    shifted.ai:OnIntervalThink()
    run(1)
    assert(shifted.ai.ai_state=='attack' and shifted.ai.contact_mode==2
        and shifted.native_rooted and not shifted.native_phased,
        'small native body separation restarted contact entry')
    assert(total('orders')==shift_orders and total('stops')==shift_stops
        and total('corrections')==shift_writes,
        'small native body separation reissued orders, stopped or snapped an attacker')
    assert(distance(shifted.p,Vector(anchor.x-amount,anchor.y,anchor.z))<.001,
        'settled drift was silently teleported back to the contact')
    for _,other in ipairs(monsters) do
        if other~=shifted then
            assert(distance(shifted.p,other.p)>=shifted:GetPaddedCollisionRadius()+other:GetPaddedCollisionRadius()-.01,
                'native separation fixture moved a retained owner inside another padded body')
        end
    end
end

-- A real knockback exceeds retention. The owner must leave its rooted state,
-- walk back using normal speed/phase-entry rules, and regain one solid slot.
local knockback_hits=shifted.hits
shifted.p=Vector(anchor.x-80,anchor.y,anchor.z)
shifted.ai:OnIntervalThink()
assert(shifted.ai.ai_state~='attack' and not shifted.ai.contact_locked,
    'an 80-unit knockback retained an invalid rooted attack contact')
run(4)
assert(shifted.ai.ai_state=='attack' and shifted.native_rooted and not shifted.native_phased
    and distance(shifted.p,anchor)<=24 and shifted.hits>knockback_hits,
    'knocked-back attacker failed to recover its real solid attack contact')

for _,m in ipairs(controllers) do m:SetWallEntIndex(-1);m:OnDestroy() end
contact.reset()
for _,u in ipairs(monsters) do assert(u.radius==32,'AI teardown did not restore original body collision') end

-- Proximity is insufficient to grant permanent retention before a successful
-- settle. A blocked owner 16 units from its slot must expire after no progress;
-- the 64-unit drift allowance belongs only to an owner that already settled.
entities,monsters,controllers={},{},{}
entities[wall:entindex()]=wall
local pending=entity(501,Vector(-200,-96),32)
monsters[#monsters+1]=pending
local first_plan=assert(contact.resolve(wall,pending))
assert(first_plan.claimed and distance(pending.p,first_plan.point)<=64,
    'unsettled-retention fixture did not enter the retained 64-unit tolerance')
local first_point=copy(first_plan.point)
local blocker=entity(502,first_point,32)
monsters[#monsters+1]=blocker
assert(not contact.settle(wall,pending,first_plan.point),'blocked pending owner unexpectedly settled')
local changed=false
for _=1,7 do
    clock=clock+.5
    local plan=contact.resolve(wall,pending)
    if not plan.claimed or distance(plan.point,first_point)>1 then changed=true end
end
assert(changed,'an owner that never settled renewed a blocked slot forever through drift tolerance')
contact.reset()
print('WALL_OPEN_FACE_AI_PASS single_entry=17 attacking=16 faces=4 solid_front=16'
    ..' corner_moves='..corner_moves..' avoidance_steps='..avoidance_steps
    ..' stable_seconds=10 orders=0 paths=0 position_writes=0 padded_front=30 drift=64 knockback=80 blocked_lease=released')
