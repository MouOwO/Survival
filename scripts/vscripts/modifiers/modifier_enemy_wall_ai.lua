if LinkLuaModifier then
    LinkLuaModifier("modifier_enemy_wall_ai", "modifiers/modifier_enemy_wall_ai", LUA_MODIFIER_MOTION_NONE)
end
modifier_enemy_wall_ai = class({})
_G.modifier_enemy_wall_ai = modifier_enemy_wall_ai
local M = modifier_enemy_wall_ai
local team_alignment = require("core/team_alignment")
local contact = require("systems/wall_melee_contact")
local navigation = require("systems/wall_navigation_service")
local attack_observer = require("systems/enemy_attack_observer")
local wall_targets = require("systems/wall_target_service")
local ranged_stationary = require("systems/enemy_ranged_stationary")
local wave_attack_rules = require("systems/wave_attack_rules")
local function shared_death_ready()
    return type(attack_observer.can_route_death)=='function' and type(attack_observer.register_death)=='function'
        and type(attack_observer.bind_death_wall)=='function' and type(attack_observer.unregister_death)=='function'
        and attack_observer.can_route_death()
end
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
local function target_controlled(self,parent)
    return interrupted(parent)
        or (parent.IsRooted and parent:IsRooted() and not self.contact_locked
            and not (self.ranged_stationary_hold and ranged_stationary.owns_root(self)))
        or (parent.IsCurrentlyHorizontalMotionControlled and parent:IsCurrentlyHorizontalMotionControlled())
        or (parent.IsCurrentlyVerticalMotionControlled and parent:IsCurrentlyVerticalMotionControlled())
end
local function same_wait_geometry(a,b)
    return b and a.wait_face==b.wait_face and a.wait_envelope==b.wait_envelope
        and a.wait_radius==b.wait_radius and a.wait_queue_key==b.wait_queue_key
end
local function movement_controlled(parent)
    return interrupted(parent) or (parent.IsRooted and parent:IsRooted())
        or (parent.IsCurrentlyHorizontalMotionControlled and parent:IsCurrentlyHorizontalMotionControlled())
        or (parent.IsCurrentlyVerticalMotionControlled and parent:IsCurrentlyVerticalMotionControlled())
end
local function uses_contact_range_property(self)
    if self.contact_range_property_enabled == nil then
        -- DeclareFunctions can run before OnCreated. Only a completed formal
        -- spawn may opt out; old/unknown instances and clients retain the
        -- original property. Server-only entity fields are not replicated.
        local enabled = true
        if self.contact_range_delta == nil and self.ai_state == nil
            and IsServer() and type(self.GetParent) == "function" then
            local ok, parent = pcall(self.GetParent, self)
            if ok and parent and (not parent.IsNull or not parent:IsNull()) then
                enabled = not (parent.survival_is_wave_monster == true
                    and parent.survival_wave_skip_contact_range_bonus == true)
            end
        end
        -- Never let ForceRefresh or a later classification change alter an
        -- engine-cached declaration. New attack types need a new instance.
        self.contact_range_property_enabled = enabled
    end
    return self.contact_range_property_enabled
