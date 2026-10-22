-- Exercise the real enemy-wall FSM; its geometry/route services are faked so
-- a same-entity wall move can be inspected before a new geometry is selected.
package.path="scripts/vscripts/?.lua;"..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 0} end
IsServer=function() return true end
LinkLuaModifier=function() end
class=function(t) return t end
DOTA_UNIT_CAP_MELEE_ATTACK,DOTA_UNIT_CAP_RANGED_ATTACK=1,2
DOTA_TEAM_BADGUYS=3
DOTA_UNIT_ORDER_ATTACK_TARGET,DOTA_UNIT_ORDER_MOVE_TO_POSITION=2,3
MODIFIER_STATE_ROOTED,MODIFIER_STATE_DISARMED,MODIFIER_STATE_NO_UNIT_COLLISION=4,5,6
local clock,entities,plan=0,{},nil
local releases,range_resets,stationary_releases=0,0,0
local expect_clean_boundary=false
GameRules={GetGameTime=function() return clock end}
EntIndexToHScript=function(index) return entities[index] end
package.loaded["core/team_alignment"]={are_enemies=function() return true end,enforce=function() end}
package.loaded["systems/enemy_attack_observer"]={is_ready=function() return false end}
package.loaded["systems/wall_target_service"]={resolve=function(_,_,current,cache)
    return current,cache or {generation=0}
end}
package.loaded["systems/wall_navigation_service"]={
    enforce_boundary=function(_,_,previous)
        if expect_clean_boundary then
            assert(previous==nil,"a moved same-ID wall must not inherit an old boundary chord")
            expect_clean_boundary=false
        end
        return false
    end,
}
package.loaded["systems/wall_melee_contact"]={
    release=function() releases=releases+1 end,
    resolve=function() return plan end,
    attack_range=function() return 210 end,
    arrived=function(_,parent,point) return parent.p.x==point.x and parent.p.y==point.y end,
    settle=function(_,parent,point)
        return parent.p.x==point.x and parent.p.y==point.y
    end,
}
package.loaded["systems/enemy_ranged_stationary"]={
    observe=function() end,
    owns_root=function(owner) return owner.contact_mode==6 and owner.ranged_stationary_hold~=nil end,
    release=function(owner)
        stationary_releases=stationary_releases+1
        owner.ranged_stationary_hold=nil
        owner:SetContactMode(0)
    end,
}
ExecuteOrderFromTable=function(order)
    local parent=assert(entities[order.UnitIndex]);parent.orders=parent.orders+1
    parent.last_order=order
end
local ai=require("modifiers/modifier_enemy_wall_ai")
local wall={index=1,p=Vector(0,0,384),survival_wall_relocation_revision=0}
function wall:entindex() return self.index end
function wall:IsNull() return false end
function wall:IsAlive() return true end
function wall:GetAbsOrigin() return self.p end
entities[1]=wall
local function make_parent(index,capability)
    local parent={p=Vector(-184,-24,384),orders=0,stops=0,capability=capability}
    function parent:entindex() return index end
    function parent:IsNull() return false end
    function parent:IsAlive() return true end
    function parent:GetAbsOrigin() return self.p end
    function parent:GetTeamNumber() return 3 end
    function parent:GetAttackCapability() return self.capability end
    function parent:Script_GetAttackRange()
        return (self.capability==1 and 128 or 550)+(self.ai.contact_range_delta or 0)
    end
    function parent:GetForceAttackTarget() return self.force end
    function parent:SetForceAttackTarget(target) self.force=target end
    function parent:GetAttacksPerSecond() return 1 end
    function parent:IsIdle() return false end
    function parent:IsStunned() return self.stunned==true end
    function parent:IsRooted() return self.ai.contact_locked or self.ai.contact_mode==6 end
    function parent:IsDisarmed() return self.ai.contact_waiting end
    function parent:Stop() self.stops=self.stops+1 end
    local owner=setmetatable({GetParent=function() return parent end,StartIntervalThink=function(self,seconds)
        self.think_interval=seconds
    end,SendBuffRefreshToClients=function(self)
        if self.contact_range_delta==0 then range_resets=range_resets+1 end
    end},{__index=ai})
    parent.ai=owner;entities[index]=parent;owner:OnCreated({wall_entindex=1})
    return parent,owner
end
local function tick(owner)
    clock=clock+.5;owner:OnIntervalThink()
    if owner.phase_order_frame then clock=clock+1/30;owner:OnIntervalThink() end
end
local function seed_stale_queue(owner)
    owner.boundary_position=Vector(-184,-24,384)
    owner.retreat_failure={until_time=999}
    owner.retreat_goal_safe=true
    owner.retreat_check_after=999
    owner.retreat_extend_after=999
end
local function assert_cleaned(parent,owner,before_stops,before_orders)
    assert(owner.wall_entindex==1 and owner.goal_wall==wall,"identity and current wall target must be preserved")
    assert(owner.ai_state=="chase" and owner.contact_mode==0 and not owner.contact_locked)
    assert(owner.contact_range_delta==0 and owner.contact_move==nil)
    assert(owner.retreat_failure==nil and owner.retreat_goal_safe==nil
        and owner.retreat_check_after==nil and owner.retreat_extend_after==nil)
    assert(owner.wait_face==nil and owner.wait_radius==nil and owner.wait_envelope==nil)
    assert(parent.stops==before_stops+1,"cancel the obsolete same-wall goal once")
    assert(parent.orders==before_orders+1 and parent.last_order.TargetIndex==1)
    assert(owner.goal_wall_revision==wall.survival_wall_relocation_revision)
    assert(owner.think_interval==.5,"wall movement must reuse the existing half-second observation")
    local stops,orders=parent.stops,parent.orders
    for _=1,12 do owner:OnAttackStart({attacker=parent,target=wall});tick(owner) end
    assert(parent.stops==stops and parent.orders==orders,"stable revision must not Stop or reissue native attacks")
