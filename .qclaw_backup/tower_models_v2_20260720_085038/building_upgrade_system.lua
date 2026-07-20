local event_bus = require("core/event_bus")
local events = require("core/events")
local arrow_tower_base = require("config/generated/arrow_tower_base")
local tower_routes = require("config/tower_route_config")
local tower_skills = require("systems/tower_skill_runtime")
local tower_ability_sync = require("systems/tower_ability_sync")

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
    if unit.SetAcquisitionRange then
        unit:SetAcquisitionRange(10)
    end
end

local function apply_common(unit, data)
    unit:SetBaseMaxHealth(data.health)
    unit:SetMaxHealth(data.health)
    unit:SetHealth(data.health)
    unit:SetPhysicalArmorBaseValue(data.armor)
    if data.model_name and data.model_name ~= "" then
        unit:SetModel(data.model_name)
        unit:SetOriginalModel(data.model_name)
    end
end

local function arrow_data(level)
    for _, row in ipairs(arrow_tower_base.rows) do
        if row.level == level then return row end
    end
    return nil
end

local function apply_tower(unit, data, level)
    apply_common(unit, data)
    local combat = arrow_data(level or 1) or {}
    unit:SetBaseDamageMin(combat.base_attack_damage or data.damage)
    unit:SetBaseDamageMax(combat.base_attack_damage or data.damage)
    unit:SetBaseAttackTime(combat.attack_speed or data.attack_rate)
    set_attack_range(unit, data.attack_range)
end

local function set_class_buttons(unit, active)
    local state = buildings[unit:entindex()]
    if not state then return end
    for _, class_data in pairs(state.definition.class_options) do
        local ability = unit:FindAbilityByName(class_data.ability)
        if active and not ability then
            ability = unit:AddAbility(class_data.ability)
            if ability then ability:SetLevel(1) end
        end
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
        display_name = state.tower_class_name
            or ((tower_routes.current(state) or {}).name),
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
    if next_level > 1 and data.requires_city_level
        and data.requires_city_level > 0 then
        local city_level = 0
        for _, building in pairs(buildings) do
            if building.team == state.team
                and building.building_id == "main_city"
                and valid_entity(building.unit) then
                city_level = math.max(city_level, building.level or 0)
            end
        end
        if city_level < data.requires_city_level then
            return {
                ok = false,
                error = "基地达到Lv." .. tostring(data.requires_city_level)
                    .. "后才能升级城墙",
            }
        end
    end
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

local function route_unit_data(state, row)
    return {
        health = state.unit:GetMaxHealth(),
        armor = state.unit:GetPhysicalArmorBaseValue(),
        damage = row.base_attack_damage,
        attack_range = 675,
        attack_rate = row.attack_speed or 0.9,
    }
end

local function sync_tower_abilities(state, row)
    tower_ability_sync.sync(state, row)
end

local function apply_model(unit, row)
    if not row or not row.model_name or row.model_name == "" then return end
    unit:SetModel(row.model_name)
    unit:SetOriginalModel(row.model_name)
end

local function apply_tower_level(state, row, level, change_model)
    apply_tower(state.unit, route_unit_data(state, row), level)
    if change_model then apply_model(state.unit, row) end
    state.level = level
    state.tower_class_name = state.tower_class and tower_routes.display_name(row) or row.name
    sync_tower_abilities(state, row)
    tower_skills.apply(state.unit, row.skill_ids)
end

local function upgrade_tower(state, mode)
    if not state.tower_class and state.level >= 5 then
        set_class_buttons(state.unit, true)
        return { ok = false, error = "请先选择防御塔转职" }
    end
    local target = mode == "max" and tower_routes.stage_end_level(state)
        or state.level + 1
    local final_row = tower_routes.row_at_level(state, target)
    local cost = tower_routes.cost_to(state, target)
    if target <= state.level or not final_row or not cost then
        return { ok = false, error = "防御塔已达当前阶段最高等级" }
    end
    local result = spend(state, cost, "upgrade_tower_" .. tostring(mode or "one"))
    if not result or not result.ok then return result end
    local previous_row = tower_routes.current(state)
    local stage_changed = previous_row
        and previous_row.stage_id ~= final_row.stage_id
    apply_tower_level(state, final_row, target, stage_changed)
    if cost.population > 0 then
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = state.team, max_population = cost.population,
            reason = "tower_route_population",
        })
    end
    if not state.tower_class and state.level == 5 then
        sync_tower_abilities(state, final_row)
        set_class_buttons(state.unit, true)
    end
    publish(state, "tower_upgraded_" .. tostring(mode or "one"))
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
    elseif state.building_id == "arrow_tower" then result = upgrade_tower(state, payload.upgrade_mode or "one")
    else result = { ok = false, error = "该建筑不能升级" } end

    if not result or not result.ok then
        local ability_name = payload.upgrade_mode == "max"
            and "ability_upgrade_tower_max"
            or "ability_upgrade_tower_lv01"
        local ability = unit:FindAbilityByName(ability_name)
        if ability then ability:EndCooldown() end
    end
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
    local row = tower_routes.get(class_data.id, 1)
    if not row then notify(state, "路线配置缺失", "error"); return end
    local result = spend(state, {
        wood = row.upgrade_wood, gold = row.upgrade_gold,
    }, "tower_class_change")
    if not result or not result.ok then
        notify(state, result and result.error or "资源不足", "error")
        return
    end

    state.tower_class = class_data.id
    apply_tower_level(state, row, 6, true)
    if row.population_delta and row.population_delta > 0 then
        event_bus.request(events.RESOURCE_ADD_REQUEST, { team = state.team, max_population = row.population_delta, reason = "tower_route_population" })
    end
    set_class_buttons(state.unit, false)
    publish(state, "tower_class_changed")
    notify(state, "防御塔已转职为" .. state.tower_class_name)
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
        tower_combat = nil,
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