end
function M:DeclareFunctions()
    local functions
    if self.shared_attack_observer ~= false and attack_observer.is_ready() then
        functions = {}
    else
        functions = { MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_ATTACK_LANDED,
            }
    end
    local death_shared=self.shared_death_observer
    if death_shared==nil then death_shared=shared_death_ready() end
    if not death_shared then functions[#functions+1]=MODIFIER_EVENT_ON_DEATH end
    if uses_contact_range_property(self) then
        functions[#functions + 1] = MODIFIER_PROPERTY_ATTACK_RANGE_BONUS
    end
    return functions
end
function M:OnAttackStart(params)
    if self.shared_attack_observer then return end
    return self:HandleAttackStart(params)
end
function M:ObserveRangedStationary(parent,wall,event,params)
    if not self.ranged_stationary_hold and _G.SURVIVAL_RANGED_STATIONARY_PROBE~=true then return end
    if type(ranged_stationary.observe)=="function" then ranged_stationary.observe(self,parent,wall,event,params) end
end
function M:ReleaseRangedStationary(reason)
    if self.ranged_stationary_hold and type(ranged_stationary.release)=="function" then
        ranged_stationary.release(self,self:GetParent(),reason)
    end
end
function M:HandleAttackStart(params,observed_event)
    if not IsServer() or not params or params.attacker~=self:GetParent() then return end
    local parent = self:GetParent()
    if params.target and not wave_attack_rules.can_attack(parent, params.target) then
        -- Native retaliation can replace an explicit wall goal. Cancel only
        -- this illegal attack; the normal AI resumes its wall/movement order.
        self:ReleaseRangedStationary("target_changed")
        parent:SetForceAttackTarget(nil)
        if parent.Stop then parent:Stop() end
        self.order_pending = true
        return
    end
    if params.target and params.target:entindex()==self.wall_entindex then
        self.last_attack_activity=now()
        self.recovery_delay=3
        self.order_pending=false
    end
    self:ObserveRangedStationary(self:GetParent(),params.target,observed_event or "start",params)
end
function M:HandleAttackFired(params)
    if not IsServer() or not params or params.attacker~=self:GetParent() then return end
    if params.target and params.target:entindex()==self.wall_entindex then
        self.last_attack_activity=now()
        self.recovery_delay=3
        self.order_pending=false
    end
    self:ObserveRangedStationary(self:GetParent(),params.target,"fired",params)
end
function M:OnDeath(params)
    if self.shared_death_observer then return end
    return self:HandleDeath(params)
end
function M:HandleDeath(params)
    if not IsServer() then return end
    local parent=self:GetParent()
    if params.unit==parent then
        self:ReleaseRangedStationary("unit_dead")
        contact.release(self.wall_entindex,parent:entindex())
    elseif params.unit and params.unit:entindex()==self.wall_entindex then
        self:ReleaseRangedStationary("target_changed")
        if self.wall_target_player_id ~= nil and self.wall_target_player_id >= 0 then
            self:InvalidateWallTarget()
            self:RefreshWallTarget(parent,true)
        else self:SetWallEntIndex(-1) end
    end
end
function M:GetModifierAttackRangeBonus() return self.contact_range_delta or 0 end
function M:AddCustomTransmitterData() return {contact_range_delta=self.contact_range_delta or 0} end
function M:HandleCustomTransmitterData(data) self.contact_range_delta=tonumber(data.contact_range_delta) or 0 end
function M:OnAttackLanded(params)
    if self.shared_attack_observer then return end
    return self:HandleAttackLanded(params)
end
function M:HandleAttackLanded(params)
    if not IsServer() or not params then return end
    self:HandleAttackStart(params,"landed") -- Missed attack-start notifications still count as progress.
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
    uses_contact_range_property(self)
    -- Wall attackers never bypass living bodies, including old challenge
    -- callers that still send the former no_unit_collision spawn parameter.
    self.no_unit_collision = false
    if not IsServer() then return end
    local parent = self:GetParent()
    if parent.survival_is_wave_monster == true then
        -- Explicit wall orders still work with native idle acquisition off.
        if parent.SetIdleAcquire then parent:SetIdleAcquire(false) end
        if parent.SetAcquisitionRange then parent:SetAcquisitionRange(0) end
    end
    self:GetParent().survival_wall_contact_owner=self
    self.shared_attack_observer = attack_observer.is_ready() and true or false
    if self.shared_attack_observer then self:GetParent().survival_enemy_attack_owner = self end
    self.contact_range_delta = 0
    if self.SetHasCustomTransmitterData then self:SetHasCustomTransmitterData(true) end
    self.wall_entindex = tonumber(params.wall_entindex) or -1
    self.wall_target_player_id = tonumber(params.wall_target_player_id)
    self.wall_target_cache = nil
    self.shared_death_observer=false
    if shared_death_ready() then
        local wall=self.wall_entindex>=0 and EntIndexToHScript(self.wall_entindex) or nil
        self.shared_death_observer=attack_observer.register_death(self:GetParent(),self,wall) and true or false
        if self.shared_death_observer then self.death_wall_handle=wall end
    end
    self.boundary_position=nil
    self.ai_state="idle"
    -- Let the spawn caller finish FindClearSpaceForUnit, then issue the first
    -- goal on the next server frame instead of waiting half a second.
    self.first_observation = true
    self:StartIntervalThink(0)
end

-- State refreshes must never reinitialize the target, timers or attack clock.
function M:OnRefresh()
    -- Old native instances keep their original callback path until respawn.
    -- Do not register an engine-cached callback a second time during refresh.
    if IsServer() and self.shared_attack_observer == nil then self.shared_attack_observer = false end
    if IsServer() and self.shared_death_observer == nil then self.shared_death_observer = false end
    if self.contact_range_property_enabled == nil then self.contact_range_property_enabled = true end
end

function M:CheckState()
    local state = {}
    local mode=self.GetStackCount and self:GetStackCount() or
        (self.contact_locked and 2 or (self.contact_advancing and 3 or (self.contact_waiting and 1 or 0)))
    -- Approach and retreat are ordinary native movement. A reserved empty
    -- contact never grants permission to pass through a living front body.
    if mode==1 or mode==3 or mode==4 or mode==5 then state[MODIFIER_STATE_DISARMED] = true end
    -- Mode 6 owns only stationary ranged rooting. It adds neither phasing nor
    -- disarm and is replicated by the same native stack as the contact modes.
    if mode==2 or mode==6 then state[MODIFIER_STATE_ROOTED] = true end
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
    local changed=self.contact_mode~=mode
    self.contact_mode=mode
    self.contact_waiting,self.contact_locked,self.contact_advancing=(mode==1 or mode==3 or mode==4 or mode==5),mode==2,mode==3
    if changed and self.SetStackCount then
        self:SetStackCount(mode)
        if self.ForceRefresh then self:ForceRefresh() end
    end
end

function M:SetWallEntIndex(entindex,reset_position)
    local next_index=tonumber(entindex) or -1
    if next_index==self.wall_entindex and not reset_position then return end
    self:ReleaseRangedStationary("target_changed")
    local parent=self:GetParent()
    local previous=self.wall_entindex
    self.wall_entindex=next_index
    if self.shared_death_observer then
        local wall=next_index>=0 and EntIndexToHScript(next_index) or nil
        attack_observer.bind_death_wall(self,wall);self.death_wall_handle=wall
    end
    self.boundary_position=nil
    if self.phase_order_frame then
        self.phase_order_frame=nil
        self:StartIntervalThink(0.5)
    end
    if not parent or parent:IsNull() then return end
    contact.release(previous,parent:entindex())
    self:SetContactMode(0)
    self:UpdateContactRange(parent,false)
    self.ai_state="idle"
    self.contact_move,self.order_pending,self.last_attack_activity=nil,false,nil
    self.goal_wall=nil
    self.goal_wall_revision=nil
    self.wait_blocked,self.wait_face,self.wait_envelope,self.wait_radius=nil,nil,nil,nil
    self.wait_queue_key=nil
    self.retreat_failure,self.retreat_goal_safe,self.retreat_check_after,self.retreat_extend_after=nil,nil,nil,nil
    if not parent.GetForceAttackTarget or parent:GetForceAttackTarget()~=nil then
        parent:SetForceAttackTarget(nil)
    end
    -- Cancel an obsolete goal once, never on repeated no-target notifications.
    if parent.Stop then parent:Stop() end
end

function M:InvalidateWallTarget()
    if self.wall_target_player_id ~= nil then self.wall_target_cache = nil end
end

function M:RefreshWallTarget(parent,retry)
    if self.wall_target_player_id == nil or self.wall_target_player_id < 0
        or type(wall_targets.resolve) ~= "function" then return false end
    -- Contact rooting belongs to this AI. External control must finish before
    -- a target change can release its goal or issue a native Stop.
    if target_controlled(self,parent) then return false end
    local previous_generation=self.wall_target_cache and self.wall_target_cache.generation
    local next_index,cache=wall_targets.resolve(parent,self.wall_target_player_id,
        self.wall_entindex,self.wall_target_cache,retry)
    self.wall_target_cache=cache
    if retry or previous_generation~=cache.generation then self.wall_target_retry_after=now()+4 end
    if next_index==self.wall_entindex then return false end
    self:SetWallEntIndex(next_index)
    return true
end

function M:IssueStateOrder(parent,wall)
    self:ReleaseRangedStationary("recovery_order")
    if interrupted(parent) then self.order_pending=true;return end
    local attacking=self.ai_state=="attack" or self.ai_state=="chase"
    if not attacking and movement_controlled(parent) then self.order_pending=true;return end
    if attacking then
        if parent.IsDisarmed and parent:IsDisarmed() then self.order_pending=true;return end
        if wall.IsInvulnerable and wall:IsInvulnerable() then self.order_pending=true;return end
        if not parent.GetForceAttackTarget or parent:GetForceAttackTarget()~=wall then
            parent:SetForceAttackTarget(wall)
        end
        ExecuteOrderFromTable({UnitIndex=parent:entindex(),OrderType=DOTA_UNIT_ORDER_ATTACK_TARGET,
            TargetIndex=wall:entindex(),Queue=false})
    else
        -- The native getter can be nil while an attack order is still active.
        -- Clear explicitly on a real move transition, never on stable ticks.
        parent:SetForceAttackTarget(nil)
        ExecuteOrderFromTable({UnitIndex=parent:entindex(),OrderType=DOTA_UNIT_ORDER_MOVE_TO_POSITION,
            Position=self.contact_move,Queue=false})
    end
    self.order_pending=false
    self.last_order_time=now()
end

function M:EnterState(state,parent,wall,point,plan)
    if self.shared_death_observer and self.death_wall_handle~=wall then
        attack_observer.bind_death_wall(self,wall);self.death_wall_handle=wall
    end
    -- Finish a retreat at its selected rear goal, rather than immediately
    -- ordering a move back toward the compact queue and into the front again.
    if state=="waiting" and self.ai_state=="retreat" and self.goal_wall==wall
        and plan and same_wait_geometry(self,plan) then
        point=self.contact_move
    end
    if self.ai_state==state and self.goal_wall==wall then
        if state=="waiting" then
            -- A reserved rear position stays stable between observations.
            -- Its key changes only when a real vacancy or geometry change
            -- assigns a new destination; issue that MOVE exactly once.
            local blocked=plan and plan.waiting_blocked
            local face=plan and plan.wait_face
            local envelope=plan and plan.wait_envelope
            local radius=plan and plan.wait_radius
            if self.wait_blocked==blocked and self.wait_face==face
                and self.wait_envelope==envelope and self.wait_radius==radius
                and self.wait_queue_key==(plan and plan.wait_queue_key) then return false end
        elseif state=="attack" or state=="chase"
            or (same_point(point,self.contact_move) and (state~="retreat" or same_wait_geometry(self,plan))) then return false end
    end
    local previous=self.ai_state
    self:ReleaseRangedStationary("state_changed")
    self.ai_state,self.goal_wall=state,wall
    self.goal_wall_revision=tonumber(wall.survival_wall_relocation_revision) or 0
    self.contact_move=point
    if (state=="waiting" or state=="retreat") and plan then
        self.wait_blocked,self.wait_face=plan.waiting_blocked,plan.wait_face
        self.wait_envelope,self.wait_radius=plan.wait_envelope,plan.wait_radius
        self.wait_queue_key=plan.wait_queue_key
    else
        self.wait_blocked,self.wait_face,self.wait_envelope,self.wait_radius=nil,nil,nil,nil
        self.wait_queue_key=nil
    end
    self.last_attack_activity=nil
    self.progress_position=parent:GetAbsOrigin()
    self.last_progress_time=now()
    self.recovery_delay=3
    self.recovery_after=nil
    self.approach_retry_done=false
    if state=="retreat" then
        self.retreat_failure=nil
        self.retreat_goal_safe=true
        self.retreat_check_after=now()+2
    else
        self.retreat_goal_safe,self.retreat_check_after,self.retreat_extend_after=nil,nil,nil
    end
    local mode=state=="attack" and 2 or (state=="approach" and 3 or (state=="retreat" and 4
        or (state=="route" and 5 or (state=="waiting" and 1 or 0))))
    self:SetContactMode(mode)
    self:UpdateContactRange(parent,state=="attack" and wall or false)
    -- Cancel the old move exactly once at arrival. Previously this Stop was
    -- repeated on every think whenever the engine briefly hid its attack target.
    if state=="attack" and (previous=="approach" or previous=="route" or previous=="waiting") then parent:Stop() end
    if state=="approach" or state=="retreat" or state=="route" then
        -- Root/disarm changes reach the native actor on the next frame.
        -- Do not issue MOVE using an old attack root. Wait exactly one
        -- engine frame, using this modifier's existing think callback.
        parent:SetForceAttackTarget(nil)
        self.order_pending=true
        self.phase_order_frame=true
        self:StartIntervalThink(0)
    else
        self:IssueStateOrder(parent,wall)
    end
    return true
end

function M:MonitorState(parent,wall)
    local stamp=now()
    -- Keep contact reach valid if an external range buff/debuff changes, without
    -- touching the current attack order or refreshing unchanged properties.
    if self.ai_state=="attack" then self:UpdateContactRange(parent,wall) end
    if interrupted(parent) or ((self.ai_state=="approach" or self.ai_state=="route" or self.ai_state=="waiting" or self.ai_state=="retreat")
        and movement_controlled(parent)) or ((self.ai_state=="attack" or self.ai_state=="chase")
        and parent.IsDisarmed and parent:IsDisarmed()) then
        self.last_progress_time=stamp
        self.recovery_after=stamp+3
        return
    end
    if self.order_pending then self:IssueStateOrder(parent,wall);return end
    -- Rear units hold behind the contact row. Only a vacant claim wakes them.
    if self.ai_state=="waiting" then return end
    local p=parent:GetAbsOrigin()
    if not self.progress_position or distance_squared(p,self.progress_position)>=64 then
        self.progress_position=p
        self.last_progress_time=stamp
        self.recovery_delay=3
    end
    -- Record the final movement before waiting at native acceptance. Otherwise
    -- its stale progress position can indefinitely suppress a blocked exit.
    -- Retrying the same completed MOVE cannot separate bodies.
    if self.ai_state=="retreat" and distance_squared(p,self.contact_move)<=32*32 then return end
    -- Native movement can silently finish/fail while still far from its goal
    -- (including the frame that phasing becomes active). Repair that idle move
    -- once BEFORE the three-second reservation expires. The old three-second
    -- monitor lost the claim first and therefore could never retry its move.
    if (self.ai_state=="approach" or self.ai_state=="route" or self.ai_state=="retreat") and not self.approach_retry_done
        and stamp-(self.last_order_time or stamp)>=0.5
        and stamp-(self.last_progress_time or stamp)>=0.5
        and parent.IsIdle and parent:IsIdle()
        and not (parent.IsRooted and parent:IsRooted()) then
        self.approach_retry_done=true
        self:IssueStateOrder(parent,wall)
        return
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
    if self:RefreshWallTarget(parent,true) then return end
    self:IssueStateOrder(parent,wall)
    self.recovery_delay=math.min(12,grace*2)
end

function M:OnIntervalThink()
    if not IsServer() then return end
    if self.first_observation or self.phase_order_frame then
        self.first_observation = false
        self.phase_order_frame = nil
        self:StartIntervalThink(0.5) -- Observe state; never reissue orders on a timer.
    end
    local parent = self:GetParent()
    if contact.restore_hull then contact.restore_hull(parent) end
    -- Release our own root before any dead/control/no-target early return. This
    -- experiment uses the existing .5s observation, never a new per-frame loop.
    self:ObserveRangedStationary(parent)
    if not parent or parent:IsNull() or not parent:IsAlive() then return end

    if self.wall_target_player_id ~= nil and target_controlled(self,parent) then
        self.last_progress_time=now()
        return
    end

    self:RefreshWallTarget(parent,self.wall_entindex<0 and now()>=(self.wall_target_retry_after or 0))

    if self.wall_entindex < 0 then return end

    local wall = EntIndexToHScript(self.wall_entindex)
    if not wall or wall:IsNull() or not wall:IsAlive() then
        if self:RefreshWallTarget(parent,true) then return end
        self:SetWallEntIndex(-1)
        return
    end

    -- A wall keeps its entity when moved. Its old boundary history, rooted
    -- contact and ranged hold must not survive merely because the ID matches.
    if self.goal_wall==wall and (self.goal_wall_revision or 0)
        ~=(tonumber(wall.survival_wall_relocation_revision) or 0) then
        self:SetWallEntIndex(self.wall_entindex,true)
    end

    if not parent.GetTeamNumber or parent:GetTeamNumber()~=DOTA_TEAM_BADGUYS then
        team_alignment.enforce(parent, DOTA_TEAM_BADGUYS, "wave_enemy_ai")
    end
    if not team_alignment.are_enemies(parent, wall) then
        team_alignment.enforce(wall, DOTA_TEAM_GOODGUYS, "wall_target")
    end
    if not team_alignment.are_enemies(parent, wall) then return end

    -- All combat classifications use the ground-navigation wall boundary,
    -- including ranged/flying-labelled and no-unit-collision challenge units.
    if navigation.enforce_boundary then
        if navigation.enforce_boundary(wall,parent,self.boundary_position) then
            self:ReleaseRangedStationary("position_changed")
            -- Do not leave the MOVE that caused penetration alive after the
            -- exceptional boundary recovery. Otherwise it drives back into
            -- the same edge and the next observation ejects it again.
            self:SetWallEntIndex(self.wall_entindex,true)
            local settled=parent:GetAbsOrigin()
            self.boundary_position={x=settled.x,y=settled.y,z=settled.z}
            return
        end
    end
    local desired,point,plan="chase",nil,nil
    local melee=parent.GetAttackCapability and parent:GetAttackCapability()==DOTA_UNIT_CAP_MELEE_ATTACK
    -- Flying is a combat label; these monsters also navigate on the ground.
    -- Every native melee attacker must respect the wall's contact capacity.
    if melee then
        local face=navigation.contact_face and navigation.contact_face(wall,parent)
        plan=contact.resolve(wall,parent,face)
        if plan then
            point=plan.point
            local retained=self.ai_state=="attack" and self.goal_wall==wall and same_point(point,self.contact_move)
            local arrived=plan.claimed and retained and contact.arrived(wall,parent,point,true)
            if plan.claimed and not arrived and not self.contact_locked then
                arrived=contact.settle(wall,parent,point)
            end
            if not plan.claimed then
                desired="waiting"
                local retained_retreat=self.ai_state=="retreat" and self.goal_wall==wall
                    and same_wait_geometry(self,plan)
                local rear_blocked=retained_retreat and not plan.wait_retreat
                    and not contact.rear_clear(wall,parent)
                if (plan.wait_retreat or rear_blocked) and not movement_controlled(parent) then
                    -- Keep a selected fallback lane while retreating. A new
                    -- nearest front lane is not a reason to cancel that move.
                    local stamp=now()
                    if retained_retreat and stamp>=(self.retreat_check_after or 0) then
                        self.retreat_goal_safe=contact.can_retreat(wall,parent,self.contact_move)
                        self.retreat_check_after=stamp+2
                    end
                    if retained_retreat and self.retreat_goal_safe then
                        point=self.contact_move
                        desired="retreat"
                        if (plan.wait_retreat or rear_blocked) and stamp>=(self.retreat_extend_after or 0) then
                            local extended,checked=contact.extend_retreat(wall,parent,plan,point)
                            if extended then point=extended end
                            if checked then self.retreat_extend_after=stamp+2 end
                        end
                    else
                        local failed=self.retreat_failure
                        local position=parent:GetAbsOrigin()
                        if not failed or stamp>=failed.until_time or not same_wait_geometry(failed,plan)
                            or distance_squared(position,failed.position)>=64 then
                            local retreat=contact.retreat_point(wall,parent,plan)
                            if retreat then
                                point=retreat;desired="retreat"
                            else
                                self.retreat_failure={wait_face=plan.wait_face,wait_envelope=plan.wait_envelope,
                                    wait_radius=plan.wait_radius,wait_queue_key=plan.wait_queue_key,
                                    position={x=position.x,y=position.y},until_time=stamp+2}
                            end
                        end
                    end
                end
            else
                local entry=true
                if contact.entry_ready then entry=contact.entry_ready(wall,parent,point) end
                desired=arrived and "attack" or (entry and "approach" or "route")
            end
        end
    else
        contact.release(self.wall_entindex,parent:entindex())
    end
    if not self:EnterState(desired,parent,wall,point,plan) then self:MonitorState(parent,wall) end
    local settled=parent:GetAbsOrigin()
    self.boundary_position={x=settled.x,y=settled.y,z=settled.z}
end

function M:OnDestroy()
    if not IsServer() then return end
    self:ReleaseRangedStationary("destroyed")
    if type(attack_observer.unregister_death)=='function' then attack_observer.unregister_death(self) end
    self.boundary_position=nil
    local parent = self:GetParent()
    if parent and not parent:IsNull() and parent.survival_enemy_attack_owner == self then
        parent.survival_enemy_attack_owner = nil
    end
    if parent and not parent:IsNull() and parent.survival_wall_contact_owner == self then
        parent.survival_wall_contact_owner = nil
    end
    self:SetContactMode(0)
    if parent and not parent:IsNull() then
        contact.release(self.wall_entindex,parent:entindex())
        if contact.restore_hull then contact.restore_hull(parent,true) end
        self:UpdateContactRange(parent,false)
        parent:SetForceAttackTarget(nil)
    end
end

return M
