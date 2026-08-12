local buildings = require("config/buildings_config")
local gold_mine = require("config/gold_mine_config")
local tower_routes = require("config/tower_route_config")
local altar_actions = require("config/generated/altar_actions")
local training_definitions = require("config/generated/training_definitions")
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
local function value_delta(current, target, suffix)
    current = tonumber(current)
    target = tonumber(target)
    if not current or not target then return nil end
    local delta = target - current
    local sign = delta >= 0 and "+" or ""
    return tostring(current) .. " → " .. tostring(target)
        .. " (" .. sign .. tostring(delta) .. (suffix or "") .. ")"
end
local function mark_upgrade_state(data, state)
    if state and state.upgrade_in_progress == 1 then
        data.available = 0
        data.can_afford = 0
        data.upgrade_in_progress = 1
        data.status_text = "升级中（1秒）"
        data.target_model_asset_id = state.upgrade_target_model_asset_id
        data.target_model_path = state.upgrade_target_model_path
        data.upgrade_model_status = state.upgrade_model_status
        data.fields = data.fields or {}
        data.fields[#data.fields + 1] = {
            label = "模型状态",
            value = state.upgrade_model_status or "unchanged",
        }
    end
    return data
end
local function count(state, building_id)
    return state.building_counts
        and state.building_counts[building_id] or 0
end
local function default_lumberjack_training()
    local row = (training_definitions.by_id or {}).train_lumberjack_01 or {}
    local level = tonumber(row.level) or 1
    return {
        training_id = row.training_id or "train_lumberjack_01",
        level = level,
        name = row.name or "农民LV1",
        count = 0,
        max_count = tonumber(row.max_count) or 0,
        unlimited = (tonumber(row.max_count) or 0) < 0 and 1 or 0,
        requires_city_level = tonumber(row.requires_city_level) or 1,
        wood_cost = tonumber(row.wood_cost) or 0,
        gold_cost = tonumber(row.gold_cost) or 0,
        population_cost = tonumber(row.population_cost) or 0,
        wood_per_hit = tonumber(row.wood_per_hit) or 0,
        base_attack = tonumber(row.base_attack) or 0,
    }
end
local function lumberjack_training(state, resources)
    local training = event_bus.request(events.WORKER_TRAINING_GET_REQUEST, {
        team = state.team,
    }) or default_lumberjack_training()
    local required = tonumber(training.requires_city_level) or 1
    local city_level = tonumber(state.level) or tonumber(state.city_level) or 1
    local unlocked = city_level >= required
    local maximum = tonumber(training.max_count) or 0
    local trained = tonumber(training.count) or 0
    local progress_text = maximum < 0 and "无限训练"
        or (tostring(trained) .. "/" .. tostring(maximum))
    local cost = {
        wood = tonumber(training.wood_cost) or 0,
        gold = tonumber(training.gold_cost) or 0,
    }
    local population = tonumber(training.population_cost) or 0
    local status = unlocked
        and ("当前等级训练进度 " .. progress_text)
        or ("主城达到LV" .. tostring(required) .. "后解锁")
    local result = merge({
        available = unlocked and 1 or 0,
        display_name = "训练" .. tostring(training.name or "农民LV1"),
        current_level = tonumber(training.level) or 1,
        status_text = status,
        upgrade_description = "训练一名" .. tostring(training.name or "农民")
            .. "，自动攻击资源树。每次有效攻击获得"
            .. tostring(training.wood_per_hit or 0) .. "木材。",
        population = population,
        fields = {
            { label = "训练进度", value = progress_text },
            { label = "占用人口", value = population },
            { label = "基础攻击力", value = training.base_attack or 0 },
            { label = "每次伐木", value = tostring(training.wood_per_hit or 0) .. "木材" },
            { label = "主城要求", value = "LV" .. tostring(required) },
        },
    }, cost_data(cost))
    return with_affordability(result, cost, population, resources)
