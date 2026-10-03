local arrow = require("config/generated/arrow_tower_base")
local asset_catalog = require("config/asset_catalog")
local rank_projection = require("systems/tower_rank_projection")
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
-- CSV rarity still controls existing gameplay (e.g. stage-max upgrades). UI
-- rank comes from the actual route position, shared with the overhead stars.
local presentation_level_by_id = {}
for index, row in ipairs(arrow.rows) do
    presentation_level_by_id[row.record_id] = index
end
for _, module in pairs(modules) do
    for index, row in ipairs(module.rows) do
        presentation_level_by_id[row.record_id] = index + 5
    end
end

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

function M.population_occupied(row)
    return math.max(0, tonumber(row and row.population_occupied) or 0)
end

function M.population_transition(state, target_row)
    local current = tonumber(state and state.population_occupied)
    if current == nil then current = M.population_occupied(M.current(state)) end
    current = math.max(0, current)
    local target = M.population_occupied(target_row)
    return {
        current = current,
        target = target,
        spend = math.max(0, target - current),
        release = math.max(0, current - target),
    }
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
    if not row then return nil end
    local asset = asset_catalog.resolve(row.model_asset_id)
    return asset and asset.primary_model or row.model_name
end

function M.is_supported_route_model(row)
    if row and row.model_asset_id and asset_catalog.resolve(row.model_asset_id) then
        return true
    end
    local model = M.model_for(row)
    return model == "models/heroes/zuus/zuus.vmdl"
        or model == "models/heroes/drow_ranger/drow_ranger.vmdl"
end

function M.cost_to(state, target_level)
    local cost = { wood = 0, gold = 0, population = 0 }
    local target_row = nil
    for level = state.level + 1, target_level do
        local row = M.row_at_level(state, level)
        if not row then return nil end
        target_row = row
        cost.wood = cost.wood + (tonumber(row.upgrade_wood) or 0)
        cost.gold = cost.gold + (tonumber(row.upgrade_gold) or 0)
    end
    local transition = M.population_transition(state, target_row)
    cost.population = transition.spend
    cost.population_release = transition.release
    cost.population_occupied = transition.target
    return cost
end

function M.class_change_cost(row, state)
    if not row then return nil end
    local transition = state and M.population_transition(state, row) or {
        spend = M.population_occupied(row),
        release = 0,
        target = M.population_occupied(row),
    }
    return {
        wood = tonumber(row.upgrade_wood) or 0,
        gold = tonumber(row.upgrade_gold) or 0,
        population = transition.spend,
        population_release = transition.release,
        population_occupied = transition.target,
    }
end

function M.display_name(row)
    if not row then return "" end
    local level = presentation_level_by_id[row.record_id]
    return rank_projection.display_name({ building_id = "arrow_tower", level = level }, row.name)
        or row.name
end

function M.display_name_for_unit(unit)
    if not unit then return nil end
    if unit.survival_building_id == "arrow_tower" then
        local row = M.current({
            level = tonumber(unit.survival_level) or 1,
            tower_class = unit.survival_tower_class,
        })
        return row and M.display_name(row) or nil
    end
    if unit.survival_ultimate_tower == true or unit.survival_building_id == "ultimate_tower" then
        return rank_projection.display_name({ building_id = "ultimate_tower", level = 1 },
            unit.survival_display_name or "终极之塔")
    end
    return nil
end

return M
