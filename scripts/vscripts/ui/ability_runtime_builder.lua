local buildings = require("config/buildings_config")
local workers = require("config/workers_config")

local M = {}

local function cost_data(cost)
    return {
        cost_wood = cost and cost.wood or 0,
        cost_gold = cost and cost.gold or 0,
    }
end

local function merge(base, extra)
    for key, value in pairs(extra or {}) do base[key] = value end
    return base
end

local function can_afford(cost, population_cost, resources)
    if not resources then return 1 end
    if (resources.wood or 0) < (cost and cost.wood or 0) then return 0 end
    if (resources.gold or 0) < (cost and cost.gold or 0) then return 0 end
    if (resources.population or 0) + (population_cost or 0)
        > (resources.max_population or 0) then return 0 end
    return 1
end

local function with_affordability(data, cost, population_cost, resources)
    data.can_afford = can_afford(cost, population_cost, resources)
    if data.available == 1 and data.can_afford == 0 then
        data.status_text = "资源或人口不足"
    end
    return data
end

local function build_ability(ability_name, resources)
    local definition_by_ability = {
        ability_build_wall = buildings.wall,
        ability_build_main_city = buildings.main_city,
        ability_build_arrow_tower = buildings.arrow_tower,
    }
    local definition = definition_by_ability[ability_name]
    if not definition then return nil end

    local cost = definition.build_cost
    local data = merge({
        available = 1,
        status_text = "可建造",
    }, cost_data(cost))
    return with_affordability(data, cost, 0, resources)
end

local function upgrade_level(definition, current_level, resources)
    local next_level = current_level + 1
    local data = definition.levels and definition.levels[next_level] or nil
    if not data then
        return {
            available = 0,
            can_afford = 0,
            current_level = current_level,
            status_text = "已达最高等级",
        }
    end

    local result = merge({
        available = 1,
        current_level = current_level,
        next_level = next_level,
        status_text = "可以升级",
    }, cost_data(data.upgrade_cost))
    return with_affordability(result, data.upgrade_cost, 0, resources)
end

local function tower_upgrade(state, resources)
    local definition = buildings.arrow_tower
    if not state.tower_class then
        if state.level >= 5 then
            return {
                available = 0,
                can_afford = 0,
                current_level = state.level,
                status_text = "请先选择一个转职方向",
            }
        end
        local data = definition.pre_class_levels[state.level + 1]
        local result = merge({
            available = data and 1 or 0,
            current_level = state.level,
            next_level = data and state.level + 1 or nil,
            status_text = data and "可以升级" or "已达当前阶段上限",
        }, cost_data(data and data.upgrade_cost or nil))
        return with_affordability(result, data and data.upgrade_cost or nil, 0, resources)
    end

    local growth = definition.post_class_upgrade
    local next_level = state.level + 1
    local extra = next_level - 5
    local cost = {
        wood = growth.wood_base + growth.wood_per_level * math.max(0, extra - 1),
        gold = growth.gold_base + growth.gold_per_level * math.max(0, extra - 1),
    }
    local result = merge({
        available = 1,
        current_level = state.level,
        next_level = next_level,
        status_text = "转职后持续升级",
        tower_class_name = state.tower_class_name or "",
    }, cost_data(cost))
    return with_affordability(result, cost, 0, resources)
end

local function tower_class(state, resources)
    local available = state.level >= 5 and not state.tower_class
    local cost = buildings.arrow_tower.class_change_cost
    local result = merge({
        available = available and 1 or 0,
        current_level = state.level,
        status_text = available and "可以转职"
            or (state.tower_class and "已经完成转职" or "防御塔未达到5级"),
    }, cost_data(cost))
    return with_affordability(result, cost, 0, resources)
end

function M.build(ability_name, state, resources)
    local build = build_ability(ability_name, resources)
    if build then return build end
    if not state then return { available = 1, can_afford = 1, status_text = "" } end

    if ability_name == "ability_upgrade_wall" then
        return upgrade_level(buildings.wall, state.level, resources)
    end
    if ability_name == "ability_upgrade_city" then
        return upgrade_level(buildings.main_city, state.level, resources)
    end
    if ability_name == "ability_train_lumberjack" then
        local result = merge({
            available = 1,
            status_text = "每次有效攻击获得"
                .. tostring(workers.wood_per_hit or 1) .. "木材",
            population = workers.cost.population or 0,
        }, cost_data(workers.cost))
        return with_affordability(
            result,
            workers.cost,
            workers.cost.population or 0,
            resources
        )
    end
    if ability_name == "ability_upgrade_tower" then
        return tower_upgrade(state, resources)
    end
    if string.match(ability_name, "^ability_tower_class_[1-5]$") then
        return tower_class(state, resources)
    end
    return { available = 1, can_afford = 1, status_text = "" }
end

return M
