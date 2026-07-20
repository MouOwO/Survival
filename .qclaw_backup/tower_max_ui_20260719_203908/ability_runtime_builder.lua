local buildings = require("config/buildings_config")
local workers = require("config/workers_config")
local gold_mine = require("config/gold_mine_config")
local tower_routes = require("config/tower_route_config")
local M = {}
local function cost_data(cost)
    return {
        cost_wood = cost and cost.wood or 0,
        cost_gold = cost and cost.gold or 0,
    }
end
local function merge(base, extra)
    for key, value in pairs(extra or {}) do
        base[key] = value
    end
    return base
end
local function can_afford(cost, population_cost, resources)
    if not resources then
        return 1
    end
    if (resources.wood or 0) < (cost and cost.wood or 0) then
        return 0
    end
    if (resources.gold or 0) < (cost and cost.gold or 0) then
        return 0
    end
    if (resources.population or 0) + (population_cost or 0)
        > (resources.max_population or 0) then
        return 0
    end
    return 1
end
local function with_affordability(data, cost, population_cost, resources)
    data.can_afford = can_afford(cost, population_cost, resources)
    if data.available == 1 and data.can_afford == 0 then
        data.status_text = "资源或人口不足"
    end
    return data
end
local function count(state, building_id)
    return state.building_counts
        and state.building_counts[building_id] or 0
end
local function build_ability(ability_name, state, resources)
    local definitions = {
        ability_build_wall = buildings.wall,
        ability_build_main_city = buildings.main_city,
        ability_build_arrow_tower = buildings.arrow_tower,
        ability_build_gold_mine = buildings.gold_mine,
        ability_build_hero_altar = buildings.hero_altar,
    }
    local definition = definitions[ability_name]
    if not definition then
        return nil
    end
    local required = definition.unlock_city_level or 0
    local city_level = state and state.city_level or 0
    local maximum = definition.max_count or 0
    local built = count(state or {}, definition.id)
    local unlocked = city_level >= required
    local under_limit = maximum <= 0 or built < maximum
    local hero_allows = not (
        definition.id == "hero_altar"
        and state and state.hero_summoned == 1
    )
    local available = unlocked and under_limit and hero_allows
    local status = "可建造"
    if not unlocked then
        status = "主城达到Lv." .. tostring(required) .. "后解锁"
    elseif not under_limit then
        status = definition.display_name .. "已建造"
    elseif not hero_allows then
        status = "已经召唤英雄，祭坛建造入口已关闭"
    end
    local data = merge({
        available = available and 1 or 0,
        current_level = city_level,
        status_text = status,
        fields = required > 0 and {
            {
                label = "解锁条件",
                value = "主城Lv." .. tostring(required),
            },
        } or nil,
    }, cost_data(definition.build_cost))
    return with_affordability(
        data,
        definition.build_cost,
        0,
        resources
    )
end
local function upgrade_level(definition, current_level, resources)
    local next_level = current_level + 1
    local data = definition.levels
        and definition.levels[next_level] or nil
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
    return with_affordability(
        result,
        data.upgrade_cost,
        0,
        resources
    )
end
local function tower_upgrade(ability_name, state, resources)
    local mode = ability_name == "ability_upgrade_tower_max" and "max" or "one"
    if not state.tower_class and state.level >= 5 then
        return { available = 0, can_afford = 0, current_level = state.level, status_text = "请先选择一个转职方向" }
    end
    local target = mode == "max" and tower_routes.stage_end_level(state) or state.level + 1
    local row = tower_routes.row_at_level(state, target)
    local current_row = tower_routes.current(state)
    if mode == "max" and current_row and current_row.rarity
        and current_row.rarity ~= "" and current_row.rarity ~= "N" then
        return { available = 0, can_afford = 0, current_level = state.level, status_text = "当前稀有度不可升满" }
    end
    local cost = tower_routes.cost_to(state, target)
    if target <= state.level or not row or not cost then
        return { available = 0, can_afford = 0, current_level = state.level, status_text = "已达最高等级" }
    end
    local result = merge({
        available = 1, current_level = state.level, next_level = target,
        status_text = (mode == "max" and "升满至" or "升级至")
            .. tower_routes.display_name(row),
        tower_name = tower_routes.display_name(row), skill_ids = row.skill_ids,
        upgrade_description = row.upgrade_description,
        target_level = target,
        upgrade_attack_delta = (row.base_attack_damage or 0)
            - (current_row and current_row.base_attack_damage or 0),
    }, cost_data(cost))
    return with_affordability(result, cost, cost.population or 0, resources)