end

-- A completed front attack has a real root and contact-range bonus.
local parent,owner=make_parent(2,1)
plan={point=parent.p,claimed=true};tick(owner)
assert(owner.ai_state=="attack" and owner.contact_locked and owner.contact_range_delta==82)
local before_stops,before_orders=parent.stops,parent.orders
local before_releases=releases
seed_stale_queue(owner)
wall.p=Vector(1000,0,384);wall.survival_wall_relocation_revision=1;plan=nil
expect_clean_boundary=true;tick(owner)
assert(not expect_clean_boundary and releases==before_releases+1 and range_resets>0)
assert_cleaned(parent,owner,before_stops,before_orders)

-- Same-ID notifications without an actual move remain idempotent.
before_stops,before_orders=parent.stops,parent.orders
owner:SetWallEntIndex(1)
assert(parent.stops==before_stops and parent.orders==before_orders)

-- A retained retreat must discard its old rear point and delayed phase MOVE.
local rear,rear_owner=make_parent(3,1)
wall.p=Vector(0,0,384)
local rear_plan={point=Vector(-280,-24,384),claimed=false,wait_face=1,
    wait_envelope=208,wait_radius=32,waiting_blocked=false,wait_retreat=true}
rear_owner:EnterState("retreat",rear,wall,rear_plan.point,rear_plan)
assert(rear_owner.phase_order_frame and rear_owner.contact_mode==4)
seed_stale_queue(rear_owner)
before_stops,before_orders=rear.stops,rear.orders
wall.p=Vector(1000,0,384);wall.survival_wall_relocation_revision=2;plan=nil
expect_clean_boundary=true;tick(rear_owner)
assert(not expect_clean_boundary and not rear_owner.phase_order_frame)
assert_cleaned(rear,rear_owner,before_stops,before_orders)

-- Release even an optional ranged stationary root before resuming the same
-- wall's new location. No stationary subsystem scan or extra timer is added.
local ranged,ranged_owner=make_parent(4,2)
plan=nil;tick(ranged_owner)
assert(ranged_owner.ai_state=="chase")
ranged_owner.ranged_stationary_hold={}
ranged_owner:SetContactMode(6)
seed_stale_queue(ranged_owner)
before_stops,before_orders=ranged.stops,ranged.orders
local released_before=stationary_releases
wall.p=Vector(1500,0,384);wall.survival_wall_relocation_revision=3
expect_clean_boundary=true;tick(ranged_owner)
assert(stationary_releases==released_before+1 and ranged_owner.ranged_stationary_hold==nil)
assert(not expect_clean_boundary and ranged:Script_GetAttackRange()==550)
assert_cleaned(ranged,ranged_owner,before_stops,before_orders)

-- Formal-wave external controls keep their priority; the pending wall move
-- is observed once control ends, using the same existing think callback.
wall.p=Vector(0,0,384)
local controlled,controlled_owner=make_parent(5,1)
controlled_owner.wall_target_player_id=0
plan={point=controlled.p,claimed=true};tick(controlled_owner)
assert(controlled_owner.contact_locked)
before_stops,before_orders=controlled.stops,controlled.orders
controlled.stunned=true
wall.p=Vector(1000,0,384);wall.survival_wall_relocation_revision=4;plan=nil
tick(controlled_owner)
assert(controlled.stops==before_stops and controlled.orders==before_orders,
    "a wall move must not issue Stop/attack orders through external stun")
controlled.stunned=false
expect_clean_boundary=true;tick(controlled_owner)
assert(not expect_clean_boundary)
assert_cleaned(controlled,controlled_owner,before_stops,before_orders)
-- A rear vacancy can change a waiting unit's destination without changing
-- the front envelope, face, radius or wall entity. The old FSM ignored that
-- change forever. A stable reservation must still avoid repeated MOVE orders.
local queued,queued_owner=make_parent(6,1)
plan={point=Vector(-300,-24,384),claimed=false,wait_face=1,
    wait_envelope=226,wait_radius=32,waiting_blocked=false,wait_retreat=false,
    wait_queue_key="-300:-24"}
tick(queued_owner)
assert(queued_owner.ai_state=="waiting" and queued.orders==1)
for _=1,10 do tick(queued_owner) end
assert(queued.orders==1,"a stable queue reservation must not reissue MOVE")
plan={point=Vector(-388,64,384),claimed=false,wait_face=1,
    wait_envelope=226,wait_radius=32,waiting_blocked=false,wait_retreat=false,
    wait_queue_key="-388:64"}
tick(queued_owner)
assert(queued.orders==2 and queued.last_order.Position==plan.point,
    "a new reserved rear goal must update the native MOVE exactly once")
for _=1,10 do tick(queued_owner) end
assert(queued.orders==2 and not queued_owner.contact_locked,
    "rear reassignment must keep normal collision and stable orders")
print("WALL_RELOCATION_AI_PASS same-entity revision resets melee root/range/boundary/retreat and ranged hold; external control priority; stable revisions preserve native attacks and half-second cadence; rear reservation changes issue one MOVE")
