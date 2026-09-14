-- Shared by authoritative upgrades and tooltip cost projection.
local M = {}

function M.quote(definition, level, quick)
    level = tonumber(level) or 1
    local target = quick and definition.quick_upgrade_target_level or level + 1
    if quick and level ~= 1 then
        return nil, "直升9-1仅限未升级的城墙"
    end
    local levels = definition.levels or {}
    if not target or not levels[target] then return nil, "城墙已达最高等级" end
    local result = {target_level = target, data = levels[target], cost = {wood = 0, gold = 0}, requires_city_level = 0}
    for index = level + 1, target do
        local row = levels[index]
        if not row or not row.upgrade_cost then return nil, "城墙升级费用未配置" end
        result.cost.wood = result.cost.wood + math.max(0, tonumber(row.upgrade_cost.wood) or 0)
        result.cost.gold = result.cost.gold + math.max(0, tonumber(row.upgrade_cost.gold) or 0)
        result.requires_city_level = math.max(result.requires_city_level, tonumber(row.requires_city_level) or 0)
    end
    return result
end

function M.sync(state, busy)
    if not state or state.building_id ~= "wall" then return end
    local unit = state.unit
    if not unit or unit:IsNull() or not unit.FindAbilityByName then return end
    for _, entry in ipairs({{"ability_upgrade_wall", false}, {"ability_upgrade_wall_9_1", true}}) do
        local quote = M.quote(state.definition, state.level, entry[2])
        local ability = unit:FindAbilityByName(entry[1])
        if not ability and quote and unit.AddAbility then
            ability = unit:AddAbility(entry[1])
            if ability then ability:SetLevel(1) end
        end
        if ability then
            ability:SetHidden(quote == nil)
            ability:SetActivated(quote ~= nil and not busy)
        end
    end
end

return M
