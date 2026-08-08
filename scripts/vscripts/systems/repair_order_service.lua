local M = {}

local REPAIR_MODIFIER = "modifier_repair_worker_ai"

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

local function ordered_units(keys)
    local result = {}
    for _, entindex in pairs(keys.units or {}) do
        local unit = entity(entindex)
        if unit then result[#result + 1] = unit end
    end
    return result
end

local function repair_modifier(unit)
    if not valid_entity(unit) or not unit.FindModifierByName then return nil end
    local modifier = unit:FindModifierByName(REPAIR_MODIFIER)
    if modifier and modifier.SetManualRepairTarget
        and modifier.ClearManualRepairTarget then
        return modifier
    end
    return nil
end

local function same_owner(unit, target)
    local unit_player_id = tonumber(unit.survival_player_id)
    local target_player_id = tonumber(target.survival_player_id)
    return unit_player_id == nil or target_player_id == nil
        or unit_player_id == target_player_id
end

local function is_repairable_target(unit, target)
    return valid_entity(target)
        and target.survival_is_building == true
        and target:IsAlive()
        and target:GetTeamNumber() == unit:GetTeamNumber()
        and same_owner(unit, target)
        and not target:HasModifier("modifier_building_under_construction")
        and target:GetHealth() < target:GetMaxHealth()
end

local function is_target_order(order_type)
    return order_type == tonumber(DOTA_UNIT_ORDER_MOVE_TO_TARGET)
        or order_type == tonumber(DOTA_UNIT_ORDER_ATTACK_TARGET)
end

-- Returns true only when the original engine order has been consumed and must
-- be rejected by the single global ExecuteOrderFilter.
function M.process(keys)
    keys = keys or {}
    local order_type = tonumber(keys.order_type)
    local units = ordered_units(keys)
    if #units == 0 then return false end

    local target = is_target_order(order_type)
        and entity(keys.entindex_target) or nil
    local consumed = false

    for _, unit in ipairs(units) do
        local modifier = repair_modifier(unit)
        if modifier and unit.survival_repair_internal_order ~= true then
            if target and is_repairable_target(unit, target) then
                if modifier:SetManualRepairTarget(target) then
                    consumed = true
                end
            else
                modifier:ClearManualRepairTarget("player_order")
            end
        end
    end

    return consumed
end

M._ordered_units_for_test = ordered_units
M._is_repairable_target_for_test = is_repairable_target

return M