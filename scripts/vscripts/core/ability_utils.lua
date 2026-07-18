local M = {}

local function valid_unit(unit)
    return unit and not unit:IsNull()
end

local function ability_names(unit)
    local names = {}
    if not valid_unit(unit) or not unit.GetAbilityCount then
        return names
    end

    local count = math.max(0, tonumber(unit:GetAbilityCount()) or 0)
    for index = 0, count - 1 do
        local ability = unit:GetAbilityByIndex(index)
        if ability and not ability:IsNull() then
            local name = ability:GetAbilityName()
            if name and name ~= "" then
                table.insert(names, name)
            end
        end
    end
    return names
end

function M.for_each(unit, callback)
    if not valid_unit(unit) or type(callback) ~= "function" then
        return
    end
    for _, name in ipairs(ability_names(unit)) do
        local ability = unit:FindAbilityByName(name)
        if ability and not ability:IsNull() then
            callback(ability)
        end
    end
end

function M.remove_all_except(unit, allowed)
    if not valid_unit(unit) then
        return
    end
    allowed = allowed or {}

    for pass = 1, 3 do
        local removed = false
        for _, name in ipairs(ability_names(unit)) do
            if not allowed[name] then
                unit:RemoveAbility(name)
                removed = true
            end
        end
        if not removed then
            break
        end
    end
end

function M.remove_all(unit)
    M.remove_all_except(unit, {})
end

return M
