modifier_repair_worker_ai = class({})
_G.modifier_repair_worker_ai = modifier_repair_worker_ai
local M = modifier_repair_worker_ai
local repair_math = require("core/repair_math")
local repair_policy = require("systems/repair_target_policy")
local repair_candidates = require("systems/repair_building_candidates")
local repair_wakeup = require("systems/repair_worker_wakeup")

local THINK_INTERVAL = repair_policy.think_interval
local IDLE_INTERVAL = repair_policy.idle_interval

function M:SetThinkInterval(interval)
    if self.repair_think_interval == interval then return end
    self.repair_think_interval = interval
    self:StartIntervalThink(interval)
end

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:OnCreated(params)
    if not IsServer() then return end
    self.repair_max_health_pct_per_second = math.max(
        0,
        tonumber(params.repair_max_health_pct_per_second) or 0
    )
    self.repair_range = math.max(64, tonumber(params.repair_range) or 200)
    local detection_range = tonumber(params.detection_range) or FIND_UNITS_EVERYWHERE
    -- The engine's all-map sentinel is -1; clamping it would silently restrict
    -- builders without an explicit scan range to their melee repair radius.
    self.detection_range = detection_range == FIND_UNITS_EVERYWHERE
        and detection_range or math.max(self.repair_range, detection_range)
    self.repair_target_entindex = nil
    self.manual_repair_target_entindex = nil
    self.repair_target_handle = nil
    self.manual_repair_target_handle = nil
    self.repairing = false
    self.repair_standby = false
    self.repair_gesture_elapsed = 0.25
    self.approaching_manual_target = false
    self.approaching_repair_target = false
    self.repair_fractional_remainder = 0
    self.approach_retry = 0
    self.repair_think_interval = nil
    repair_wakeup.register(self, self:GetParent())
    self:SetThinkInterval(IDLE_INTERVAL)
end

function M:OnDestroy()
    if IsServer() then repair_wakeup.unregister(self) end
end

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function entity(entindex)
    entindex = tonumber(entindex)
    if not entindex or type(EntIndexToHScript) ~= "function" then return nil end
    local ok, result = pcall(EntIndexToHScript, entindex)
    if not ok or not valid_entity(result) then return nil end
    return result
end

local function same_owner(parent, building)
    local parent_player_id = tonumber(parent.survival_player_id)
    local building_player_id = tonumber(building.survival_player_id)
    return parent_player_id == nil or building_player_id == nil
        or parent_player_id == building_player_id
end

local function repairable_building(parent, building, allow_full)
    return valid_entity(building)
        and building.survival_is_building == true
        and building:IsAlive()
        and building:GetTeamNumber() == parent:GetTeamNumber()
        and same_owner(parent, building)
        and not building:HasModifier("modifier_building_under_construction")
        and (allow_full or repair_policy.needs_repair(building))
end

local function issue_internal_order(parent, order)
    parent.survival_repair_internal_order = true
    local ok, result = pcall(ExecuteOrderFromTable, order)
    parent.survival_repair_internal_order = nil
    return ok, result
end

function M:SetManualRepairTarget(building)
    if not IsServer() then return false end
    local parent = self:GetParent()
    if not repairable_building(parent, building, true) then return false end
    local build_task = parent.survival_build_task
    if build_task and build_task.constructing then return false end
    if build_task then parent.survival_build_task = nil end
    self.approach_retry = 0
    self.repair_standby = false
    self.approaching_repair_target = false
    local entindex = building:entindex()
    if self.manual_repair_target_entindex ~= entindex
        or self.manual_repair_target_handle ~= building then
        self.manual_repair_target_entindex = entindex
        self.manual_repair_target_handle = building
        self.repair_target_entindex = entindex
        self.repair_target_handle = building
        self.repairing = false
        self.repair_gesture_elapsed = 0.25
        self.repair_fractional_remainder = 0
        self.approaching_manual_target = false
    end
    issue_internal_order(parent, {
        UnitIndex = parent:entindex(),
        OrderType = DOTA_UNIT_ORDER_STOP,
        Queue = false,
    })
    self:SetThinkInterval(THINK_INTERVAL)
    return true
end

