-- Real allocator and AI with native MOVE acceptance and unit collision.
-- These regressions exercise actual motion, not just a returned waiting goal.
-- The offline model is deliberately bounded; it is not Dota physics acceptance.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,paths,nav_queries,rear_queries=0,0,0,0
local entities,monsters,controllers={}, {}, {}
local face,blocked,target,rear_spread=1,nil,nil,false
local graded_floor
local function copy(p) return Vector(p.x,p.y,p.z) end
local function distance(a,b)
    local x,y=a.x-b.x,a.y-b.y
    return math.sqrt(x*x+y*y)
end
local function coordinate(normal,lateral)
    local p
    if face==1 then p=Vector(-normal,lateral,384)
    elseif face==2 then p=Vector(normal,lateral,384)
    elseif face==3 then p=Vector(lateral,-normal,384)
    else p=Vector(lateral,normal,384) end
    p.z=GetGroundHeight(p)
    return p
end
local function normal(p)
    if face==1 then return -p.x elseif face==2 then return p.x
    elseif face==3 then return -p.y else return p.y end
end
local function lateral(p) return face<=2 and p.y or p.x end
local function passage_half(p) return rear_spread and normal(p)>230 and 384 or 128 end
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function(p) return graded_floor and graded_floor(normal(p)) or 384 end
GridNav={
    IsTraversable=function(_,p)
        nav_queries=nav_queries+1
        return math.abs(lateral(p))<passage_half(p)
    end,
    IsBlocked=function(_,p)
        nav_queries=nav_queries+1
        return (math.abs(p.x)<128 and math.abs(p.y)<128)
            or (blocked and blocked(p)) or false
    end,
    FindPathLength=function(_,a,b)
        paths=paths+1
        if normal(a)*normal(b)<0 then return -1 end
        return distance(a,b)
    end,
}
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
        if u:IsAlive() and distance(origin,u.p)<=radius+u:GetPaddedCollisionRadius() then nearby[#nearby+1]=u end
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
-- The fixture is a sealed straight gate for every rotation. Registration is
-- tested independently; retain its cached approach direction in this AI test.
package.loaded['systems/wall_navigation_service']={contact_face=function() return face end,
    contact_layout=function() return {axis=face<=2 and 1 or 2,min=-128,max=128,center=0} end}
local contact=require('systems/wall_melee_contact')
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
    next_p.z=GetGroundHeight(next_p)
    if math.abs(lateral(next_p))>passage_half(next_p)-u.radius or normal(next_p)<128+u.radius then return end
    if blocked and blocked(next_p) then return end
    if not u.native_phased then
        for _,other in ipairs(monsters) do
            if other~=u and other:IsAlive() and not other.native_phased
                and distance(next_p,other.p)<u:GetPaddedCollisionRadius()+other:GetPaddedCollisionRadius()-.01 then return end
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
            local along=lateral(u.p)
            assert(math.abs(normal(u.p)-184)<.01,label..': front was displaced from the wall face')
            assert(along==-96 or along==-32 or along==32 or along==96,label..': wrong front lane')
            assert(not lanes[along],label..': duplicated front lane');lanes[along]=true
            assert(u.hits>0 and u.radius==20 and not u.native_phased,label..': contact must attack with collision')
        end
    end
    assert(#result==4,label..': expected four actual attacking contacts')
    return result
end
local function setup(side,grade)
    contact.reset();entities,monsters,controllers={},{},{}
    clock=0;face=side;blocked=nil;rear_spread=false;graded_floor=grade;target=unit(1,coordinate(0,0),128)
    for index,along in ipairs({-96,-32,32,96}) do controller(unit(10+index,coordinate(320,along))) end
    run(3);return fronts('initial face '..side)
end
local function rear(u,label)
    local attackers=fronts(label)
    assert(normal(u.p)>=184+30+(u.original_radius+10)+8-.01,label..': fifth remained inside the front envelope')
    for _,front in ipairs(attackers) do
        assert(distance(u.p,front.p)>=u:GetPaddedCollisionRadius()+front:GetPaddedCollisionRadius()-.01,label..': fifth overlaps an attacker')
    end
    assert(u.ai.ai_state=='waiting' and not u.native_phased,label..': safe waiter kept retreat phase')
    assert(u:IsDisarmed() and not u:IsRooted(),label..': safe waiter has an incorrect native state')
    assert(u.radius==u.original_radius and u.hull_writes==0,label..': retreat changed the configured hull')
    assert(u.hits==0 and u.force==nil and u:Script_GetAttackRange()==128,label..': fifth received attack permission')
    assert(u.corrections==0,label..': waiter was teleported instead of retreating')
end
local function stable(label)
    local orders,corrections,path_count=total('orders'),total('corrections'),paths
    local query_count=rear_queries
    local prior_hits=total('hits');run(10)
    fronts(label)
    assert(total('hits')>prior_hits,label..': four front attackers stopped landing attacks')
    assert(total('orders')==orders,label..': stable rear/front reissued orders')
    assert(total('corrections')==corrections,label..': stable actors kept writing coordinates')
    assert(paths==path_count,label..': stable full front repeated path searches')
    assert(rear_queries==query_count,label..': ordinary stable waiting kept querying rear bodies')
end

-- A settled solid contact can be shifted a little by native avoidance.
-- Retaining its attack must not phase/snap it back or restart native orders.
do
    local established=setup(1)
    local shifted=established[1]
    local goal=shifted.ai.contact_move
    shifted.p=coordinate(224,lateral(shifted.p))
    local before=copy(shifted.p)
    local orders,corrections,path_count,query_count=total('orders'),total('corrections'),paths,rear_queries
    local hits=shifted.hits
    run(5)
    assert(shifted.ai.ai_state=='attack' and shifted.ai.contact_move==goal
        and not shifted.native_phased and shifted:IsRooted() and shifted.hits>hits,
        'settled contact inside native arrival hysteresis must keep attacking with collision')
    assert(distance(shifted.p,before)<.01 and total('corrections')==corrections,
        'native avoidance drift caused repeated coordinate alignment')
    assert(total('orders')==orders and paths==path_count and rear_queries==query_count,
        'native avoidance drift restarted orders, routes, or local body queries')
end

-- A dense rear occupies every straight retreat stop. Several bodies pushed
-- into the front must reserve different lateral exits, accounting for both
-- native padding and the final 32-unit MOVE acceptance segment. The wider
-- rear courtyard is real terrain; the gate itself remains 256 units wide.
do
    setup(1);rear_spread=true
    local id=100
    for _,depth in ipairs({264,356,448}) do
        for _,along in ipairs({-84,0,84}) do
            id=id+1
            local blocker=unit(id,coordinate(depth,along));blocker.rooted=true
            local m=controller(blocker);m:OnIntervalThink()
        end
    end
    for index=1,5 do
        id=id+1
        local blocker=unit(id,coordinate(640+index*96,0));blocker.rooted=true
        local m=controller(blocker);m:OnIntervalThink()
    end
    local intruders={}
    for index,along in ipairs({-32,32}) do
        local u=unit(200+index,coordinate(184,along));local m=controller(u)
        local query_count=rear_queries
        m:OnIntervalThink()
        assert(m.ai_state=='retreat','dense rear did not find a free lateral retreat')
        assert(rear_queries==query_count+1,'retreat candidates repeated the local native body query')
        for _,other in ipairs(intruders) do
            assert(distance(m.contact_move,other.ai.contact_move)>=92-.01,
                'simultaneous retreaters reserved overlapping native acceptance goals')
        end
        intruders[#intruders+1]=u
    end
    assert(#monsters==20,'congested regression must retain twenty live monsters')
    run(6)
    for _,u in ipairs(intruders) do
        rear(u,'dense rear body-aware exit')
        assert(u.retreat_orders>=1 and u.retreat_orders<=2,
            'occupied straight exits caused repeated extension toward the radial limit')
    end
    for index,u in ipairs(monsters) do
        for other_index=index+1,#monsters do
            local other=monsters[other_index]
            assert(not u.native_phased and not other.native_phased,
                'dense rear retained indefinite temporary unit phasing')
            assert(distance(u.p,other.p)>=u:GetPaddedCollisionRadius()+other:GetPaddedCollisionRadius()-.01,
                'dense rear restored collision with overlapping native padded bodies')
        end
    end
    stable('stable dense rear exits')
end

-- An established wait goal does not authorize a displaced body to remain in
-- the front. Cancel the first native retreat MOVE and require bounded recovery.
-- Native walking must follow continuous stairs beyond the wall's height
-- band. A newly occupied stop forces a second downhill goal: the exact
-- sampled heights were 300.354 at depth296 and 254.354 at depth388.
for side=1,4 do
    setup(side,function(depth) return math.min(385.5,448.354-depth*.5) end)
    rear_spread=true
    local u=unit(400,coordinate(184,0));local m=controller(u)
    m:OnIntervalThink()
    assert(m.ai_state=='retreat','continuous descending stairs must admit a real ground retreat')
    run(.1)
    u.p=copy(m.contact_move);u.order=nil
    assert(math.abs(normal(u.p)-296)<.01 and math.abs(u.p.z-300.354)<.01,
        'graded retreat fixture must reach the real native stopped-goal elevation')
    m.progress_position=copy(u.p);m.last_progress_time=clock;m.last_order_time=clock
    local blocker=unit(401,coordinate(326,0));blocker.rooted=true
    local blocker_ai=controller(blocker);blocker_ai:OnIntervalThink()
    assert(not contact.rear_clear(target,u),'graded fixture must reproduce an actual hard body overlap')
    local old_orders=u.retreat_orders
    local stopped_height=u.p.z
    m:OnIntervalThink();run(.1)
    local next_goal=m.contact_move
    assert(math.abs(normal(next_goal)-388)<.01 and math.abs(next_goal.z-254.354)<.01,
        'blocked retreat must select the free lower stair row')
    assert(math.abs(next_goal.z-target.p.z)>128 and math.abs(next_goal.z-stopped_height)>32,
        'native MOVE regression must exercise both obsolete wall-height and flat-segment caps')
    run(5)
    rear(u,'graded blocked-stop recovery face '..side)
    assert(u.retreat_orders==old_orders+1 and u.corrections==0,
        'descending stair recovery must use one native MOVE, never coordinate correction')
    assert(distance(u.p,blocker.p)>=u:GetPaddedCollisionRadius()+blocker:GetPaddedCollisionRadius()+8-.01,
        'descending stair phase ended before the padded bodies separated')
    stable('stable graded retreat recovery face '..side)
end

-- A native MOVE can be idle, or remain busy against a bank with no progress.
-- Neither may stay phased far from its goal, including while still intruding
-- into the front. Actual moving bodies must not incur a retreat-body search.
for _,busy in ipairs({false,true}) do for side=1,4 do
    setup(side);rear_spread=true
    local first_blocker=unit(300,coordinate(388,32));first_blocker.rooted=true
    local first_ai=controller(first_blocker);first_ai:OnIntervalThink()
    local u=unit(301,coordinate(184,32));local m=controller(u)
    m:OnIntervalThink()
    local plan=assert(contact.resolve(target,u,side))
    local diagonal=assert(contact.retreat_point(target,u,plan,388))
    assert(math.abs(lateral(diagonal)-32)>1,'idle-stop fixture must use a real diagonal retreat')
    m:EnterState('retreat',u,target,diagonal,plan);run(.1)
    first_blocker.p=coordinate(448,-84)
    u.p=coordinate(busy and 244 or 296,56.7)
    if not busy then u.order=nil end
    assert(u:IsIdle()==not busy,'blocked MOVE fixture must preserve its native busy/idle state')
    m.progress_position=copy(u.p);m.last_progress_time=clock;m.last_order_time=clock
    local blocker=unit(302,coordinate(busy and 280.8 or 332.8,18.8));blocker.rooted=true
    local blocker_ai=controller(blocker);blocker_ai:OnIntervalThink()
    local before_queries,before_orders=rear_queries,u.retreat_orders
    local premature,checked=contact.extend_retreat(target,u,plan,diagonal)
    assert(not premature and checked==false and rear_queries==before_queries,
        'fresh native progress must not prematurely replace the in-flight retreat')
    if busy then
        assert(contact.resolve(target,u,side).wait_retreat,
            'busy blocked MOVE must reproduce the still-intruding AI extension branch')
    end
    assert(not contact.rear_clear(target,u),'idle native stop must reproduce the padded-body overlap')
    assert(distance(u.p,diagonal)>32 and normal(diagonal)-normal(u.p)>32,
        'idle-stop regression must not pass the obsolete normal-distance gate')
    clock=clock+.5
    local stopped=copy(u.p);u.p=coordinate(normal(stopped)+8,lateral(stopped))
    before_queries=rear_queries
    premature,checked=contact.extend_retreat(target,u,plan,diagonal)
    assert(not premature and checked==false and rear_queries==before_queries,
        'real current movement must suppress extension before MonitorState records its progress')
    u.p=stopped;m:OnIntervalThink()
    run(5)
    rear(u,'idle diagonal stop face '..side)
    assert(distance(m.contact_move,diagonal)>1,
        'idle blocked retreat must select a new safe goal rather than retry the abandoned MOVE')
    assert(u.retreat_orders==before_orders+1,
        'one idle blocked retreat must select exactly one new safe destination')
    assert(distance(u.p,blocker.p)>=u:GetPaddedCollisionRadius()+blocker:GetPaddedCollisionRadius()+8-.01,
        'idle retreat recovery restored collision before clearing the new body')
    stable('stable idle diagonal recovery face '..side)
end end

for side=1,4 do
    setup(side)
    local fifth=unit(30,coordinate(400,0));controller(fifth);run(3)
    rear(fifth,'ordinary rear face '..side)
    fifth.p=coordinate(184,0);fifth.cancel_first_retreat=true
    fifth.ai:OnIntervalThink()
    assert(fifth.ai.ai_state=='retreat' and fifth.ai:GetStackCount()==4,
        'an established waiter pushed into the front must enter retreat on every face')
    assert(fifth.retreat_orders==0 and not fifth.native_phased,
        'retreat MOVE must wait for its native phase frame')
    run(3)
    assert(fifth.cancelled_retreat and fifth.recovered_retreat and fifth.retreat_orders==2,
        'one silently cancelled retreat must receive exactly one early retry')
    rear(fifth,'displaced waiter face '..side);stable('stable displaced waiter face '..side)
end

-- A rear Hull32 body stops within native acceptance of its own goal, blocking
-- an ordinary reverse MOVE. The fifth must leave through that queue by motion.
for side=1,4 do
    setup(side)
    local fifth=unit(30,coordinate(184,0));controller(fifth)
    local blocker=unit(31,coordinate(264,0));controller(blocker)
    run(3)
    assert(fifth.retreat_orders>=1 and fifth.retreat_orders<=3,
        'rear obstruction must use a bounded number of real retreat goals')
    rear(fifth,'blocked rear queue face '..side);rear(blocker,'rear blocker face '..side)
    assert(distance(fifth.p,blocker.p)>=fifth:GetPaddedCollisionRadius()+blocker:GetPaddedCollisionRadius()+8-.01,
        'phase exit left the fifth overlapping the ordinary rear blocker')
    stable('stable blocked rear queue face '..side)
end

-- Two unadmitted bodies can need to leave the same front at once. Phase must
-- finish in finite motion, with neither body released into the other's hull.
for side=1,4 do
    setup(side)
    local first=unit(30,coordinate(184,-32));controller(first)
    local second=unit(31,coordinate(184,32));controller(second)
    run(4)
    rear(first,'first simultaneous intruder face '..side)
    rear(second,'second simultaneous intruder face '..side)
    assert(distance(first.p,second.p)>=first:GetPaddedCollisionRadius()+second:GetPaddedCollisionRadius()+8-.01,
        'simultaneous retreaters restored physical collision while overlapping')
    assert(first.retreat_orders>=1 and first.retreat_orders<=3
        and second.retreat_orders>=1 and second.retreat_orders<=3,
        'simultaneous retreaters did not finish with bounded movement')
    stable('stable simultaneous retreaters face '..side)
end

-- Lua must not phase or move a controlled unit out from under its controller.
for _,status in ipairs({'rooted','stunned','restricted','horizontal','vertical'}) do
    setup(1)
    local fifth=unit(30,coordinate(184,0));fifth[status]=true;controller(fifth)
    local before=copy(fifth.p);run(3)
    fronts('controlled waiter '..status)
    assert(fifth.retreat_orders==0 and not fifth.native_phased and fifth.ai:GetStackCount()~=4,
        'controlled waiter must not start phased retreat: '..status)
    assert(distance(fifth.p,before)<.01 and fifth.corrections==0,
        'controlled waiter was moved by the retreat controller: '..status)
    assert(fifth.hits==0 and fifth.radius==32 and fifth:Script_GetAttackRange()==128,
        'controlled waiter acquired front combat state: '..status)
    fifth[status]=false;run(3);rear(fifth,'released waiter '..status)
end

-- Control can begin after the native phase frame, while retreat is moving.
-- Remove retreat phase on observation, then recover without teleporting when
-- the external controller releases the still-intruding waiting body.
for _,status in ipairs({'rooted','stunned','restricted','horizontal','vertical'}) do
    setup(1)
    local fifth=unit(30,coordinate(184,0));controller(fifth);run(.1)
    assert(fifth.ai.ai_state=='retreat' and fifth.native_phased and normal(fifth.p)<264,
        'mid-retreat control fixture did not start moving inside the front')
    fifth[status]=true;local before=copy(fifth.p);fifth.ai:OnIntervalThink()
    assert(fifth.ai:GetStackCount()~=4,'new external control retained retreat mode: '..status)
    run(3)
    assert(not fifth.native_phased and distance(fifth.p,before)<.01 and fifth.corrections==0,
        'mid-retreat external controller was bypassed: '..status)
    assert(fifth.hits==0 and fifth.radius==32 and fifth:Script_GetAttackRange()==128,
        'mid-retreat control acquired attack permission: '..status)
    fifth[status]=false;run(3);rear(fifth,'mid-retreat controller released '..status)
end

-- Reject a blocked default destination but recover to a legal alternate on
-- this same face. With every rear destination blocked, do not phase blindly.
for side=1,4 do
    setup(side)
    blocked=function(p) return math.abs(normal(p)-296)<2 and math.abs(lateral(p)-32)<2 end
    local fifth=unit(30,coordinate(184,32));controller(fifth)
    run(3);rear(fifth,'alternate rear goal face '..side)
    assert(normal(fifth.ai.contact_move)>184 and not blocked(fifth.ai.contact_move),
        'blocked default goal did not select a safe same-face destination')
    setup(side)
    blocked=function(p)
        -- A narrower rear passage fits a centered Hull32, while each of the
        -- four lane centers places some of that same hull inside a bank.
        return normal(p)>230 and math.abs(lateral(p))>40
    end
    local center_only=unit(30,coordinate(184,0));controller(center_only)
    run(3);rear(center_only,'only center rear goal clear face '..side)
    assert(lateral(center_only.ai.contact_move)==0,
        'all four rear lanes blocked must still permit a legal same-face center goal')
    setup(side)
    blocked=function(p) return normal(p)>230 end
    local trapped=unit(30,coordinate(184,0));controller(trapped);run(3)
    fronts('all rear goals blocked face '..side)
    assert(trapped.ai.ai_state=='waiting' and trapped.retreat_orders==0 and not trapped.native_phased,
        'an entirely blocked rear must not enable unit phase')
    assert(normal(trapped.p)==184 and trapped.corrections==0 and trapped.hits==0
        and trapped.radius==32 and trapped:Script_GetAttackRange()==128,
        'blocked retreat moved or armed the unadmitted waiter')
    blocked=nil;run(3);rear(trapped,'rear obstruction removed face '..side)
end

-- Reaching a different nearest lane during a slow diagonal fallback does not
-- replace a valid retreat goal or start another native state frame/MOVE.
setup(1)
blocked=function(p) return math.abs(normal(p)-296)<2 and math.abs(lateral(p)-32)<2 end
local diagonal=unit(30,coordinate(184,32));diagonal.speed=100;controller(diagonal)
diagonal.ai:OnIntervalThink()
assert(diagonal.ai.ai_state=='retreat' and lateral(diagonal.ai.contact_move)==-96,
    'blocked first retreat destination must exercise the diagonal rear fallback')
local diagonal_goal=copy(diagonal.ai.contact_move)
run(.55)
assert(lateral(diagonal.p)<0 and normal(diagonal.p)<264,
    'slow diagonal retreat did not cross to the adjacent nearest lane while still intruding')
assert(distance(diagonal.ai.contact_move,diagonal_goal)<.01 and diagonal.retreat_orders==1,
    'a nearest-lane change replaced the safe in-progress retreat or issued another MOVE')
run(3);rear(diagonal,'slow diagonal sticky retreat');stable('stable slow diagonal retreat')

-- A legal endpoint alone cannot authorize unit phase. The default direct
-- segment crosses this rectangle, while a diagonal rear lane is reachable.
setup(1)
blocked=function(p)
    return normal(p)>=218 and normal(p)<=238 and lateral(p)>=16 and lateral(p)<=32
end
local around=unit(30,coordinate(184,32));controller(around)
assert(not GridNav:IsBlocked(coordinate(296,32)),
    'short-segment obstacle fixture accidentally blocked the default destination')
run(3);rear(around,'blocked direct segment with safe diagonal retreat')
assert(lateral(around.ai.contact_move)~=32 and around.retreat_orders==1,
    'a blocked default short segment did not choose a safe alternate rear lane once')

-- Every destination is clear but the full rear route is blocked. Repeated
-- stationary observations share the failed short-segment backoff; removing
-- the obstruction later recovers even if native MOVE already disappeared.
setup(1)
blocked=function(p) return normal(p)>=218 and normal(p)<=238 end
local no_route=unit(30,coordinate(184,0));controller(no_route);run(1)
assert(no_route.ai.ai_state=='waiting' and not no_route.native_phased and no_route.retreat_orders==0,
    'clear endpoints must not phase a waiter through an obstructed rear route')
assert(no_route.hits==0 and no_route.radius==32 and no_route.corrections==0,
    'failed short segments changed the unadmitted waiting body')
no_route.order=nil -- Native MOVE can silently give up at a new obstruction.
local failed_nav,failed_paths=nav_queries,paths
for _=1,12 do no_route.ai:OnIntervalThink() end
assert(nav_queries==failed_nav and paths==failed_paths,
    'stationary failed retreat repeatedly checked every rear segment before backoff elapsed')
blocked=nil;run(3);rear(no_route,'failed rear-route backoff recovery')

-- Retreat grants no claim. A single death later promotes exactly one waiting
-- unit into the vacated lane, with normal contact cleanup on target release.
local initial=setup(1)
local fifth=unit(30,coordinate(184,0));controller(fifth);run(3)
rear(fifth,'before death promotion')
local victim=initial[2];local old_lane=lateral(victim.p)
victim.dead=true;victim.ai:OnDeath({unit=victim})
assert(victim.radius==32,'death must restore the previous front hull')
run(3)
local attackers=fronts('single death promotion');local promoted=0
for _,u in ipairs(attackers) do
    if u==fifth then promoted=promoted+1;assert(lateral(u.p)==old_lane,'replacement changed the vacated lane') end
end
assert(promoted==1 and fifth.hits>0 and fifth.radius==20,'death must promote precisely the fifth waiter')
stable('stable replacement')
for _,m in ipairs(controllers) do m:SetWallEntIndex(-1);m:OnDestroy() end
for _,u in ipairs(monsters) do
    assert(u.radius==32 and not u.ai:CheckState()[MODIFIER_STATE_NO_UNIT_COLLISION]
        and not u.ai:CheckState()[MODIFIER_STATE_ROOTED] and not u.ai:CheckState()[MODIFIER_STATE_DISARMED]
        and u:Script_GetAttackRange()==128 and u.force==nil,'target release retained temporary contact state')
end
contact.reset()
print('WALL_WAITER_RETREAT_PASS four_faces dense_rear idle_and_busy_2d_stop busy_front_intrusion moving_no_query displaced_waiter cancelled_move rear_clear simultaneous_intruders external_controls center_fallback sticky_diagonal safe_segment blocked_goals failure_backoff death_promotion stable_orders=0 stable_coordinates=0 stable_paths=0 stable_rear_queries=0')
