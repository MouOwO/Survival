local M = {}

local function valid(unit)
    return unit and not unit:IsNull()
end

function M.is_flying(unit)
    if not valid(unit) then return false end
    return tostring(unit.survival_movement_type or "") == "flying"
        or tostring(unit.survival_movement_type_override or "") == "flying"
end

function M.is_anti_air_tower(unit)
    return valid(unit) and tostring(unit.survival_tower_class or "") == "class_7"
end

function M.can_attack(attacker, target)
    return not M.is_anti_air_tower(attacker) or M.is_flying(target)
end

function M.has_damage_taken_aura(unit)
    if not valid(unit) or not unit.FindAllModifiersByName then return false end
    for _, modifier in ipairs(
            unit:FindAllModifiersByName("modifier_survival_managed_buff") or {}) do
        if modifier and not modifier:IsNull()
            and modifier.buff_id == "debuff_airspace_damage_taken" then
            return true
        end
    end
    return false
end

return M