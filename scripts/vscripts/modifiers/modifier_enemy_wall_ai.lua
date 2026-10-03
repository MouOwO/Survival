if LinkLuaModifier then
    LinkLuaModifier("modifier_enemy_wall_ai", "modifiers/modifier_enemy_wall_ai", LUA_MODIFIER_MOTION_NONE)
end
modifier_enemy_wall_ai = class({})
_G.modifier_enemy_wall_ai = modifier_enemy_wall_ai
local M = modifier_enemy_wall_ai
local team_alignment = require("core/team_alignment")
local contact = require("systems/wall_melee_contact")
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

local function now()
    return GameRules and GameRules:GetGameTime() or 0
end
local function same_point(a,b)
    return a and b and a.x==b.x and a.y==b.y
end
local function distance_squared(a,b)
    local x,y=a.x-b.x,a.y-b.y
    return x*x+y*y
end
local function interrupted(parent)
    return (parent.IsStunned and parent:IsStunned())
        or (parent.IsCommandRestricted and parent:IsCommandRestricted())
end
function M:DeclareFunctions()
    return { MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_ATTACK_LANDED,
        MODIFIER_EVENT_ON_DEATH, MODIFIER_PROPERTY_ATTACK_RANGE_BONUS }
end
function M:OnAttackStart(params)
    if not IsServer() or params.attacker~=self:GetParent() then return end
    if params.target and params.target:entindex()==self.wall_entindex then
        self.last_attack_activity=now()
        self.recovery_delay=3
        self.order_pending=false
    end
end
function M:OnDeath(params)
    if not IsServer() then return end
    local parent=self:GetParent()
    if params.unit==parent then
        contact.release(self.wall_entindex,parent:entindex())
    elseif params.unit and params.unit:entindex()==self.wall_entindex then
        self:SetWallEntIndex(-1)
    end
end
function M:GetModifierAttackRangeBonus() return self.contact_range_delta or 0 end
function M:AddCustomTransmitterData() return {contact_range_delta=self.contact_range_delta or 0} end
function M:HandleCustomTransmitterData(data) self.contact_range_delta=tonumber(data.contact_range_delta) or 0 end
function M:OnAttackLanded(params)
    if not IsServer() then return end
    self:OnAttackStart(params) -- Missed attack-start notifications still count as progress.
    local parent, wall = self:GetParent(), params.target
    if params.attacker ~= parent or parent.survival_is_wave_monster ~= true
        or parent.survival_is_boss ~= true or not wall or wall:IsNull()
        or wall:entindex() ~= self.wall_entindex then return end
    local player_id = tonumber(wall.survival_player_id)
    if player_id == nil and wall.GetPlayerOwnerID then player_id = wall:GetPlayerOwnerID() end
    if player_id == nil or player_id < 0 then player_id = parent.survival_player_id end
    local duration = require("systems/permanent_reward_effect_service").value(player_id, "wall_wave_boss_stun_seconds")
    if duration > 0 then parent:AddNewModifier(wall, nil, "modifier_stunned", {duration=duration}) end
end

function M:OnCreated(params)
    self.no_unit_collision = tonumber(params.no_unit_collision) == 1
    if not IsServer() then return end
    self.contact_range_delta = 0
    if self.SetHasCustomTransmitterData then self:SetHasCustomTransmitterData(true) end
    self.wall_entindex = tonumber(params.wall_entindex) or -1
    self.ai_state="idle"
    -- Let the spawn caller finish FindClearSpaceForUnit, then issue the first
    -- goal on the next server frame instead of waiting half a second.
    self.first_observation = true
    self:StartIntervalThink(0)
end

function M:CheckState()
    local state = {}
    if self.no_unit_collision then state[MODIFIER_STATE_NO_UNIT_COLLISION] = true end
    local mode=self.GetStackCount and self:GetStackCount() or
        (self.contact_locked and 2 or (self.contact_waiting and 1 or 0))
    if mode==1 then state[MODIFIER_STATE_DISARMED] = true end
    if mode==2 then state[MODIFIER_STATE_ROOTED] = true end
    return state
end