function M:ClearManualRepairTarget(reason)
    if not IsServer() then return end
    local parent = self:GetParent()
    local should_stop = (self.approaching_manual_target == true
        or self.approaching_repair_target == true)
        and reason ~= "player_order"
    self.manual_repair_target_entindex = nil
    self.manual_repair_target_handle = nil
    self.approaching_manual_target = false
    self.approaching_repair_target = false
    self.repair_target_entindex = nil
    self.repair_target_handle = nil
    self.repairing = false
    self.repair_standby = false
    self.repair_gesture_elapsed = 0.25
    self.repair_fractional_remainder = 0
    self:SetThinkInterval(IDLE_INTERVAL)
    if should_stop and valid_entity(parent) then
        issue_internal_order(parent, {
            UnitIndex = parent:entindex(),
            OrderType = DOTA_UNIT_ORDER_STOP,
            Queue = false,
        })
    end
end

local function damaged_building(parent, detection_range)
    -- The formal registry includes native npc_dota_building walls. Its cached
    -- owner/team candidates avoid a map-wide engine search on each idle tick.
    return repair_candidates.closest(parent, detection_range, repairable_building)
end

local function unit_is_idle(unit)
    if not unit.IsIdle then return true end
    local ok, idle = pcall(function() return unit:IsIdle() end)
    return not ok or idle == true
end

function M:WakeForDamagedBuilding(building)
    if self.repair_think_interval == THINK_INTERVAL then return false end
    local parent = self:GetParent()
    if not valid_entity(parent) or not parent:IsAlive()
        or parent.survival_build_task
        or (parent.IsChanneling and parent:IsChanneling())
        or (parent.GetCurrentActiveAbility and parent:GetCurrentActiveAbility())
        or not repairable_building(parent, building, false) then return false end
    if self.manual_repair_target_entindex then
        if self.manual_repair_target_handle ~= building then return false end
    elseif not unit_is_idle(parent) then
        return false
    end
    -- Changing the timer only once leaves an already pending wake untouched.
    self:SetThinkInterval(THINK_INTERVAL)
    return true
end

