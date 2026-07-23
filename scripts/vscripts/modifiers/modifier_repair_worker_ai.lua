modifier_repair_worker_ai = class({})
local M = modifier_repair_worker_ai

local THINK_INTERVAL = 0.25

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:OnCreated(params)
    if not IsServer() then return end
    self.repair_per_second = math.max(
        0,
        tonumber(params.repair_per_second) or 0
    )
    self.repair_range = math.max(64, tonumber(params.repair_range) or 200)
    self.detection_range = math.max(
        self.repair_range,
        tonumber(params.detection_range) or FIND_UNITS_EVERYWHERE
    )
    self:StartIntervalThink(THINK_INTERVAL)
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
        if unit.survival_is_building == true
            and unit:IsAlive()
            and not unit:HasModifier("modifier_building_under_construction")
            and unit:GetHealth() < unit:GetMaxHealth() then
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
    if not unit_is_idle(parent) then return end

    local building = damaged_building(parent, self.detection_range)
    if not building then return end
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
        ExecuteOrderFromTable({
            UnitIndex = parent:entindex(),
            OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
            Position = building:GetAbsOrigin(),
            Queue = false,
        })
        return
    end

    parent:FaceTowards(building:GetAbsOrigin())
    parent:StartGesture(ACT_DOTA_ATTACK)
    local amount = self.repair_per_second * THINK_INTERVAL
    building:SetHealth(math.min(
        building:GetMaxHealth(),
        building:GetHealth() + amount
    ))
end

return M