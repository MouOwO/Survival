local M = {}

local function valid_unit(unit)
    return unit and not unit:IsNull()
end

function M.for_each(unit, callback)
    if not valid_unit(unit) or type(callback) ~= "function" then return end
    if not unit.GetAbilityCount then return end

    local count = math.max(0, tonumber(unit:GetAbilityCount()) or 0)
    for index = 0, count - 1 do
        local ability = unit:GetAbilityByIndex(index)
        if ability and not ability:IsNull() then
            callback(ability, index)
        end
    end
end

function M.remove_all(unit)
    if not valid_unit(unit) or not unit.GetAbilityCount then return end

    local count = math.max(0, tonumber(unit:GetAbilityCount()) or 0)
    for index = count - 1, 0, -1 do
        local ability = unit:GetAbilityByIndex(index)
        if ability and not ability:IsNull() then
            unit:RemoveAbility(ability:GetAbilityName())
        end
    end
end

return M