end
local function repairer_training(state, resources, training_id)
    local training = event_bus.request(events.WORKER_TRAINING_GET_REQUEST, {
        team = state.team,
        training_type = "repairer",
        training_id = training_id,
    }) or {}
    local required = tonumber(training.requires_city_level) or 1
    local city_level = tonumber(state.level) or tonumber(state.city_level) or 1
    local maximum = tonumber(training.max_count) or 0
    local trained = tonumber(training.count) or 0
    local completed = training.completed == 1
        or (maximum > 0 and trained >= maximum)
    local unlocked = not completed and city_level >= required
    local progress_text = maximum < 0 and "无限训练"
        or (tostring(trained) .. "/" .. tostring(maximum))
    local cost = {
        wood = tonumber(training.wood_cost) or 0,
        gold = tonumber(training.gold_cost) or 0,
    }
    local population = tonumber(training.population_cost) or 0
    local status = "修理工数量已达上限"
    if not completed then
        status = unlocked
            and ("当前修理工数量 " .. progress_text)
            or ("主城达到LV" .. tostring(required) .. "后解锁")
    end
    local repair_rate = tonumber(training.repair_max_health_pct_per_second) or 0
    local result = merge({
        available = unlocked and 1 or 0,
        display_name = "训练" .. tostring(training.name or "修理工"),
        current_level = tonumber(training.level) or 1,
        status_text = status,
        upgrade_description = "训练一名" .. tostring(training.name or "修理工")
            .. "，自动修复受损城墙。每秒修复最大生命值的"
            .. tostring(repair_rate) .. "%。",
        population = population,
        fields = {
            { label = "当前数量", value = progress_text },
            { label = "人口消耗", value = population },
            { label = "木材消耗", value = cost.wood },
            { label = "金币消耗", value = cost.gold },
            { label = "修复效率", value = tostring(repair_rate) .. "%最大生命/秒" },
            { label = "修理范围", value = training.repair_range or 0 },
            { label = "训练上限", value = maximum < 0 and "无限" or maximum },
        },
    }, cost_data(cost))
    if completed then
        result.can_afford = 0
        return result
    end
    return with_affordability(result, cost, population, resources)
end
local function population_training(state, resources)
    local training = event_bus.request(events.WORKER_TRAINING_GET_REQUEST, {
        team = state.team,
        training_type = "population_upgrade",
    }) or {}
    local trained = tonumber(training.count) or 0
    local maximum = tonumber(training.max_count) or 0
    local completed = training.completed == 1
        or (maximum > 0 and trained >= maximum)
    local required = tonumber(training.requires_farm_level) or 1
    local farm_level = tonumber(state.level) or 1
    local unlocked = not completed and farm_level >= required
    local progress_text = tostring(trained) .. "/" .. tostring(maximum)
    local cost = {
        wood = completed and 0 or (tonumber(training.wood_cost) or 0),
        gold = completed and 0 or (tonumber(training.gold_cost) or 0),
    }
    local training_name = tostring(training.name or "人口训练")
    local status = "人口训练已全部完成"
    if not completed then
        status = unlocked and (training_name .. "可训练（第"
            .. tostring(trained + 1) .. "次）")
            or ("农场达到LV" .. tostring(required) .. "后解锁")
    end
    local fields = {
        { label = "当前阶段", value = training_name },
        { label = "阶段进度", value = progress_text },
    }
    if not completed then
        fields[#fields + 1] = {
            label = "本次增加人口",
            value = "+" .. tostring(training.population_add or 0),
        }
        fields[#fields + 1] = {
            label = "本次条件",
            value = tostring(training.prerequisite_text or ("农场LV" .. tostring(required))),
        }
        fields[#fields + 1] = {
            label = "下一级条件",
            value = tostring(training.next_prerequisite_text or "已完成"),
        }
    end
    local result = merge({
        available = unlocked and 1 or 0,
        current_level = tonumber(training.level) or 0,
        next_level = completed and nil or (tonumber(training.level) or 0),
        status_text = status,
        upgrade_description = completed
            and "所有人口训练阶段均已达到CSV配置的次数上限。"
            or "当前阶段达到次数上限后自动加载下一人口训练阶段；费用与人口收益由CSV配置决定。",
        fields = fields,
    }, cost_data(cost))
    if completed then result.can_afford = 0 end
    return completed and result or with_affordability(result, cost, 0, resources)