function M:UpdateContactRange(parent, wall)
    local delta=0
    if wall and parent.GetAttackCapability
        and parent:GetAttackCapability() == DOTA_UNIT_CAP_MELEE_ATTACK then
        local getter=parent.Script_GetAttackRange or parent.GetAttackRange
        if getter then
            local base=getter(parent)-(self.contact_range_delta or 0)
            delta=contact.attack_range(parent,wall)-base
        end
    end
    if delta ~= (self.contact_range_delta or 0) then
        self.contact_range_delta=delta
        if self.SendBuffRefreshToClients then self:SendBuffRefreshToClients() end
    end
end

-- Each modifier owns its state and goal. Only entries/goal changes issue an
-- order. In particular, a transient nil attack target is not an idle state.
function M:SetContactMode(mode)
    local changed=self.contact_waiting~=(mode==1) or self.contact_locked~=(mode==2)
    self.contact_waiting,self.contact_locked=mode==1,mode==2
    if changed and self.SetStackCount then
        self:SetStackCount(mode)
        if self.ForceRefresh then self:ForceRefresh() end
    end
end

function M:SetWallEntIndex(entindex)
    local next_index=tonumber(entindex) or -1
    if next_index==self.wall_entindex then return end
    local parent=self:GetParent()
    local previous=self.wall_entindex
    self.wall_entindex=next_index
    if not parent or parent:IsNull() then return end
    contact.release(previous,parent:entindex())
    self:SetContactMode(0)
    self:UpdateContactRange(parent,false)
    self.ai_state="idle"
    self.contact_move,self.order_pending,self.last_attack_activity=nil,false,nil
    self.goal_wall=nil
    if not parent.GetForceAttackTarget or parent:GetForceAttackTarget()~=nil then
        parent:SetForceAttackTarget(nil)
    end
    -- Cancel an obsolete goal once, never on repeated no-target notifications.
    if parent.Stop then parent:Stop() end
end

function M:IssueStateOrder(parent,wall)
    if interrupted(parent) then self.order_pending=true;return end
    local attacking=self.ai_state=="attack" or self.ai_state=="chase"
    if attacking then
        if parent.IsDisarmed and parent:IsDisarmed() then self.order_pending=true;return end
        if wall.IsInvulnerable and wall:IsInvulnerable() then self.order_pending=true;return end
        if not parent.GetForceAttackTarget or parent:GetForceAttackTarget()~=wall then
            parent:SetForceAttackTarget(wall)
        end
        ExecuteOrderFromTable({UnitIndex=parent:entindex(),OrderType=DOTA_UNIT_ORDER_ATTACK_TARGET,
            TargetIndex=wall:entindex(),Queue=false})
    else
        if not parent.GetForceAttackTarget or parent:GetForceAttackTarget()~=nil then
            parent:SetForceAttackTarget(nil)
        end
        ExecuteOrderFromTable({UnitIndex=parent:entindex(),OrderType=DOTA_UNIT_ORDER_MOVE_TO_POSITION,
            Position=self.contact_move,Queue=false})
    end
    self.order_pending=false
    self.last_order_time=now()
end

function M:EnterState(state,parent,wall,point)
    if self.ai_state==state and self.goal_wall==wall then
        -- Overflow keeps its original local approach until a contact is free.
        -- Re-sorting the nearest occupied point must not redirect it each tick.
        if state=="waiting" or state=="attack" or state=="chase"
            or same_point(point,self.contact_move) then return false end
    end
    local previous=self.ai_state
    self.ai_state,self.goal_wall=state,wall
    self.contact_move=point
    self.last_attack_activity=nil
    self.progress_position=parent:GetAbsOrigin()
    self.last_progress_time=now()
    self.recovery_delay=3
    self.recovery_after=nil
    local mode=state=="attack" and 2 or ((state=="approach" or state=="waiting") and 1 or 0)
    self:SetContactMode(mode)
    self:UpdateContactRange(parent,state=="attack" and wall or false)
    -- Cancel the old move exactly once at arrival. Previously this Stop was
    -- repeated on every think whenever the engine briefly hid its attack target.
    if state=="attack" and (previous=="approach" or previous=="waiting") then parent:Stop() end
    self:IssueStateOrder(parent,wall)
    return true
end

