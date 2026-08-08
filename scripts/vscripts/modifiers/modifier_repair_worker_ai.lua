modifier_repair_worker_ai = class({})
local M = modifier_repair_worker_ai
local repair_math = require("core/repair_math")

local THINK_INTERVAL = 0.25

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
    self.detection_range = math.max(
        self.repair_range,
        tonumber(params.detection_range) or FIND_UNITS_EVERYWHERE
    )
    self.repair_target_entindex = nil
    self.manual_repair_target_entindex = nil
    self.approaching_manual_target = false
    self.repair_fractional_remainder = 0
    self:StartIntervalThink(THINK_INTERVAL)
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

local function repairable_building(parent, building)
    return valid_entity(building)
        and building.survival_is_building == true
        and building:IsAlive()
        and building:GetTeamNumber() == parent:GetTeamNumber()
        and same_owner(parent, building)
        and not building:HasModifier("modifier_building_under_construction")
        and building:GetHealth() < building:GetMaxHealth()
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
    if not repairable_building(parent, building) then return false end
    local build_task = parent.survival_build_task
    if build_task and build_task.constructing then return false end
    if build_task then parent.survival_build_task = nil end
    local entindex = building:entindex()
    if self.manual_repair_target_entindex ~= entindex then
        self.manual_repair_target_entindex = entindex
        self.repair_target_entindex = entindex
        self.repair_fractional_remainder = 0
        self.approaching_manual_target = false
    end
    issue_internal_order(parent, {
        UnitIndex = parent:entindex(),
        OrderType = DOTA_UNIT_ORDER_STOP,
        Queue = false,
    })
    return true
end

function M:ClearManualRepairTarget(reason)
    if not IsServer() then return end
    local parent = self:GetParent()
    local should_stop = self.approaching_manual_target == true
        and reason ~= "player_order"
    self.manual_repair_target_entindex = nil
    self.approaching_manual_target = false
    self.repair_target_entindex = nil
    self.repair_fractional_remainder = 0
    if should_stop and valid_entity(parent) then
        issue_internal_order(parent, {
            UnitIndex = parent:entindex(),
            OrderType = DOTA_UNIT_ORDER_STOP,
            Queue = false,
        })
    end
end

local function damaged_building(parent, detection_range)
    local units = FindUnitsInRadius(
        parent:GetTeamNumber(),
        parent:GetAbsOrigin(),
        nil,
        detection_range,
        DOTA_UNIT_TARGET_TEAM_FRIENDLY,
        DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_HERO,
        DOTA_UNIT_TARGET_FLAG_INVULNERABLE,
        FIND_CLOSEST,
        false
    )
    for _, unit in ipairs(units) do
        if repairable_building(parent, unit) then
            return unit
        end
    end
    return nil
end

local function unit_is_idle(unit)
    if not unit.IsIdle then return true end
    local ok, idle = pcall(function() return unit:IsIdle() end)
    return not ok or idle == true
end

function M:OnIntervalThink()
    if not IsServer() then return end
    local parent = self:GetParent()
    if not parent or parent:IsNull() or not parent:IsAlive() then return end
    if parent.survival_build_task
        or (parent.IsChanneling and parent:IsChanneling())
        or (parent.GetCurrentActiveAbility and parent:GetCurrentActiveAbility()) then
        return
    end
    local manual_target = self.manual_repair_target_entindex ~= nil
    local building = manual_target
        and entity(self.manual_repair_target_entindex) or nil
    if manual_target and not repairable_building(parent, building) then
        self:ClearManualRepairTarget("target_invalid")
        return
    end
    if not manual_target then
        if not unit_is_idle(parent) then return end
        building = damaged_building(parent, self.detection_range)
    end
    if not building then
        self.repair_target_entindex = nil
        self.repair_fractional_remainder = 0
        return
    end
    local building_index = building:entindex()
    if self.repair_target_entindex ~= building_index then
        self.repair_target_entindex = building_index
        self.repair_fractional_remainder = 0
    end
    local center_distance = (
        building:GetAbsOrigin() - parent:GetAbsOrigin()
    ):Length2D()
    local parent_hull = parent.GetHullRadius
        and (parent:GetHullRadius() or 0) or 0
    local building_hull = building.GetHullRadius
        and (building:GetHullRadius() or 0) or 0
    local edge_distance = math.max(
        0,
        center_distance - parent_hull - building_hull
    )
    if edge_distance > self.repair_range then
        if manual_target then self.approaching_manual_target = true end
        issue_internal_order(parent, {
            UnitIndex = parent:entindex(),
            OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
            Position = building:GetAbsOrigin(),
            Queue = false,
        })
        return
    end

    if manual_target and self.approaching_manual_target then
        issue_internal_order(parent, {
            UnitIndex = parent:entindex(),
            OrderType = DOTA_UNIT_ORDER_STOP,
            Queue = false,
        })
        self.approaching_manual_target = false
    end

    parent:FaceTowards(building:GetAbsOrigin())
    parent:StartGesture(ACT_DOTA_ATTACK)
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
        if manual_target then
            self:ClearManualRepairTarget("target_full")
        else
            self.repair_target_entindex = nil
            self.repair_fractional_remainder = 0
        end
    else
        self.repair_fractional_remainder = remainder
    end
end

return M