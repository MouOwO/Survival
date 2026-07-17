local event_bus = require("core/event_bus")
local events = require("core/events")
local builder = require("ui/ability_runtime_builder")
local buildings = require("config/buildings_config")
local builder_config = require("config/builder_config")

local M = {}
local state_by_unit = {}
local ability_keys_by_unit = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function unit_from_payload(payload)
    if valid_entity(payload.unit) then return payload.unit end
    if not payload.entindex then return nil end
    local ok, entity = pcall(EntIndexToHScript, payload.entindex)
    return ok and valid_entity(entity) and entity or nil
end

local function get_resources(team)
    if not team then return nil end
    return event_bus.request(events.RESOURCE_GET_REQUEST, { team = team })
end

local function normalize_state(payload, unit)
    local previous = state_by_unit[unit:entindex()] or {}
    return {
        unit = unit,
        team = payload.team or previous.team or unit:GetTeamNumber(),
        building_id = payload.building_id or previous.building_id,
        level = payload.level or previous.level or 1,
        tower_class = payload.tower_class ~= nil and payload.tower_class
            or previous.tower_class,
        tower_class_name = payload.tower_class_name ~= nil
            and payload.tower_class_name or previous.tower_class_name,
        city_level = payload.city_level ~= nil
            and payload.city_level or previous.city_level or 0,
        mine_level = payload.mine_level ~= nil
            and payload.mine_level or previous.mine_level or 1,
        crit_level = payload.crit_level ~= nil
            and payload.crit_level or previous.crit_level or 0,
    }
end

local function configured_ability_names(state)
    if state.building_id == "builder" then return builder_config.abilities or {} end
    local definition = buildings[state.building_id]
    if not definition then return {} end

    local names = {}
    for _, ability_name in ipairs(definition.abilities or {}) do
        table.insert(names, ability_name)
    end
    if state.building_id == "arrow_tower" then
        for _, class_data in pairs(definition.class_options or {}) do
            table.insert(names, class_data.ability)
        end
    end
    return names
end

local function clear_removed_keys(unit_key, current_keys)
    local previous = ability_keys_by_unit[unit_key] or {}
    for ability_entindex, _ in pairs(previous) do
        if not current_keys[ability_entindex] then
            CustomNetTables:SetTableValue(
                "survival_ability_runtime",
                tostring(ability_entindex),
                { removed = 1 }
            )
        end
    end
end

local function publish_state(state)
    local unit = state.unit
    if not valid_entity(unit) then return end
    local unit_key = unit:entindex()
    state_by_unit[unit_key] = state
    local resources = get_resources(state.team)
    local current_keys = {}

    for _, ability_name in ipairs(configured_ability_names(state)) do
        local ability = unit:FindAbilityByName(ability_name)
        if ability and not ability:IsNull() then
            local runtime = builder.build(ability_name, state, resources)
            runtime.ability_name = ability_name
            runtime.owner_entindex = unit_key
            runtime.ability_entindex = ability:entindex()
            runtime.resource_version = resources and resources.version or 0
            CustomNetTables:SetTableValue(
                "survival_ability_runtime",
                tostring(ability:entindex()),
                runtime
            )
            current_keys[ability:entindex()] = true
        end
    end

    clear_removed_keys(unit_key, current_keys)
    ability_keys_by_unit[unit_key] = current_keys
end

local function publish_unit(payload)
    local unit = unit_from_payload(payload)
    if not unit then return end
    publish_state(normalize_state(payload, unit))
end

local function clear_unit(payload)
    local entindex = payload.entindex
    local keys = entindex and ability_keys_by_unit[entindex] or nil
    if keys then
        for ability_entindex, _ in pairs(keys) do
            CustomNetTables:SetTableValue(
                "survival_ability_runtime",
                tostring(ability_entindex),
                { removed = 1 }
            )
        end
    end
    ability_keys_by_unit[entindex] = nil
    state_by_unit[entindex] = nil
end

local function on_resource_changed(payload)
    for _, unit_state in pairs(state_by_unit) do
        if unit_state.team == payload.team then publish_state(unit_state) end
    end
end

local function on_hero_ready(payload)
    publish_unit({
        unit = payload.hero,
        team = payload.team,
        level = 1,
        building_id = "builder",
    })
end

function M.init()
    state_by_unit = {}
    ability_keys_by_unit = {}
    event_bus.subscribe(events.HERO_READY, on_hero_ready)
    event_bus.subscribe(events.BUILDING_CREATED, publish_unit)
    event_bus.subscribe(events.BUILDING_CHANGED, publish_unit)
    event_bus.subscribe(events.BUILDING_DESTROYED, clear_unit)
    event_bus.subscribe(events.BUILDER_UNLOCK_CHANGED, publish_unit)
    event_bus.subscribe(events.GOLD_MINE_CHANGED, publish_unit)
    event_bus.subscribe(events.RESOURCE_CHANGED, on_resource_changed)
end

return M
