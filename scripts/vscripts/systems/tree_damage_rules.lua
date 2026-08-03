local M = {}

local function valid(unit)
    return unit and not unit:IsNull()
end

function M.is_tree(unit)
    return valid(unit) and unit.GetUnitName
        and unit:GetUnitName() == "enemy_tree"
end

function M.is_arrow_tower(unit)
    return valid(unit)
        and tostring(unit.survival_building_id or "") == "arrow_tower"
end

function M.is_basic_attack_category(category)
    return DOTA_DAMAGE_CATEGORY_ATTACK ~= nil
        and tonumber(category) == tonumber(DOTA_DAMAGE_CATEGORY_ATTACK)
end

function M.allows_damage(attacker, victim, damage_category)
    if not M.is_tree(victim) then return true end
    if M.is_arrow_tower(attacker) then return false end
    return M.is_basic_attack_category(damage_category)
end

return M