function M:MonitorState(parent,wall)
    local stamp=now()
    -- Keep contact reach valid if an external range buff/debuff changes, without
    -- touching the current attack order or refreshing unchanged properties.
    if self.ai_state=="attack" then self:UpdateContactRange(parent,wall) end
    if interrupted(parent) or ((self.ai_state=="attack" or self.ai_state=="chase")
        and parent.IsDisarmed and parent:IsDisarmed()) then
        self.last_progress_time=stamp
        self.recovery_after=stamp+3
        return
    end
    if self.order_pending then self:IssueStateOrder(parent,wall);return end
    -- Native movement waits on unit collision. Never keep reissuing an approach
    -- to an occupied front. Receiving a free contact is the wake-up transition.
    if self.ai_state=="waiting" then return end
    local p=parent:GetAbsOrigin()
    if not self.progress_position or distance_squared(p,self.progress_position)>=64 then
        self.progress_position=p
        self.last_progress_time=stamp
        self.recovery_delay=3
    end
    local attacking=self.ai_state=="attack"
    local latest=math.max(self.last_order_time or stamp,self.last_progress_time or stamp,
        self.last_attack_activity or 0)
    local grace=self.recovery_delay or 3
    local rate=parent.GetAttacksPerSecond and parent:GetAttacksPerSecond(false)
    if rate and rate>0 then grace=math.max(grace,2/rate+0.5) end
    if stamp-latest<grace or stamp<(self.recovery_after or 0) then return end
    -- Recovery is exceptional, with backoff. Normal windup/cooldown/backswing
    -- events continually renew activity and never trigger Stop or another order.
    if not attacking and (not parent.IsIdle or not parent:IsIdle()) then return end
    if wall.IsInvulnerable and wall:IsInvulnerable() then return end
    self:IssueStateOrder(parent,wall)
    self.recovery_delay=math.min(12,grace*2)
end

function M:OnIntervalThink()
    if not IsServer() then return end
    if self.first_observation then
        self.first_observation = false
        self:StartIntervalThink(0.5) -- Observe state; never reissue orders on a timer.
    end
    local parent = self:GetParent()
    if not parent or parent:IsNull() or not parent:IsAlive() then return end

    if self.wall_entindex < 0 then return end

    local wall = EntIndexToHScript(self.wall_entindex)
    if not wall or wall:IsNull() or not wall:IsAlive() then
        self:SetWallEntIndex(-1)
        return
    end

    if not parent.GetTeamNumber or parent:GetTeamNumber()~=DOTA_TEAM_BADGUYS then
        team_alignment.enforce(parent, DOTA_TEAM_BADGUYS, "wave_enemy_ai")
    end
    if not team_alignment.are_enemies(parent, wall) then
        team_alignment.enforce(wall, DOTA_TEAM_GOODGUYS, "wall_target")
    end
    if not team_alignment.are_enemies(parent, wall) then return end

    local desired,point="chase",nil
    local ground=(parent.survival_wave_movement_type or parent.survival_movement_type or "ground") == "ground"
    local melee=parent.GetAttackCapability and parent:GetAttackCapability()==DOTA_UNIT_CAP_MELEE_ATTACK
    if ground and melee then
        local plan=contact.resolve(wall,parent)
        if plan then
            point=plan.point
            local p,w=parent:GetAbsOrigin(),wall:GetAbsOrigin()
            local dx,dy=math.abs(p.x-point.x),math.abs(p.y-point.y)
            local x_face=math.abs(point.x-w.x)>math.abs(point.y-w.y)
            local normal_error,lateral_error=x_face and dx or dy,x_face and dy or dx
            local retained=self.ai_state=="attack" and self.goal_wall==wall
            -- Small exit hysteresis prevents terrain/collision rounding from
            -- oscillating a settled unit between rooted and disarmed states.
            local arrived=normal_error<=(retained and 60 or 56)
                and lateral_error<=20
            desired=not plan.claimed and "waiting" or (arrived and "attack" or "approach")
        end
    else
        contact.release(self.wall_entindex,parent:entindex())
    end
    if not self:EnterState(desired,parent,wall,point) then self:MonitorState(parent,wall) end
end

function M:OnDestroy()
    if not IsServer() then return end
    local parent = self:GetParent()
    if parent and not parent:IsNull() then
        contact.release(self.wall_entindex,parent:entindex())
        self:UpdateContactRange(parent,false)
        parent:SetForceAttackTarget(nil)
    end
end

return M
