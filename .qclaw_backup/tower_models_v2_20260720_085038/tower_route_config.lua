local arrow = require("config/generated/arrow_tower_base")
local modules = {
    class_1 = require("config/generated/tower_class_death"),
    class_2 = require("config/generated/tower_class_mystery"),
    class_3 = require("config/generated/tower_class_lightning"),
    class_4 = require("config/generated/tower_class_machine_gun"),
    class_5 = require("config/generated/tower_class_multi"),
    class_6 = require("config/generated/tower_class_frost"),
    class_7 = require("config/generated/tower_class_anti_air"),
}

local M = {}

function M.get_route(class_id)
    local module = modules[class_id]
    return module and module.rows or nil
end

function M.get(class_id, route_index)
    local route = M.get_route(class_id)
    return route and route[route_index] or nil
end

function M.arrow(level)
    return arrow.rows[level]
end

function M.current(state)
    if state.tower_class then return M.get(state.tower_class, state.level - 5) end
    return M.arrow(state.level)
end

function M.stage_end_level(state)
    if not state.tower_class then return 5 end
    local row = M.current(state)
    if not row then return state.level end
    local route_index = state.level - 5
    local remaining = (row.max_level or row.level) - (row.level or 1)
    return state.level + math.max(0, remaining)
end

function M.row_at_level(state, absolute_level)
    if state.tower_class then return M.get(state.tower_class, absolute_level - 5) end
    return M.arrow(absolute_level)
end

function M.model_for(row)
    return row and row.model_name or nil
end

function M.cost_to(state, target_level)
    local cost = { wood = 0, gold = 0, population = 0 }
    for level = state.level + 1, target_level do
        local row = M.row_at_level(state, level)
        if not row then return nil end
        cost.wood = cost.wood + (row.upgrade_wood or 0)
        cost.gold = cost.gold + (row.upgrade_gold or 0)
        cost.population = cost.population + (row.population_delta or 0)
    end
    return cost
end

function M.display_name(row)
    if not row then return "" end
    if not row.rarity or row.rarity == "" then return row.name end
    return "【" .. row.rarity .. "】" .. row.name
end

return M
