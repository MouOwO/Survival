-- Real contact allocator and AI, with native MOVE acceptance and body collision
-- simulated offline. This verifies behavior, not Dota engine physics acceptance.
package.path = 'scripts/vscripts/?.lua;' .. package.path

Vector = function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock, paths, nav_queries = 0, 0, 0
local entities, monsters, controllers, areas = {}, {}, {}, {}
local function copy(p) return Vector(p.x,p.y,p.z) end
local function distance(a,b)
    local dx,dy=a.x-b.x,a.y-b.y
    return math.sqrt(dx*dx+dy*dy)
end
local function coordinates(face,normal,lateral,area)
    local x,y
    if face==1 then x,y=-normal,lateral
    elseif face==2 then x,y=normal,lateral
    elseif face==3 then x,y=lateral,-normal
    else x,y=lateral,normal end
    return Vector((area.x or 0)+x,(area.y or 0)+y,384)
end
local function relative(p,area) return p.x-area.x,p.y-area.y end
local function area_for(p)
    local nearest,best
    for _,area in ipairs(areas) do
        local d=(p.x-area.x)^2+(p.y-area.y)^2
        if not best or d<best then nearest,best=area,d end
    end
    return nearest
end
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
GridNav={
    IsTraversable=function(_,p)
        nav_queries=nav_queries+1
        local area=assert(area_for(p))
        local _,y=relative(p,area)
        return not area.narrow or math.abs(y)<96
    end,
    IsBlocked=function(_,p)
        nav_queries=nav_queries+1
        local area=assert(area_for(p))
        local x,y=relative(p,area)
        return math.abs(x)<128 and math.abs(y)<128
    end,
    FindPathLength=function(_,a,b)
        paths=paths+1
        local area=assert(area_for(a))
        local x1,y1=relative(a,area)
        local x2,y2=relative(b,area)
        if area.narrow and (x1*x2<0 or math.abs(y2)>=96) then return -1 end
        return distance(a,b)
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
    if order.OrderType==DOTA_UNIT_ORDER_MOVE_TO_POSITION and u.ai:GetStackCount()==3 then
        assert(u.native_phased,'contact MOVE preceded native phase application')
    end
    u.order={OrderType=order.OrderType,TargetIndex=order.TargetIndex,
        Position=order.Position and copy(order.Position)}
end

local function unit(id,p,radius,area)
    local u={p=copy(p),radius=radius or 32,area=area,orders=0,stops=0,
        corrections=0,hits=0,next_attack=0,hull_writes={},survival_monster_hull_radius=radius or 32}
    function u:entindex() return id end
    function u:GetAbsOrigin() return self.p end
    function u:SetAbsOrigin(value) self.p=copy(value);self.corrections=self.corrections+1 end
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return not self.dead end
    function u:GetHullRadius() return self.radius end
    function u:SetHullRadius(value)
        assert(value>=0,'front hull must not assign a negative collision radius')
        self.radius=value;self.hull_writes[#self.hull_writes+1]=value
    end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:GetTeamNumber() return 3 end
    function u:GetAttackCapability() return DOTA_UNIT_CAP_MELEE_ATTACK end
    function u:GetForceAttackTarget() return self.force end
    function u:SetForceAttackTarget(value) self.force=value end
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
local ai=require('modifiers/modifier_enemy_wall_ai')
local function reset()
    contact.reset()
    entities,monsters,controllers,areas={},{},{},{}
    clock=0
end
local function wall(id,x,y,narrow)
    local area={x=x or 0,y=y or 0,narrow=narrow}
    areas[#areas+1]=area
    local w=unit(id,Vector(area.x,area.y,384),128,area)
    area.wall=w
    return w,area
end
local function actor(id,area,face,normal,lateral,radius)
    local u=unit(id,coordinates(face,normal,lateral,area),radius,area)
    u.face=face
    return u
end
local function assert_contact(w,u,plan,face,lateral,label)
    assert(plan and plan.claimed,label..': contact was not admitted')
    local expected=coordinates(face,184,lateral,u.area)
    assert(distance(plan.point,expected)<.01,label..': wrong face or lane')
    assert(u:GetHullRadius()==24,label..': admitted unit did not receive its navigation hull')
    assert(u.survival_monster_hull_radius==u.nominal,
        label..': tactical contact must not overwrite nominal collision policy')
end
local lanes={-72,-24,24,72}

-- All faces are occupied concurrently on one wall. A full face must not cap
-- another face, and vacancies must be consumed by their local waiting front.
reset()
local w,area=wall(1,0,0,false)
local fronts,waiters={},{}
for lane,lateral in ipairs(lanes) do
    for face=1,4 do
        local radius=lane%2==0 and 64 or 32
        local u=actor(100+face*10+lane,area,face,400,lateral,radius)
        u.nominal=radius
        local plan=contact.resolve(w,u)
        assert_contact(w,u,plan,face,lateral,'sixteen concurrent front contacts')
        u.p=copy(plan.point)
        fronts[face]=fronts[face] or {};fronts[face][lane]=u
    end
end
for face=1,4 do
    local radius=face%2==0 and 64 or 32
    local u=actor(200+face,area,face,400,0,radius)
    local plan=assert(contact.resolve(w,u))
    assert(not plan.claimed,'fifth unit on a full face must wait')
    assert(u:GetHullRadius()==radius,'waiting units must retain their real collision hull')
    local x,y=relative(plan.point,area)
    local normal=face<=2 and math.abs(x) or math.abs(y)
    assert(normal>=184+24+radius+8,'local waiter overlaps the actual front envelope')
    waiters[face]=u
end
local released=fronts[1][2]
contact.release(w:entindex(),released:entindex())
assert(released:GetHullRadius()==64,'explicit release must restore a large original hull')
waiters[1].nominal=32
local refill=contact.resolve(w,waiters[1])
assert_contact(w,waiters[1],refill,1,-24,'same-face explicit-release replacement')
waiters[1].p=copy(refill.point)
for face=2,4 do
    assert(not contact.resolve(w,waiters[face]).claimed,
        'vacancy on another face must not admit a fifth local attacker')
end
local victim=fronts[3][4]
victim.dead=true
waiters[3].nominal=32
refill=contact.resolve(w,waiters[3])
assert_contact(w,waiters[3],refill,3,72,'same-face dead-owner replacement')
assert(victim:GetHullRadius()==64,'dead-owner cleanup must release the temporary hull')
waiters[3].p=copy(refill.point)
contact.clear(w:entindex())
for face=1,4 do
    for _,u in ipairs(fronts[face]) do
        assert(u:GetHullRadius()==u.nominal,'wall clear must restore every remaining owner')
    end
    assert(waiters[face]:GetHullRadius()==(face%2==0 and 64 or 32),
        'wall clear must restore admitted replacements and preserve waiting hulls')
end

-- A real 192-wide terrain corridor admits four bodies of diameter 48.
-- Large model/native bodies must use the same front capacity, then recover
-- their normal hull when leaving the front. Failed reservations also recover.
reset()
w,area=wall(2,0,0,true)
local narrow_front={}
for lane,lateral in ipairs(lanes) do
    local u=actor(300+lane,area,1,400,lateral,64);u.nominal=64
    local plan=contact.resolve(w,u)
    assert_contact(w,u,plan,1,lateral,'192-wide gate with large native bodies')
    if lane~=1 then u.p=copy(plan.point) end
    narrow_front[lane]=u
end
for pass=1,7 do
    clock=pass*.5
    for lane=2,4 do assert(contact.resolve(w,narrow_front[lane]).claimed) end
    local plan=contact.resolve(w,narrow_front[1])
    if pass==7 then
        assert(not plan.claimed,'a stalled owner must release its unavailable front position')
        assert(narrow_front[1]:GetHullRadius()==64,'stall release must restore the real hull')
    end
end
contact.reset()
for _,u in ipairs(narrow_front) do assert(u:GetHullRadius()==64,'reset must restore temporary hulls') end

-- While admitted, nominal policy may be changed by the existing collision
-- control. Release restores the latest policy, rather than a stale first hull.
reset()
w,area=wall(3,0,0,false)
local resized=actor(320,area,1,400,-24,32);resized.nominal=32
assert_contact(w,resized,contact.resolve(w,resized),1,-24,'external hull-policy change fixture')
resized.survival_monster_hull_radius=64
contact.release(w:entindex(),resized:entindex())
assert(resized:GetHullRadius()==64,'release must honor the most recent nominal hull policy')

-- Small and intentionally zero-sized challenge bodies must never be enlarged
-- to the tactical hull. Their original collision exemption is preserved.
reset()
w,area=wall(330,0,0,false)
for lane,radius in ipairs({0,8,16,24}) do
    local u=actor(330+lane,area,1,400,lanes[lane],radius)
    local plan=assert(contact.resolve(w,u))
    assert(plan.claimed,'small native bodies still receive one exclusive slot')
    assert(u:GetHullRadius()==radius and #u.hull_writes==0,
        'claiming a small or zero hull must not enlarge it or rewrite unchanged native properties')
    u.p=copy(plan.point)
    assert(contact.resolve(w,u).claimed and u:GetHullRadius()==radius,
        'retaining a small or zero hull must preserve its original collision size')
    contact.release(w:entindex(),u:entindex())
    assert(u:GetHullRadius()==radius and #u.hull_writes==0,
        'releasing a small or zero hull must preserve its original collision policy')
end

-- Native indices are reused independently of Lua handles. Replacing a wall
-- at the same index must restore all owners of its old handle, and a late old
-- owner release must not remove the replacement wall's new reservation.
reset()
local old_wall,old_area=wall(340,0,0,false)
local old_owner=actor(341,old_area,1,400,-72,64);old_owner.nominal=64
assert_contact(old_wall,old_owner,contact.resolve(old_wall,old_owner),1,-72,'wall-index reuse old owner')
local new_wall,new_area=wall(340,1000,0,false)
local new_owner=actor(342,new_area,1,400,72,32);new_owner.nominal=32
local new_plan=contact.resolve(new_wall,new_owner)
assert_contact(new_wall,new_owner,new_plan,1,72,'wall-index reuse replacement owner')
assert(old_owner:GetHullRadius()==64,'wall-handle replacement must restore valid old owners')
contact.release(old_wall:entindex(),old_owner:entindex())
assert(contact.resolve(new_wall,new_owner).point==new_plan.point and new_owner:GetHullRadius()==24,
    'a late old-wall owner release removed the replacement wall reservation')
contact.clear(new_wall:entindex())
assert(new_owner:GetHullRadius()==32,'replacement wall clear must restore its own owner')

-- An enemy entity may also reuse an index while its old valid Lua handle is
-- retained in the allocator. Cleanup must act on that old handle exactly once.
reset()
w,area=wall(350,0,0,false)
old_owner=actor(351,area,1,400,-72,64);old_owner.nominal=64
assert_contact(w,old_owner,contact.resolve(w,old_owner),1,-72,'enemy-index reuse old owner')
new_owner=actor(351,area,1,400,72,32);new_owner.nominal=32
assert_contact(w,new_owner,contact.resolve(w,new_owner),1,72,'enemy-index reuse replacement owner')
assert(old_owner:GetHullRadius()==64,'enemy-handle replacement must restore the old valid owner')
contact.reset()
assert(new_owner:GetHullRadius()==32,'reset must restore the reused enemy handle')

-- Existing hull controls write the native radius and policy together. While
-- admitted, the next observation retains the same reservation and reapplies
-- the bounded front hull; release then restores the newly configured radius.
reset()
w,area=wall(360,0,0,false)
resized=actor(361,area,1,400,-24,32);resized.nominal=32
local resize_plan=contact.resolve(w,resized)
assert_contact(w,resized,resize_plan,1,-24,'retained native-plus-policy resize fixture')
resized:SetHullRadius(64);resized.survival_monster_hull_radius=64;resized.nominal=64
local retained=contact.resolve(w,resized)
assert(retained.claimed and retained.point==resize_plan.point and resized:GetHullRadius()==24,
    'native-plus-policy resize must retain its slot and reapply the tactical hull')
contact.release(w:entindex(),resized:entindex())
assert(resized:GetHullRadius()==64,'retained native-plus-policy resize must restore the latest radius')

-- A direct external native resize with unchanged metadata is also observable.
-- Its value must survive both immediate release and a retained observation.
for _,observe_first in ipairs({false,true}) do
    reset();w,area=wall(370,0,0,false)
    resized=actor(371,area,1,400,24,32);resized.nominal=32
    resize_plan=contact.resolve(w,resized)
    assert_contact(w,resized,resize_plan,1,24,'external native-only resize fixture')
    resized:SetHullRadius(48)
    if observe_first then
        for pass=1,3 do
            clock=pass*.5
            retained=contact.resolve(w,resized)
            assert(retained.claimed and retained.point==resize_plan.point and resized:GetHullRadius()==24,
                'native-only resize must retain its slot and bounded navigation hull across observations')
        end
    end
    contact.release(w:entindex(),resized:entindex())
    assert(resized:GetHullRadius()==48,'release overwrote the most recent external native radius')
end

-- Initial and retained writes can fail, or a read-only native setter can
-- accept a call without changing its getter. No failed write may fabricate an
-- admission or consume one of the four slots; subsequent valid owners refill.
for _,failure in ipairs({'throw','partial_throw','missing','noop'}) do
    reset();w,area=wall(380,0,0,false)
    local rejected=actor(381,area,1,400,-72,64)
    if failure=='throw' then rejected.SetHullRadius=function() error('native hull is read-only') end
    elseif failure=='partial_throw' then
        rejected.SetHullRadius=function(self,value) self.radius=value;error('native setter failed after applying') end
    elseif failure=='missing' then rejected.SetHullRadius=nil
    else rejected.SetHullRadius=function() end end
    local denied=contact.resolve(w,rejected)
    assert(denied and not denied.claimed and rejected:GetHullRadius()==64,
        failure..': failed native hull write must not fake a new claimed contact')
    for lane,lateral in ipairs(lanes) do
        local admitted=actor(381+lane,area,1,400,lateral,64);admitted.nominal=64
        assert_contact(w,admitted,contact.resolve(w,admitted),1,lateral,
            failure..': valid owner after failed native hull write')
    end
end
for _,failure in ipairs({'throw','partial_throw','noop'}) do
    reset();w,area=wall(390,0,0,false)
    local rejected=actor(391,area,1,400,-72,64);rejected.nominal=64
    assert_contact(w,rejected,contact.resolve(w,rejected),1,-72,'retained hull-write failure fixture')
    rejected:SetHullRadius(64)
    if failure=='throw' then rejected.SetHullRadius=function() error('native hull became read-only') end
    elseif failure=='partial_throw' then
        rejected.SetHullRadius=function(self,value) self.radius=value;error('native setter failed after applying') end
    else rejected.SetHullRadius=function() end end
    local denied=contact.resolve(w,rejected)
    assert(denied and not denied.claimed and rejected:GetHullRadius()==64,
        failure..': failed retained hull write must release the obsolete reservation')
    for lane,lateral in ipairs(lanes) do
        local admitted=actor(391+lane,area,1,400,lateral,64);admitted.nominal=64
        assert_contact(w,admitted,contact.resolve(w,admitted),1,lateral,
            failure..': valid owner after failed retained hull write')
    end
end

local function controller(u,target)
    local m=setmetatable({stack=0},{__index=ai})
    function m:GetParent() return u end
    function m:GetStackCount() return self.stack end
    function m:SetStackCount(value) self.stack=value end
    function m:StartIntervalThink(interval)
        self.interval=interval;self.next_think=clock+(interval==0 and .05 or interval)
    end
    function m:ForceRefresh()
        local target_index,state,first=self.wall_entindex,self.ai_state,self.first_observation
        if self.OnRefresh then self:OnRefresh({}) end
        assert(self.wall_entindex==target_index and self.ai_state==state and self.first_observation==first,
            'native state refresh reinitialized the AI')
        u.phase_refresh_pending=true
    end
    function m:SetHasCustomTransmitterData() end
    function m:SendBuffRefreshToClients() end
    u.ai=m;monsters[#monsters+1]=u;controllers[#controllers+1]=m
    m:OnCreated({wall_entindex=target:entindex()})
    return m
end
local function move(u,goal,dt)
    if u:IsRooted() or u:IsStunned() or u:IsCommandRestricted() then return end
    local remaining=distance(u.p,goal)
    if remaining<=32 then return end -- Native MOVE acceptance deliberately stops short.
    local step=math.min(240*dt,remaining-32)
    local next_p=Vector(u.p.x+(goal.x-u.p.x)*step/remaining,
        u.p.y+(goal.y-u.p.y)*step/remaining,384)
    local x,y=relative(next_p,u.area)
    if u.area.narrow and (math.abs(y)>96-u.radius or x>-128-u.radius) then return end
    if not u.area.narrow then
        local dx=x-math.max(-128,math.min(128,x))
        local dy=y-math.max(-128,math.min(128,y))
        if dx*dx+dy*dy<u.radius*u.radius then return end
    end
    if not u.native_phased then
        for _,other in ipairs(monsters) do
            if other~=u and other:IsAlive() and not other.native_phased
                and distance(next_p,other.p)<u.radius+other.radius-.01 then return end
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
                        assert(u.ai.ai_state=='attack','waiting or chasing unit attacked through the front')
                        u.hits=u.hits+1;u.next_attack=clock+1
                        u.ai:OnAttackStart({attacker=u,target=target})
                    end
                end
            end
        end
    end
end
local function run(seconds)
    for _=1,math.floor(seconds/.05+.5) do frame(.05) end
end
local function total(field)
    local result=0
    for _,u in ipairs(monsters) do result=result+u[field] end
    return result
end
local function attacking(target)
    local result={}
    for _,u in ipairs(monsters) do
        if u:IsAlive() and u.ai.wall_entindex==target:entindex() and u.ai.ai_state=='attack' then
            result[#result+1]=u
        end
    end
    return result
end

-- Flying is a combat/visual label while native movement is still grounded.
-- These melee owners must also land sixteen concurrent native attacks, with
-- no actor manually placed at a claim or excluded from the contact range bonus.
reset()
w,area=wall(350,0,0,false)
for face=1,4 do
    for lane,lateral in ipairs(lanes) do
        local u=actor(350+face*10+lane,area,face,400,lateral,64)
        u.nominal=64
        u.survival_is_wave_monster=true
        u.survival_wave_movement_type='flying'
        u.survival_navigation_type='ground'
        u.survival_wave_skip_contact_range_bonus=false
        controller(u,w)
    end
end
run(6)
local simultaneous=attacking(w)
assert(#simultaneous==16,'flying melee owners must actually attack concurrently on all four faces')
local face_counts={0,0,0,0}
for _,u in ipairs(simultaneous) do
    assert(u.hits>0 and u:GetHullRadius()==24,'a concurrent front owner did not land its native attacks')
    assert(u.ai.contact_range_property_enabled and u.ai:GetModifierAttackRangeBonus()>0,
        'flying melee contact requires the native contact-range property and bonus')
    face_counts[u.face]=face_counts[u.face]+1
end
for face=1,4 do assert(face_counts[face]==4,'concurrent native attacks must include four owners per face') end
local simultaneous_orders,simultaneous_positions,simultaneous_paths=total('orders'),total('corrections'),paths
run(5)
assert(total('orders')==simultaneous_orders and total('corrections')==simultaneous_positions
    and paths==simultaneous_paths,'stable sixteen-front attacks restarted movement, positioning or paths')
for _,m in ipairs(controllers) do m:SetWallEntIndex(-1);m:OnDestroy() end
for _,u in ipairs(monsters) do assert(u:GetHullRadius()==64,'all-face AI cleanup failed to restore native hulls') end

-- Four players each have ninety enemies on a narrow approach. Model scale
-- and original native hull do not reduce their four actual attacking contacts.
-- Rear bodies keep physical collision; no actor is placed at its claim here.
reset()
local player_walls={}
for player=0,3 do
    local target,player_area=wall(400+player,player*5000,0,true)
    player_walls[#player_walls+1]=target
    for index=1,90 do
        local row=math.floor((index-1)/3)
        local lateral=({-64,0,64})[(index-1)%3+1]
        local normal=index<=4 and 288+(index-1)*16 or 420+row*64
        local radius=index<=4 and (index%2==0 and 64 or 32) or 32
        local u=actor(1000+player*100+index,player_area,1,normal,lateral,radius)
        u.nominal=radius
        -- Formal and endless owners use the same real allocator and AI.
        u.survival_is_wave_monster=index%2==1 and true or nil
        controller(u,target)
    end
end
run(9)
local initial={}
for _,target in ipairs(player_walls) do
    local front=attacking(target)
    assert(#front==4,'each player must have four actually attacking contacts in the 192-wide gate')
    local occupied={}
    for _,u in ipairs(front) do
        local x,y=relative(u.p,u.area)
        assert(math.abs(x+184)<.01 and (y==-72 or y==-24 or y==24 or y==72),
            'native crowd did not align all four front lanes')
        assert(not occupied[y],'native crowd put two owners in the same lane')
        occupied[y]=true
        assert(u.hits>0 and u:GetHullRadius()==24 and u.native_phased,
            'front owner must land attacks with its bounded navigation hull')
        initial[u:entindex()]=true
    end
end
for _,u in ipairs(monsters) do
    if not initial[u:entindex()] then
        assert(u.hits==0,'overflow unit must not attack')
        assert(u:GetHullRadius()==u.nominal,'rear collision hull must remain unchanged')
    end
end
local orders_before,positions_before,paths_before=total('orders'),total('corrections'),paths
local nav_before=nav_queries
run(10)
assert(total('orders')==orders_before,'stable crowd reissued native orders')
assert(total('corrections')==positions_before,'stable crowd kept writing front coordinates')
assert(paths==paths_before,'stable full fronts repeated path queries')
assert(nav_queries-nav_before<2000,'navigation work grew with all 360 waiting/attacking units')
for _,target in ipairs(player_walls) do
    local front=attacking(target)
    assert(#front==4,'stable four-player fronts lost an attacking contact')
    local victim=front[2]
    victim.dead=true;victim.ai:OnDeath({unit=victim})
    assert(victim:GetHullRadius()==victim.nominal,'death callback must restore the original hull')
end
run(6)
local replacements=0
for _,target in ipairs(player_walls) do
    local front=attacking(target)
    assert(#front==4,'one local death must refill only its single vacant contact')
    local changed=0
    for _,u in ipairs(front) do
        assert(u.hits>0,'replacement reached attack state without landing an attack')
        if not initial[u:entindex()] then changed=changed+1 end
    end
    assert(changed==1,'a death admitted more than one new owner on its wall')
    replacements=replacements+changed
end
for _,m in ipairs(controllers) do m:SetWallEntIndex(-1);m:OnDestroy() end
for _,u in ipairs(monsters) do
    assert(u:GetHullRadius()==u.nominal,'retarget/destroy must restore each original hull')
    assert(not u.ai.contact_locked and u.force==nil,'retarget/destroy must release native contact state')
end
print('WALL_FOUR_FACES_PASS concurrent_contacts=16 players=4 crowd_units=360 local_death_replacements='..replacements
    ..' stable_orders=0 stable_position_writes=0 stable_paths=0')