end
local function build_ability(ability_name, state, resources)
    local definitions = {
        ability_build_wall = buildings.wall,
        ability_build_main_city = buildings.main_city,
        ability_build_arrow_tower = buildings.arrow_tower,
        ability_build_farm = buildings.building_farm,
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
local function upgrade_level(definition, current_level, resources, state)
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
    local current_data = definition.levels and definition.levels[current_level] or {}
    local fields = {
        { label = "等级", value = tostring(current_level) .. " → " .. tostring(next_level) },
    }
    local health = value_delta(current_data.health, data.health)
    local armor = definition.id == "wall"
        and value_delta(current_data.war3_armor, data.war3_armor)
        or value_delta(current_data.armor, data.armor)
    local population = value_delta(
        current_data.max_population or current_data.population,
        data.max_population or data.population
    )
    if not population and (tonumber(data.add_population) or 0) ~= 0 then
        population = "+" .. tostring(data.add_population)
    end
    if health then fields[#fields + 1] = { label = "生命", value = health } end
    if armor then fields[#fields + 1] = { label = "护甲", value = armor } end
    if population then fields[#fields + 1] = { label = "人口上限", value = population } end
    local result = merge({
        available = 1,
        current_level = current_level,
        next_level = next_level,
        status_text = "可以升级",
        fields = fields,
    }, cost_data(data.upgrade_cost))
    return mark_upgrade_state(with_affordability(
        result,
        data.upgrade_cost,
        0,
        resources
    ), state)
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
    local tower_name = tower_routes.display_name(row)
    local attack_delta = (row.base_attack_damage or 0)
        - (current_row and current_row.base_attack_damage or 0)
    local description = (mode == "max"
        and "一次升级至当前阶段允许的最高等级："
        or "按当前路线升级至下一等级：")
        .. tostring(tower_name) .. "。升级后攻击力 +"
        .. tostring(attack_delta) .. "。"
    local result = merge({
        available = 1, current_level = state.level, next_level = target,
        status_text = (mode == "max" and "升满至" or "升级至")
            .. tower_name,
        tower_name = tower_name, skill_ids = row.skill_ids,
        upgrade_description = description,
        target_level = target,
        upgrade_attack_delta = attack_delta,
        population = cost.population or 0,
        fields = {
            { label = "目标等级", value = target },
            { label = "升级目标", value = tower_name },
            { label = "攻击提升", value = "+" .. tostring(attack_delta) },
            { label = "攻击速度", value = value_delta(
                current_row and current_row.base_attack_speed,
                row.base_attack_speed
            ) },
            { label = "人口消耗", value = (tonumber(cost.population) or 0) > 0
                and tostring(cost.population)
                or ((tonumber(row.population_occupied) or 0) > 0
                    and ("0（当前占有" .. tostring(row.population_occupied) .. "）")
                    or "0") },
        },
    }, cost_data(cost))
    local affordable = can_afford(cost, cost.population or 0, resources)
    result.can_afford = affordable
    if affordable == 0 then
        result.status_text = result.status_text .. "（当前资源不足）"
    end
    return mark_upgrade_state(result, state)
end
local function tower_class(ability_name, state, resources)
    local available = state.level >= 5 and not state.tower_class
    local class_index = tonumber(string.match(ability_name, "(%d+)$"))
    local class_id = class_index and "class_" .. tostring(class_index) or nil
    local row = class_id and tower_routes.get(class_id, 1) or nil
    local cost = tower_routes.class_change_cost(row, state)
    local class_count = state.tower_class_counts
        and state.tower_class_counts[class_id] or {}
    local completed = tonumber(class_count.count) or 0
    local pending = tonumber(class_count.pending) or 0
    local maximum = tonumber(class_count.maximum) or 5
    local class_full = maximum > 0 and completed + pending >= maximum
    available = available and not class_full
    local result = merge({
        available = available and row and 1 or 0,
        current_level = state.level,
        status_text = class_full and ("该路线数量已达上限（"
                .. tostring(completed + pending) .. "/" .. tostring(maximum) .. "）")
            or (available and row and "转职为" .. tower_routes.display_name(row)
                or (state.tower_class and "已经完成转职"
                    or "防御塔未达到5级")),
        tower_name = row and tower_routes.display_name(row) or "",
        skill_ids = row and row.skill_ids or nil,
        population = cost and cost.population or 0,
        fields = row and {
            {
                label = "人口消耗",
                value = tostring(cost and cost.population or 0),
            },
            {
                label = "转职后人口占有",
                value = tostring(row.population_occupied or 0),
            },
            {
                label = "路线数量",
                value = tostring(completed + pending) .. "/" .. tostring(maximum),
            },
        } or nil,
    }, cost_data(cost))
    return mark_upgrade_state(with_affordability(
        result,
        cost,
        cost and cost.population or 0,
        resources
    ), state)
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
    local current_data = gold_mine.level_data(level) or {}
    local target_data = gold_mine.level_data(level + 1) or {}
    local result = merge({
        available = 1,
        current_level = level,
        next_level = level + 1,
        status_text = "升级金矿本体至Lv." .. tostring(level + 1),
        upgrade_description = "提升金矿本体等级并提高基础金币产量。",
        fields = {
            { label = "等级", value = tostring(level) .. " → " .. tostring(level + 1) },
            { label = "生命", value = value_delta(current_data.health, target_data.health) },
            { label = "护甲", value = value_delta(current_data.armor, target_data.armor) },
            { label = "每秒金币", value = value_delta(
                state.income_per_second,
                gold_mine.normal_income(level + 1, state.efficiency_level or 0)
            ) },
        },
    }, cost_data(cost))
    return mark_upgrade_state(with_affordability(result, cost, 0, resources), state)
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
        fields = {
            { label = "科技等级", value = tostring(level) .. " → " .. tostring(level + 1) },
            { label = "效率", value = tostring(gold_mine.efficiency_percent(level))
                .. "% → " .. tostring(gold_mine.efficiency_percent(level + 1)) .. "%" },
            { label = "每秒金币", value = value_delta(
                state.income_per_second,
                gold_mine.normal_income(state.mine_level or 1, level + 1)
            ) },
        },
    }, cost_data(cost))
    return mark_upgrade_state(with_affordability(result, cost, 0, resources), state)
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
        fields = {
            { label = "科技等级", value = tostring(level) .. " → " .. tostring(level + 1) },
            { label = "暴击率", value = tostring(gold_mine.crit_chance(level))
                .. "% → " .. tostring(gold_mine.crit_chance(level + 1)) .. "%" },
            { label = "暴击倍率", value = tostring(gold_mine.crit_multiplier(
                state.mine_level or 1
            )) .. "x" },
        },
    }, cost_data(cost))
    return mark_upgrade_state(with_affordability(result, cost, 0, resources), state)
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
        return upgrade_level(buildings.wall, state.level, resources, state)
    end
    if ability_name == "ability_upgrade_city" then
        return upgrade_level(
            buildings.main_city,
            state.level,
            resources,
            state
        )
    end
    if ability_name == "ability_train_lumberjack" then
        return lumberjack_training(state, resources)
    end
    if ability_name == "ability_train_repairer" then
        return repairer_training(state, resources, "train_repairer_01")
    end
    if ability_name == "ability_train_advanced_repairer" then
        return repairer_training(state, resources, "train_repairer_02")
    end
    if ability_name == "ability_train_population" then
        return population_training(state, resources)
    end
    if ability_name == "ability_upgrade_farm" then
        return upgrade_level(buildings.farm, state.level, resources, state)
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
    if ability_name == "ability_tower_fusion" then
        local fusion = event_bus.request(events.TOWER_FUSION_ELIGIBILITY_REQUEST, {
            player_id = state.player_id,
        }) or {}
        local ready = tonumber(fusion.route_count) or 0
        local count = tonumber(fusion.ultimate_count) or 0
        local maximum = tonumber(fusion.maximum) or 5
        return {
            available = fusion.eligible == true and 1 or 0,
            can_afford = 1,
            status_text = count >= maximum
                and ("终极塔数量已达上限（" .. tostring(count) .. "/"
                    .. tostring(maximum) .. "）")
                or ("可用路线材料：" .. tostring(ready) .. "/7；终极塔："
                    .. tostring(count) .. "/" .. tostring(maximum)),
            fields = {
                { label = "未参与满级路线", value = tostring(ready) .. "/7" },
                { label = "终极塔数量", value = tostring(count) .. "/"
                    .. tostring(maximum) },
                { label = "材料消耗", value = "不消耗；每座塔永久限参与一次" },
            },
        }
    end
    return {
        available = 1,
        can_afford = 1,
        status_text = "",
    }
end
return M
