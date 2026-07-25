local buildings = require("config/buildings_config")
local workers = require("config/workers_config")
local gold_mine = require("config/gold_mine_config")
local tower_routes = require("config/tower_route_config")
local altar_actions = require("config/generated/altar_actions")
local event_bus = require("core/event_bus")
local events = require("core/events")
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
        population = definition.population_cost or 0,
    }, cost_data(definition.build_cost))
    return with_affordability(
        data,
        definition.build_cost,
        definition.population_cost or 0,
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
    -- Tower upgrade abilities must remain clickable when resources are short.
    -- The authoritative upgrade system validates and spends resources, then
    -- reports the concrete failure to the player. Treating affordability as
    -- availability here made both level-one buttons grey (especially the
    -- cumulative "max" upgrade) and prevented players from requesting an
    -- otherwise valid upgrade.
    local affordable = can_afford(cost, cost.population or 0, resources)
    result.can_afford = 1
    if affordable == 0 then
        result.status_text = result.status_text .. "（当前资源不足）"
    end
    return result
end
local function tower_class(ability_name, state, resources)
    local available = state.level >= 5 and not state.tower_class
    local class_index = tonumber(string.match(ability_name, "(%d+)$"))
    local class_id = class_index and "class_" .. tostring(class_index) or nil
    local row = class_id and tower_routes.get(class_id, 1) or nil
    local cost = tower_routes.class_change_cost(row)
    local result = merge({
        available = available and row and 1 or 0,
        current_level = state.level,
        status_text = available and row and "转职为" .. tower_routes.display_name(row)
            or (state.tower_class and "已经完成转职"
                or "防御塔未达到5级"),
        tower_name = row and tower_routes.display_name(row) or "",
        skill_ids = row and row.skill_ids or nil,
    }, cost_data(cost))
    -- population_delta increases max population after the class change; it is
    -- not population consumed by the upgrade itself.
    return with_affordability(result, cost, 0, resources)
end
local function mine_level_upgrade(state, resources)
    local level = state.mine_level or state.level or 1
    if level >= gold_mine.max_mine_level then
        return {
            available = 0,
            can_afford = 0,
            current_level = level,
            status_text = "金矿本体已满级",
            upgrade_description = "金矿本体已经达到最高等级。",
        }
    end
    local cost = gold_mine.mine_upgrade_cost(level)
    local result = merge({
        available = 1,
        current_level = level,
        next_level = level + 1,
        status_text = "升级金矿本体至Lv." .. tostring(level + 1),
        upgrade_description = "提升金矿本体等级并提高基础金币产量。",
    }, cost_data(cost))
    return with_affordability(result, cost, 0, resources)
end
local function mine_efficiency(state, resources)
    local level = state.efficiency_level or 0
    if level >= gold_mine.max_efficiency_level then
        return {
            available = 0,
            can_afford = 0,
            current_level = level,
            status_text = "金矿收益已满级",
            upgrade_description = "采金效率已经达到最高等级。",
        }
    end
    local cost = gold_mine.efficiency_upgrade_cost(level)
    local result = merge({
        available = cost and 1 or 0,
        current_level = level,
        next_level = level + 1,
        status_text = cost and "所有金矿收益增加5%（额外收益至少1金币）"
            or "收益升级配置缺失",
        upgrade_description = "共50级，每级使所有金矿收益提高5%；额外金币不足1时按1金币计算。",
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
            upgrade_description = "采金暴击已经达到最高等级。",
        }
    end
    local cost = gold_mine.crit_upgrade_cost(level)
    local result = merge({
        available = 1,
        current_level = level,
        next_level = level + 1,
        status_text = "每级增加3%采集暴击率",
        upgrade_description = "共10级，每级增加3%采集暴击率；采集暴击时获得正常采集金币的3倍。",
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
local ALTAR_ACTION_BY_ABILITY = {}
for _, action in ipairs(altar_actions.rows or {}) do
    if action.enabled ~= false and action.ability_name then
        ALTAR_ACTION_BY_ABILITY[action.ability_name] = action
    end
end
local function altar_travel(ability_name, state, resources)
    local action = ALTAR_ACTION_BY_ABILITY[ability_name]
    if not action then return nil end
    local player_id = tonumber(state and state.player_id)
    local progression = player_id ~= nil and event_bus.request(
        events.HERO_PROGRESSION_GET_REQUEST,
        { player_id = player_id }
    ) or nil
    local rebirth = progression and progression.snapshot
        and tonumber(progression.snapshot.rebirth_level) or 0
    local required = tonumber(action.required_rebirth_level) or 0
    local summoned = state and state.hero_summoned == 1
    local enough_rebirth = rebirth >= required
    local enough_gold = not resources
        or (tonumber(resources.gold) or 0) >= (tonumber(action.gold_cost) or 0)
    local status = "可施法"
    if not summoned then
        status = "前置条件：请先召唤英雄"
    elseif not enough_rebirth then
        status = "前置条件：英雄达到" .. tostring(required) .. "转"
    elseif not enough_gold then
        status = "前置条件：需要" .. tostring(action.gold_cost or 0) .. "金币"
    end
    return {
        available = summoned and enough_rebirth and 1 or 0,
        can_afford = enough_gold and 1 or 0,
        status_text = status,
        cost_wood = tonumber(action.wood_cost) or 0,
        cost_gold = tonumber(action.gold_cost) or 0,
        fields = {
            { label = "技能状态", value = status },
            { label = "解锁条件", value = required > 0
                and ("英雄" .. tostring(required) .. "转") or "无" },
            { label = "每秒消耗", value = (tonumber(action.gold_cost_per_second) or 0) > 0
                and (tostring(action.gold_cost_per_second) .. "金币") or "无" },
            { label = "成长收益", value = (tonumber(action.training_room_income_multiplier) or 1) > 1
                and (tostring(action.training_room_income_multiplier) .. "倍") or "正常" },
        },
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
    local travel = altar_travel(ability_name, state, resources)
    if travel then return travel end
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
        return mine_level_upgrade(state, resources)
    end
    if ability_name == "ability_upgrade_gold_mine_efficiency" then
        return mine_efficiency(state, resources)
    end
    if ability_name == "ability_upgrade_gold_mine_crit" then
        return mine_crit(state, resources)
    end
    if ability_name == "ability_gold_mine_auto_upgrade" then
        return {
            available = 1,
            can_afford = 1,
            current_level = state.mine_level or state.level or 1,
            status_text = state.auto_upgrading == 1
                and "停止自动升级"
                or "自动升级：本体→收益→暴击",
            upgrade_description = "自动依次升级金矿本体、采金效率和采金暴击。",
        }
    end
    if ability_name == "ability_gold_mine_stop_auto_upgrade" then
        return {
            available = state.auto_upgrading == 1 and 1 or 0,
            can_afford = 1,
            current_level = state.mine_level or state.level or 1,
            status_text = "停止自动升级",
            upgrade_description = "停止自动升级并恢复尚未满级的金矿技能。",
        }
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