function M:OnIntervalThink()
    if not IsServer() then return end
    local parent = self:GetParent()
    if not parent or parent:IsNull() or not parent:IsAlive() then
        self:SetThinkInterval(IDLE_INTERVAL)
        return
    end
    if parent.survival_build_task
        or (parent.IsChanneling and parent:IsChanneling())
        or (parent.GetCurrentActiveAbility and parent:GetCurrentActiveAbility()) then
        self:SetThinkInterval(IDLE_INTERVAL)
        return
    end
    local manual_target = self.manual_repair_target_entindex ~= nil
    local building = manual_target
        and self.manual_repair_target_handle or self.repair_target_handle
    -- Keep the actual handle: recycled entity indices must not inherit work.
    if building and (not valid_entity(building)
        or entity(building:entindex()) ~= building) then building = nil end
    if manual_target and not repairable_building(parent, building, true) then
        self:ClearManualRepairTarget("target_invalid")
        return
    end
    if not manual_target then
        if building and not repairable_building(parent, building, true) then building = nil end
        -- Another worker or a regeneration effect can finish our target.
        -- Retire it before seeking work instead of pinning a healthy building.
        if building and (building:GetHealth() >= building:GetMaxHealth()
            or (not self.repairing and not repair_policy.needs_repair(building))) then
            building = nil
        end
        if not building then
            if self.approaching_repair_target then
                issue_internal_order(parent, {
                    UnitIndex = parent:entindex(),
                    OrderType = DOTA_UNIT_ORDER_STOP,
                    Queue = false,
                })
                self.approaching_repair_target = false
            end
            self.repair_target_entindex = nil
            self.repair_target_handle = nil
            self.repairing = false
            self.repair_standby = false
            self.repair_fractional_remainder = 0
            if not unit_is_idle(parent) then
                self:SetThinkInterval(IDLE_INTERVAL)
                return
            end
            building = damaged_building(parent, self.detection_range)
        end
    end
    if not building then
        self.repair_target_entindex = nil
        self.repair_target_handle = nil
        self.repairing = false
        self.repair_standby = false
        self.repair_fractional_remainder = 0
        self:SetThinkInterval(IDLE_INTERVAL)
        return
    end
    local building_index = building:entindex()
    if self.repair_target_entindex ~= building_index or self.repair_target_handle ~= building then
        self.repair_target_entindex = building_index
        self.repair_target_handle = building
        self.approach_retry = 0
        self.repairing = false
        self.repair_standby = false
        self.repair_fractional_remainder = 0
    end
    if self.repair_standby and not self.repairing
        and not repair_policy.needs_repair(building) then
        self:SetThinkInterval(IDLE_INTERVAL)
        return
    end
    self:SetThinkInterval(THINK_INTERVAL)
    local building_position, worker_position = building:GetAbsOrigin(), parent:GetAbsOrigin()
    local dx, dy = building_position.x - worker_position.x, building_position.y - worker_position.y
    local parent_hull = parent.GetHullRadius
        and (parent:GetHullRadius() or 0) or 0
    local building_hull = building.GetHullRadius
        and (building:GetHullRadius() or 0) or 0
    local center_range = self.repair_range + parent_hull + building_hull
    if dx * dx + dy * dy > center_range * center_range then
        self.approach_retry = math.max(0, (self.approach_retry or 0) - THINK_INTERVAL)
        if self.approach_retry <= 0 then
            -- Find a reachable point outside the wall footprint, never its blocked center.
            local point = require("systems/builder_work_position_service").find(parent, {
                footprint = building.survival_grid_footprint or {x = 2, y = 2},
                hull_radius = building_hull,
            }, building:GetAbsOrigin(), {
                -- Leave arrival tolerance so native movement may stop just
                -- short of the point and still be inside the repair radius.
                max_center_distance = self.repair_range + parent_hull + building_hull - 16,
            })
            self.approach_retry = 1
            if point then
                if manual_target then self.approaching_manual_target = true end
                self.approaching_repair_target = true
                issue_internal_order(parent, {
                    UnitIndex = parent:entindex(),
                    OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
                    Position = point,
                    Queue = false,
                })
            end
        end
        return
    end

    if self.approaching_repair_target or (manual_target and self.approaching_manual_target) then
        issue_internal_order(parent, {
            UnitIndex = parent:entindex(),
            OrderType = DOTA_UNIT_ORDER_STOP,
            Queue = false,
        })
        self.approaching_manual_target = false
        self.approaching_repair_target = false
    end

    if building:GetHealth() >= building:GetMaxHealth()
        or (not self.repairing and not repair_policy.needs_repair(building)) then
        self.repairing = false
        self.repair_standby = manual_target
        self.repair_fractional_remainder = 0
        self:SetThinkInterval(IDLE_INTERVAL)
        return -- Keep the explicitly assigned wall; resume when it takes damage.
    end
    self.repairing = true
    self.repair_standby = false
    -- A faster decision tick must not restart the attack gesture ten times a
    -- second. Preserve its old cadence independently of the healing interval.
    self.repair_gesture_elapsed = (self.repair_gesture_elapsed or 0.25) + THINK_INTERVAL
    if self.repair_gesture_elapsed >= 0.25 then
        self.repair_gesture_elapsed = self.repair_gesture_elapsed - 0.25
        parent:FaceTowards(building:GetAbsOrigin())
        parent:StartGesture(ACT_DOTA_ATTACK)
    end
    local amount, remainder = repair_math.whole_amount_for_interval(
        building:GetMaxHealth(),
        self.repair_max_health_pct_per_second,
        THINK_INTERVAL,
        self.repair_fractional_remainder
    )
    local max_health = building:GetMaxHealth()
    local next_health = math.min(max_health, building:GetHealth() + amount)
    building:SetHealth(next_health)
    if next_health >= max_health then
        self.repairing = false
        self.repair_standby = manual_target
        if manual_target then
            self.repair_fractional_remainder = 0
        else
            self.repair_target_entindex = nil
            self.repair_target_handle = nil
            self.repair_fractional_remainder = 0
        end
        self:SetThinkInterval(IDLE_INTERVAL)
    else
        self.repair_fractional_remainder = remainder
    end
end

return M
