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
        return not area.narrow or math.abs(y)<192
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
        if area.narrow and (x1*x2<0 or math.abs(y2)>=192) then return -1 end
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
DOTA_UNIT_TARGET_TEAM_BOTH=3
DOTA_UNIT_TARGET_BASIC=1;DOTA_UNIT_TARGET_HERO=2
DOTA_UNIT_TARGET_FLAG_INVULNERABLE=1;DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=2
FIND_ANY_ORDER=0
package.loaded['core/team_alignment']={
    are_enemies=function() return true end,
    enforce=function() error('unexpected team correction') end,
}
EntIndexToHScript=function(index) return entities[index] end
FindUnitsInRadius=function(_,point,_,radius)
    assert(radius==512,'settlement must use a bounded local body snapshot')
    local result={}
    for _,u in pairs(entities) do
        if u:IsAlive() and distance(point,u.p)<=radius then result[#result+1]=u end
    end
    return result
end
ExecuteOrderFromTable=function(order)
    local u=assert(entities[order.UnitIndex])
    u.orders=u.orders+1
    assert(not u.ai:CheckState()[MODIFIER_STATE_NO_UNIT_COLLISION],
        'a reserved contact must never phase through a living monster')
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
-- Open areas keep four faces. The narrow fixtures have proven west/east
-- banks, whose cached direction is exercised separately by navigation tests.
package.loaded['systems/wall_navigation_service']={contact_face=function(w,u)
    if u.area.narrow then return u.p.x<w.p.x and 1 or 2 end
end,contact_layout=function(w)
    if w.area.narrow then return {gate=true,axis=1,min=w.area.y-192,max=w.area.y+192,center=w.area.y} end
end}
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
    assert(u:GetHullRadius()==u.nominal and #u.hull_writes==0,
        label..': contact admission changed the configured native collision hull')
    assert(u.survival_monster_hull_radius==u.nominal,
        label..': tactical contact must not overwrite nominal collision policy')
end
local lanes={-132,-44,44,132}
local narrow_lanes=lanes

-- All faces are occupied concurrently on one wall. A full face must not cap
-- another face, and vacancies must be consumed by their local waiting front.
reset()
local w,area=wall(1,0,0,false)
local fronts,waiters={},{}
for lane,lateral in ipairs(lanes) do
    for face=1,4 do
        local radius=32
        local u=actor(100+face*10+lane,area,face,400,lateral,radius)
        u.nominal=radius
        local plan=contact.resolve(w,u)
        assert_contact(w,u,plan,face,lateral,'sixteen concurrent front contacts')
        u.p=copy(plan.point)
        fronts[face]=fronts[face] or {};fronts[face][lane]=u
    end
end
for face=1,4 do
    local radius=32
    local u=actor(200+face,area,face,400,0,radius)
    local plan=assert(contact.resolve(w,u))
    assert(not plan.claimed,'fifth unit on a full face must wait')
    assert(u:GetHullRadius()==radius,'waiting units must retain their real collision hull')
    local x,y=relative(plan.point,area)
    local normal=face<=2 and math.abs(x) or math.abs(y)
    assert(normal>=184+42+(radius+10)+8,'local waiter overlaps the actual front envelope')
    waiters[face]=u
end
local released=fronts[1][2]
contact.release(w:entindex(),released:entindex())
assert(released:GetHullRadius()==32,'explicit release must preserve the fixed native hull')
clock=clock+.5 -- New admissions share one bounded path budget per wall/observation.
waiters[1].nominal=32
local refill=contact.resolve(w,waiters[1])
assert_contact(w,waiters[1],refill,1,-44,'same-face explicit-release replacement')
waiters[1].p=copy(refill.point)
for face=2,4 do
    assert(not contact.resolve(w,waiters[face]).claimed,
        'vacancy on another face must not admit a fifth local attacker')
end
local victim=fronts[3][4]
victim.dead=true
waiters[3].nominal=32
refill=contact.resolve(w,waiters[3])
assert_contact(w,waiters[3],refill,3,132,'same-face dead-owner replacement')
assert(victim:GetHullRadius()==32,'dead-owner cleanup must not rewrite the native hull')
waiters[3].p=copy(refill.point)
contact.clear(w:entindex())
for face=1,4 do
    for _,u in ipairs(fronts[face]) do
        assert(u:GetHullRadius()==u.nominal,'wall clear must restore every remaining owner')
    end
    assert(waiters[face]:GetHullRadius()==32 and #waiters[face].hull_writes==0,
        'wall clear must preserve admitted and waiting native hulls')
end

-- A real384 stair fits four88-pitch lanes with fixed Hull32 and padding10.
-- Failed reservations release their key without changing a native body.
reset()
w,area=wall(2,0,0,true)
local narrow_front={}
for lane,lateral in ipairs(narrow_lanes) do
    local u=actor(300+lane,area,1,400,lateral,32);u.nominal=32
    local plan=contact.resolve(w,u)
    assert_contact(w,u,plan,1,lateral,'384-wide gate with solid native bodies')
    if lane~=1 then
        u.p=copy(plan.point)
        assert(contact.settle(w,u,plan.point),'stationary narrow-front fixture must actually settle')
    end
    narrow_front[lane]=u
end
for pass=1,7 do
    clock=pass*.5
    for lane=2,4 do assert(contact.resolve(w,narrow_front[lane]).claimed) end
    local plan=contact.resolve(w,narrow_front[1])
    if pass==7 then
        assert(not plan.claimed,'a stalled owner must release its unavailable front position')
        assert(narrow_front[1]:GetHullRadius()==32 and #narrow_front[1].hull_writes==0,
            'stall release must preserve the real hull without a setter')
    end
end
contact.reset()
for _,u in ipairs(narrow_front) do assert(u:GetHullRadius()==32 and #u.hull_writes==0,
    'reset must preserve fixed native hulls') end

-- Metadata-only policy changes do not authorize contact code to resize an
-- actor. The policy controller owns its native setter, including on release.
reset()
w,area=wall(3,0,0,false)
local resized=actor(320,area,1,400,-44,32);resized.nominal=32
assert_contact(w,resized,contact.resolve(w,resized),1,-44,'external hull-policy change fixture')
resized.survival_monster_hull_radius=64
contact.release(w:entindex(),resized:entindex())
assert(resized:GetHullRadius()==32 and resized.survival_monster_hull_radius==64
    and #resized.hull_writes==0,'release must leave native resizing to its actual policy owner')

-- Legacy externally created small bodies are never resized by contact code.
-- Production wall-spawn policy is separately covered at the fixed Hull32.
reset()
w,area=wall(330,0,0,false)
for lane,radius in ipairs({0,8,16,20}) do
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
local old_owner=actor(341,old_area,1,400,-132,32);old_owner.nominal=32
assert_contact(old_wall,old_owner,contact.resolve(old_wall,old_owner),1,-132,'wall-index reuse old owner')
local new_wall,new_area=wall(340,1000,0,false)
local new_owner=actor(342,new_area,1,400,132,32);new_owner.nominal=32
local new_plan=contact.resolve(new_wall,new_owner)
assert_contact(new_wall,new_owner,new_plan,1,132,'wall-index reuse replacement owner')
assert(old_owner:GetHullRadius()==32 and #old_owner.hull_writes==0,
    'wall-handle replacement must preserve valid old owners')
contact.release(old_wall:entindex(),old_owner:entindex())
assert(contact.resolve(new_wall,new_owner).point==new_plan.point and new_owner:GetHullRadius()==32,
    'a late old-wall owner release removed the replacement wall reservation')
contact.clear(new_wall:entindex())
assert(new_owner:GetHullRadius()==32,'replacement wall clear must restore its own owner')

-- An enemy entity may also reuse an index while its old valid Lua handle is
-- retained in the allocator. Cleanup must act on that old handle exactly once.
reset()
w,area=wall(350,0,0,false)
old_owner=actor(351,area,1,400,-132,32);old_owner.nominal=32
assert_contact(w,old_owner,contact.resolve(w,old_owner),1,-132,'enemy-index reuse old owner')
new_owner=actor(351,area,1,400,132,32);new_owner.nominal=32
assert_contact(w,new_owner,contact.resolve(w,new_owner),1,132,'enemy-index reuse replacement owner')
assert(old_owner:GetHullRadius()==32 and #old_owner.hull_writes==0,
    'enemy-handle replacement must preserve the old valid owner')
contact.reset()
assert(new_owner:GetHullRadius()==32,'reset must restore the reused enemy handle')

-- An external controller may deliberately resize a body. Observing or clearing
-- that contact must never shrink it back down to make an attack slot fit.
reset()
w,area=wall(360,0,0,false)
resized=actor(361,area,1,400,-44,32);resized.nominal=32
local resize_plan=contact.resolve(w,resized)
assert_contact(w,resized,resize_plan,1,-44,'retained native-plus-policy resize fixture')
resized:SetHullRadius(64);resized.survival_monster_hull_radius=64;resized.nominal=64
local retained=contact.resolve(w,resized)
assert(retained.claimed and retained.point==resize_plan.point and resized:GetHullRadius()==64
    and #resized.hull_writes==1,'contact observation overwrote an external native resize')
contact.release(w:entindex(),resized:entindex())
assert(resized:GetHullRadius()==64,'retained native-plus-policy resize must restore the latest radius')

-- A direct external native resize with unchanged metadata is also observable.
-- Its value must survive both immediate release and a retained observation.
for _,observe_first in ipairs({false,true}) do
    reset();w,area=wall(370,0,0,false)
    resized=actor(371,area,1,400,44,32);resized.nominal=32
    resize_plan=contact.resolve(w,resized)
    assert_contact(w,resized,resize_plan,1,44,'external native-only resize fixture')
    resized:SetHullRadius(48)
    if observe_first then
        for pass=1,3 do
            clock=pass*.5
            retained=contact.resolve(w,resized)
            assert(retained.claimed and retained.point==resize_plan.point and resized:GetHullRadius()==48
                and #resized.hull_writes==1,
                'native-only resize must survive every contact observation without a rewrite')
        end
    end
    contact.release(w:entindex(),resized:entindex())
    assert(resized:GetHullRadius()==48,'release overwrote the most recent external native radius')
end

-- Contact admission no longer needs a native hull setter at all. Missing,
-- read-only, failing or misleading setters cannot prevent a solid Hull32 owner
-- from taking a legal contact, and none may ever be invoked by this allocator.
for _,failure in ipairs({'throw','partial_throw','missing','noop'}) do
    reset();w,area=wall(380,0,0,false)
    local writes=0
    for lane,lateral in ipairs(lanes) do
        local admitted=actor(381+lane,area,1,400,lateral,32);admitted.nominal=32
        if failure=='missing' then admitted.SetHullRadius=nil
        else admitted.SetHullRadius=function(self,value)
            writes=writes+1
            if failure=='partial_throw' then self.radius=value end
            if failure~='noop' then error('native hull setter must not be called') end
        end end
        assert_contact(w,admitted,contact.resolve(w,admitted),1,lateral,
            failure..': legal owner with unavailable native hull setter')
        local point=contact.resolve(w,admitted).point
        admitted.p=copy(point)
        assert(contact.settle(w,admitted,point))
    end
    contact.reset()
    assert(writes==0,failure..': admission/cleanup attempted a native hull write')
end
for _,failure in ipairs({'throw','partial_throw','noop'}) do
    reset();w,area=wall(390,0,0,false)
    local admitted=actor(391,area,1,400,-132,32);admitted.nominal=32
    local original=contact.resolve(w,admitted)
    assert_contact(w,admitted,original,1,-132,'retained read-only hull fixture')
    admitted.p=copy(original.point);assert(contact.settle(w,admitted,original.point))
    local writes=0
    admitted.SetHullRadius=function(self,value)
        writes=writes+1
        if failure=='partial_throw' then self.radius=value end
        if failure~='noop' then error('retained native hull setter must not be called') end
    end
    clock=.5
    local retained=contact.resolve(w,admitted)
    assert(retained.claimed and retained.point==original.point and admitted.radius==32,
        failure..': retaining a solid body must not depend on native setter availability')
    contact.release(w:entindex(),admitted:entindex())
    assert(writes==0,failure..': retention/release attempted a native hull write')
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
    if u.area.narrow and (math.abs(y)>192-u.radius or x>-128-u.radius) then return end
    if not u.area.narrow then
        local dx=x-math.max(-128,math.min(128,x))
        local dy=y-math.max(-128,math.min(128,y))
        if dx*dx+dy*dy<u.radius*u.radius then return end
    end
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
        local u=actor(350+face*10+lane,area,face,400,lateral,32)
        u.nominal=32
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
    assert(u.hits>0 and u:GetHullRadius()==32 and #u.hull_writes==0,
        'a concurrent front owner did not land attacks with its unchanged native body')
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
for _,u in ipairs(monsters) do assert(u:GetHullRadius()==32 and #u.hull_writes==0
    and u.corrections==0,'all-face AI cleanup changed a fixed body or wrote coordinates') end

-- Four players each have ninety enemies on a384 approach. Every unit retains
-- a real Hull32 body, both at the attack front and while waiting behind it.
-- Rear bodies keep physical collision; no actor is placed at its claim here.
reset()
local player_walls={}
for player=0,3 do
    local target,player_area=wall(400+player,player*5000,0,true)
    player_walls[#player_walls+1]=target
    for index=1,90 do
        local row=math.floor((index-1)/4)
        local lateral=lanes[(index-1)%4+1]
        local normal=400+row*88
        local radius=32
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
    assert(#front==4,'each player must have four actually attacking contacts in the384 stair')
    local occupied={}
    for _,u in ipairs(front) do
        local x,y=relative(u.p,u.area)
        assert(x<=-184 and x>=-220 and (y==-132 or y==-44 or y==44 or y==132),
            'native MOVE acceptance must reach each lane without snapping coordinates')
        assert(not occupied[y],'native crowd put two owners in the same lane')
        occupied[y]=true
        assert(u.hits>0 and u:GetHullRadius()==32 and not u.native_phased and #u.hull_writes==0,
            'front owner must keep its full native body while landing attacks')
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
-- Each wall has four front owners. Every two-second cache window costs at
-- most one five-point hull check per owner plus two waiter variants per lane;
-- IsTraversable/IsBlocked each contribute one query per sample. Rear count
-- does not multiply this bound, even with ninety enemies behind each wall.
local nav_budget=4*4*math.ceil(10/2)*5*2*(1+2)
assert(nav_queries-nav_before<=nav_budget,'navigation work exceeded the fixed front/cache budget: '
    ..(nav_queries-nav_before)..' > '..nav_budget)
for _,target in ipairs(player_walls) do
    local front=attacking(target)
    assert(#front==4,'stable four-player fronts lost an attacking contact')
    local victim=front[2]
    victim.dead=true;victim.ai:OnDeath({unit=victim})
    assert(victim:GetHullRadius()==victim.nominal and #victim.hull_writes==0,
        'death callback must preserve the original hull without a setter')
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
    assert(#u.hull_writes==0 and u.corrections==0,
        'retarget/destroy must never resize or reposition a native crowd body')
    assert(not u.ai.contact_locked and u.force==nil,'retarget/destroy must release native contact state')
end
print('WALL_FOUR_FACES_PASS concurrent_contacts=16 players=4 crowd_units=360 local_death_replacements='..replacements
    ..' stable_orders=0 stable_position_writes=0 stable_paths=0')
