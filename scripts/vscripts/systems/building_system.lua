local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/buildings_config")
local logger = require("core/logger")

local M = {}
local buildings = {}
local counts = {}
local wall_ever_built = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function notify(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end

local function count_for(team, building_id)
    counts[team] = counts[team] or {}
    return counts[team][building_id] or 0
end

local function change_count(team, building_id, delta)
    counts[team] = counts[team] or {}
    counts[team][building_id] = math.max(0, (counts[team][building_id] or 0) + delta)
end

local function set_attack_range(unit, attack_range)
    if unit.Script_SetAttackRange then
        unit:Script_SetAttackRange(attack_range)
    elseif unit.SetAttackRange then
        unit:SetAttackRange(attack_range)
    end
end

local function apply_initial_stats(unit, definition)
    local data = definition.id == "arrow_tower"
        and definition.pre_class_levels[1]
        or definition.levels[1]
    unit:SetBaseMaxHealth(data.health)
    unit:SetMaxHealth(data.health)
    unit:SetHealth(data.health)
    unit:SetPhysicalArmorBaseValue(data.armor)

    if definition.id == "arrow_tower" then
        unit:SetBaseDamageMin(data.damage)
        unit:SetBaseDamageMax(data.damage)
        unit:SetBaseAttackTime(data.attack_rate)
        set_attack_range(unit, data.attack_range)
    end
end

local function add_ability(unit, ability_name, active)
    local ability = unit:FindAbilityByName(ability_name) or unit:AddAbility(ability_name)
    if ability then
        ability:SetLevel(1)
        ability:SetActivated(active ~= false)
    end
end

local function add_building_abilities(unit, definition)
    for _, ability_name in ipairs(definition.abilities or {}) do
        add_ability(unit, ability_name, true)
    end
    if definition.id == "arrow_tower" then
        for _, class_data in pairs(definition.class_options) do
            add_ability(unit, class_data.ability, false)
        end
    end
end

local function public_state(state)
    return {
        entindex = state.unit:entindex(),
        unit = state.unit,
        definition = state.definition,
        team = state.team,
        player_id = state.player_id,
        building_id = state.building_id,
        level = state.level,
        tower_class = state.tower_class,
        tower_class_name = state.tower_class_name,
    }
end

local function can_place(payload)
    local definition = config[payload.building_id]
    local caster = payload.caster
    if not definition or not valid_entity(caster) then
        return { ok = false, error = "invalid_build_request" }
    end

    local team = caster:GetTeamNumber()
    if definition.build_once and wall_ever_built[team] then
        return { ok = false, error = "城墙整局只能建造一次" }
    end
    if definition.max_count > 0 and count_for(team, definition.id) >= definition.max_count then
        return { ok = false, error = "建筑数量已达上限" }
    end

    local grid = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position = payload.position,
        footprint = definition.footprint,
    })
    if not grid or not grid.ok then
        return grid or { ok = false, error = "建造位置验证失败" }
    end

    return {
        ok = true,
        definition = definition,
        team = team,
        player_id = caster:GetPlayerOwnerID(),
        grid = grid,
    }
end

local function create_building(payload)
    local check = can_place(payload)
    if not check.ok then
        notify(payload.caster and payload.caster:GetPlayerOwnerID() or -1, check.error, "error")
        return check
    end

    local cost = check.definition.build_cost
    local spend = event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        team = check.team,
        wood = cost.wood,
        gold = cost.gold,
        population = 0,
        reason = "build:" .. check.definition.id,
    })
    if not spend or not spend.ok then
        notify(check.player_id, spend and spend.error or "资源扣除失败", "error")
        return spend
    end

    local unit = CreateUnitByName(
        check.definition.unit_name,
        check.grid.world_position,
        true,
        payload.caster,
        payload.caster,
        check.team
    )
    if not unit then
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = check.team,
            wood = cost.wood,
            gold = cost.gold,
            reason = "build_refund:" .. check.definition.id,
        })
        notify(check.player_id, "建筑创建失败", "error")
        return { ok = false, error = "building_create_failed" }
    end

    unit:SetControllableByPlayer(check.player_id, true)
    unit:AddNewModifier(unit, nil, "modifier_building_stationary", {})
    if not check.definition.show_health_bar then
        unit:AddNewModifier(unit, nil, "modifier_building_no_health_bar", {})
    end
    add_building_abilities(unit, check.definition)
    apply_initial_stats(unit, check.definition)

    local state = {
        unit = unit,
        definition = check.definition,
        team = check.team,
        player_id = check.player_id,
        building_id = check.definition.id,
        level = 1,
        grid_x = check.grid.grid_x,
        grid_y = check.grid.grid_y,
        tower_class = nil,
        tower_class_name = nil,
    }
    buildings[unit:entindex()] = state
    change_count(check.team, check.definition.id, 1)
    if check.definition.build_once then wall_ever_built[check.team] = true end

    event_bus.request(events.GRID_OCCUPY_REQUEST, {
        grid_x = state.grid_x,
        grid_y = state.grid_y,
        footprint = state.definition.footprint,
        entindex = unit:entindex(),
    })

    if state.building_id == "main_city" then
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = state.team,
            max_population = state.definition.levels[1].add_population or 0,
            reason = "main_city_created",
        })
    end

    local data = public_state(state)
    event_bus.emit(events.BUILDING_CREATED, data)
    data.reason = "created"
    event_bus.emit(events.BUILDING_CHANGED, data)
    notify(state.player_id, state.definition.display_name .. "已建造")
    return { ok = true, entindex = unit:entindex() }
end

local function query_building(payload)
    local state = buildings[payload.entindex]
    if not state or not valid_entity(state.unit) then return nil end
    return public_state(state)
end

local function on_building_changed(payload)
    local state = buildings[payload.entindex]
    if not state then return end
    state.level = payload.level or state.level
    state.tower_class = payload.tower_class
    state.tower_class_name = payload.tower_class_name
end

local function on_entity_killed(payload)
    local victim = payload.victim
    if not valid_entity(victim) then return end
    local state = buildings[victim:entindex()]
    if not state then return end

    buildings[victim:entindex()] = nil
    change_count(state.team, state.building_id, -1)
    event_bus.request(events.GRID_RELEASE_REQUEST, {
        grid_x = state.grid_x,
        grid_y = state.grid_y,
        footprint = state.definition.footprint,
    })
    event_bus.emit(events.BUILDING_DESTROYED, public_state(state))
    if state.building_id == "main_city" then
        GameRules:SetGameWinner(DOTA_TEAM_BADGUYS)
    end
end

function M.init()
    buildings = {}
    counts = {}
    wall_ever_built = {}
    event_bus.handle_request(events.BUILD_CAN_PLACE_REQUEST, can_place)
    event_bus.handle_request(events.BUILDING_QUERY_REQUEST, query_building)
    event_bus.subscribe(events.BUILD_REQUEST, create_building)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
    logger.info("BuildingSystem", "initialized")
end

return M
