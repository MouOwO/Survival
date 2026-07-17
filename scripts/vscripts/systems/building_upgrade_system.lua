local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local buildings = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function notify(state, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = state.player_id,
        message = message,
        level = level or "info",
    })
end

local function set_attack_range(unit, attack_range)
    if unit.Script_SetAttackRange then
        unit:Script_SetAttackRange(attack_range)
    elseif unit.SetAttackRange then
        unit:SetAttackRange(attack_range)
    end
end

local function apply_common(unit, data)
    unit:SetBaseMaxHealth(data.health)
    unit:SetMaxHealth(data.health)
    unit:SetHealth(data.health)
    unit:SetPhysicalArmorBaseValue(data.armor)
end

local function apply_tower(unit, data)
    apply_common(unit, data)
    unit:SetBaseDamageMin(data.damage)
    unit:SetBaseDamageMax(data.damage)
    unit:SetBaseAttackTime(data.attack_rate)
    set_attack_range(unit, data.attack_range)
end

local function set_class_buttons(unit, active)
    local state = buildings[unit:entindex()]
    if not state then return end
    for _, class_data in pairs(state.definition.class_options) do
        local ability = unit:FindAbilityByName(class_data.ability)
        if ability then ability:SetActivated(active) end
    end
end

local function publish(state, reason)
    event_bus.emit(events.BUILDING_CHANGED, {
        entindex = state.unit:entindex(),
        team = state.team,
        player_id = state.player_id,
        building_id = state.building_id,
        level = state.level,
        tower_class = state.tower_class,
        tower_class_name = state.tower_class_name,
        reason = reason,
    })
end

local function spend(state, cost, reason)
    if not cost then return { ok = false, error = "升级费用未配置" } end
    return event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        team = state.team,
        wood = cost.wood or 0,
        gold = cost.gold or 0,
        population = 0,
        reason = reason,
    })
end

local function upgrade_wall(state)
    local next_level = state.level + 1
    local data = state.definition.levels[next_level]
    if not data then return { ok = false, error = "城墙已达最高等级" } end
    local result = spend(state, data.upgrade_cost, "upgrade_wall")
    if not result or not result.ok then return result end
    state.level = next_level
    apply_common(state.unit, data)
    publish(state, "wall_upgraded")
    return { ok = true }
end

local function upgrade_city(state)
    local next_level = state.level + 1
    local data = state.definition.levels[next_level]
    if not data then return { ok = false, error = "主城已达最高等级" } end
    local result = spend(state, data.upgrade_cost, "upgrade_city")
    if not result or not result.ok then return result end
    state.level = next_level
    apply_common(state.unit, data)
    if data.add_population then
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = state.team,
            max_population = data.add_population,
            reason = "city_level_population",
        })
    end
    publish(state, "city_upgraded")
    return { ok = true }
end

local function post_class_data(state, next_level)
    local base = state.definition.pre_class_levels[5]
    local growth = state.definition.post_class_upgrade
    local extra = next_level - 5
    return {
        health = base.health + growth.health_per_level * extra,
        armor = base.armor + growth.armor_per_level * extra,
        damage = base.damage + growth.damage_per_level * extra,
        attack_range = base.attack_range + growth.range_per_level * extra,
        attack_rate = math.max(
            growth.min_attack_rate,
            base.attack_rate - growth.attack_rate_reduction_per_level * extra
        ),
    }
end

local function upgrade_tower(state)
    if not state.tower_class then
        if state.level >= 5 then
            set_class_buttons(state.unit, true)
            return { ok = false, error = "请先选择防御塔转职" }
        end
        local next_level = state.level + 1
        local data = state.definition.pre_class_levels[next_level]
        local result = spend(state, data.upgrade_cost, "upgrade_tower")
        if not result or not result.ok then return result end
        state.level = next_level
        apply_tower(state.unit, data)
        if state.level == 5 then set_class_buttons(state.unit, true) end
        publish(state, "tower_upgraded")
        return { ok = true }
    end

    local next_level = state.level + 1
    local growth = state.definition.post_class_upgrade
    local extra = next_level - 5
    local cost = {
        wood = growth.wood_base + growth.wood_per_level * math.max(0, extra - 1),
        gold = growth.gold_base + growth.gold_per_level * math.max(0, extra - 1),
    }
    local result = spend(state, cost, "upgrade_tower_post_class")
    if not result or not result.ok then return result end
    state.level = next_level
    apply_tower(state.unit, post_class_data(state, next_level))
    publish(state, "tower_upgraded_post_class")
    return { ok = true }
end

local function on_upgrade_request(payload)
    local unit = payload.building
    if not valid_entity(unit) then return end
    local state = buildings[unit:entindex()]
    if not state then return end

    local result
    if state.building_id == "wall" then result = upgrade_wall(state)
    elseif state.building_id == "main_city" then result = upgrade_city(state)
    elseif state.building_id == "arrow_tower" then result = upgrade_tower(state)
    else result = { ok = false, error = "该建筑不能升级" } end

    notify(state, result and result.ok and "升级成功" or (result and result.error or "升级失败"),
        result and result.ok and "info" or "error")
end

local function on_class_request(payload)
    local unit = payload.tower
    if not valid_entity(unit) then return end
    local state = buildings[unit:entindex()]
    if not state or state.building_id ~= "arrow_tower" then return end
    if state.level < 5 then notify(state, "防御塔未达到5级", "error"); return end
    if state.tower_class then notify(state, "防御塔已经完成转职", "error"); return end

    local class_data = state.definition.class_options[payload.class_index]
    if not class_data then notify(state, "无效的转职方向", "error"); return end
    local result = spend(state, state.definition.class_change_cost, "tower_class_change")
    if not result or not result.ok then
        notify(state, result and result.error or "资源不足", "error")
        return
    end

    state.tower_class = class_data.id
    state.tower_class_name = class_data.display_name
    set_class_buttons(state.unit, false)
    publish(state, "tower_class_changed")
    notify(state, "防御塔已转职为" .. class_data.display_name)
end

local function on_created(payload)
    buildings[payload.entindex] = {
        unit = payload.unit,
        definition = payload.definition,
        team = payload.team,
        player_id = payload.player_id,
        building_id = payload.building_id,
        level = payload.level or 1,
        tower_class = nil,
        tower_class_name = nil,
    }
end

local function on_destroyed(payload)
    buildings[payload.entindex] = nil
end

function M.init()
    buildings = {}
    event_bus.subscribe(events.BUILDING_CREATED, on_created)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_destroyed)
    event_bus.subscribe(events.BUILDING_UPGRADE_REQUEST, on_upgrade_request)
    event_bus.subscribe(events.TOWER_CLASS_REQUEST, on_class_request)
end

return M