end
local function tower_class(ability_name, state, resources)
    local available = state.level >= 5 and not state.tower_class
    local class_index = tonumber(string.match(ability_name, "(%d+)$"))
    local class_id = class_index and "class_" .. tostring(class_index) or nil
    local row = class_id and tower_routes.get(class_id, 1) or nil
    local cost = row and { wood = row.upgrade_wood, gold = row.upgrade_gold } or nil
    local result = merge({
        available = available and row and 1 or 0,
        current_level = state.level,
        status_text = available and row and "转职为" .. tower_routes.display_name(row)
            or (state.tower_class and "已经完成转职"
                or "防御塔未达到5级"),
        tower_name = row and tower_routes.display_name(row) or "",
        skill_ids = row and row.skill_ids or nil,
    }, cost_data(cost))
    return with_affordability(result, cost, row and row.population_delta or 0, resources)
end
local function mine_efficiency(state, resources)
    local level = state.mine_level or 1
    if level >= gold_mine.max_level then
        return {
            available = 0,
            can_afford = 0,
            current_level = level,
            status_text = "采集效率已满级",
        }
    end
    local cost = gold_mine.efficiency_upgrade_cost(level)
    local result = merge({
        available = 1,
        current_level = level,
        next_level = level + 1,
        status_text = "提升每秒金币产量",
    }, cost_data(cost))
    return with_affordability(result, cost, 0, resources)
end
local function mine_crit(state, resources)
    local level = state.crit_level or 0
    if level >= gold_mine.max_crit_level then
        return {
            available = 0,
            can_afford = 0,
            current_level = level,
            status_text = "暴击率已满级",
        }
    end
    local cost = gold_mine.crit_upgrade_cost(level)
    local result = merge({
        available = 1,
        current_level = level,
        next_level = level + 1,
        status_text = "每级增加2%暴击率",
    }, cost_data(cost))
    return with_affordability(result, cost, 0, resources)
end
local function altar_open(state)
    local summoned = state and state.hero_summoned == 1
    return {
        available = summoned and 0 or 1,
        can_afford = 1,
        status_text = summoned
            and "已经召唤英雄，祭坛已停止工作"
            or "打开英雄选择界面",
    }
end
function M.build(ability_name, state, resources)
    local build = build_ability(ability_name, state, resources)
    if build then
        return build
    end
    if ability_name == "ability_open_hero_altar" then
        return altar_open(state)
    end
    if not state then
        return {
            available = 1,
            can_afford = 1,
            status_text = "",
        }
    end
    if ability_name == "ability_upgrade_wall" then
        return upgrade_level(buildings.wall, state.level, resources)
    end
    if ability_name == "ability_upgrade_city" then
        return upgrade_level(
            buildings.main_city,
            state.level,
            resources
        )
    end
    if ability_name == "ability_train_lumberjack" then
        local result = merge({
            available = 1,
            status_text = "每次有效攻击获得"
                .. tostring(workers.wood_per_hit or 1)
                .. "木材",
            population = workers.cost.population or 0,
        }, cost_data(workers.cost))
        return with_affordability(
            result,
            workers.cost,
            workers.cost.population or 0,
            resources
        )
    end
    if ability_name == "ability_upgrade_tower"
        or ability_name == "ability_upgrade_tower_lv01"
        or ability_name == "ability_upgrade_tower_max" then
        return tower_upgrade(ability_name, state, resources)
    end
    if ability_name == "ability_upgrade_gold_mine" then
        return mine_efficiency(state, resources)
    end
    if ability_name == "ability_upgrade_gold_mine_crit" then
        return mine_crit(state, resources)
    end
    if string.match(
        ability_name,
        "^ability_tower_class_[1-7]$"
    ) then
        return tower_class(ability_name, state, resources)
    end
    return {
        available = 1,
        can_afford = 1,
        status_text = "",
    }
end
return M
