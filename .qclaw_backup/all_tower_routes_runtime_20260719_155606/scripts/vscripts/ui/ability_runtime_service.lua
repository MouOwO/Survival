local event_bus = require("core/event_bus")
local events = require("core/events")
local builder = require("ui/ability_runtime_builder")
local ability_utils = require("core/ability_utils")

local M = {}

local state_by_unit = {}
local ability_keys_by_unit = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function unit_from_payload(payload)
    if valid_entity(payload.unit) then
        return payload.unit
    end
    if not payload.entindex then
        return nil
    end
    local ok, entity = pcall(
        EntIndexToHScript,
        payload.entindex
    )
    return ok and valid_entity(entity) and entity or nil
end

local function resources(team)
    if not team then
        return nil
    end
    return event_bus.request(
        events.RESOURCE_GET_REQUEST,
        { team = team }
    )
end

local function normalize(payload, unit)
    local previous = state_by_unit[unit:entindex()] or {}
    return {
        unit = unit,
        team = payload.team or previous.team
            or unit:GetTeamNumber(),
        building_id = payload.building_id
            or previous.building_id,
        level = payload.level or previous.level or 1,
        tower_class = payload.tower_class ~= nil
            and payload.tower_class
            or previous.tower_class,
        tower_class_name =
            payload.tower_class_name ~= nil
            and payload.tower_class_name
            or previous.tower_class_name,
        city_level = payload.city_level ~= nil
            and payload.city_level
            or previous.city_level or 0,
        mine_level = payload.mine_level ~= nil
            and payload.mine_level
            or previous.mine_level or 1,
        crit_level = payload.crit_level ~= nil
            and payload.crit_level
            or previous.crit_level or 0,
        builder_stage = payload.builder_stage
            or previous.builder_stage or "",
        hero_summoned = payload.hero_summoned ~= nil
            and payload.hero_summoned
            or previous.hero_summoned or 0,
        building_counts = payload.building_counts
            or previous.building_counts or {},
    }
end

local function clear_removed(unit_key, current)
    local previous = ability_keys_by_unit[unit_key] or {}
    for ability_entindex, _ in pairs(previous) do
        if not current[ability_entindex] then
            CustomNetTables:SetTableValue(
                "survival_ability_runtime",
                tostring(ability_entindex),
                { removed = 1 }
            )
        end
    end
end

local function publish(state)
    local unit = state.unit
    if not valid_entity(unit) then
        return
    end

    local unit_key = unit:entindex()
    state_by_unit[unit_key] = state
    local resource_state = resources(state.team)
    local current = {}

    ability_utils.for_each(unit, function(ability)
        local ability_name = ability:GetAbilityName()
        local runtime = builder.build(
            ability_name,
            state,
            resource_state
        )
        runtime.ability_name = ability_name
        runtime.owner_entindex = unit_key
        runtime.ability_entindex = ability:entindex()
        runtime.resource_version =
            resource_state and resource_state.version or 0
        CustomNetTables:SetTableValue(
            "survival_ability_runtime",
            tostring(ability:entindex()),
            runtime
        )
        current[ability:entindex()] = true
    end)

    clear_removed(unit_key, current)
    ability_keys_by_unit[unit_key] = current
end

local function publish_unit(payload)
    local unit = unit_from_payload(payload)
    if unit then
        publish(normalize(payload, unit))
    end
end

local function clear_unit(payload)
    local entindex = payload.entindex
    local keys = entindex and ability_keys_by_unit[entindex]
        or nil
    for ability_entindex, _ in pairs(keys or {}) do
        CustomNetTables:SetTableValue(
            "survival_ability_runtime",
            tostring(ability_entindex),
            { removed = 1 }
        )
    end
    ability_keys_by_unit[entindex] = nil
    state_by_unit[entindex] = nil
end

local function on_resources(payload)
    for _, state in pairs(state_by_unit) do
        if state.team == payload.team then
            publish(state)
        end
    end
end

local function on_hero_summon_state(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then
        return
    end
    local team = PlayerResource:GetTeam(player_id)
    for _, state in pairs(state_by_unit) do
        if state.team == team then
            state.hero_summoned =
                tonumber(payload.hero_summoned) or 0
            publish(state)
        end
    end
end


local function on_hero_skill_changed(payload)
    local entindex = tonumber(payload.unit_entindex)
    if not entindex or entindex < 0 then
        return
    end
    publish_unit({
        entindex = entindex,
        building_id = "combat_hero",
        level = 1,
    })
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
    event_bus.subscribe(events.BUILDER_STAGE_CHANGED, publish_unit)
    event_bus.subscribe(
        events.HERO_SUMMON_STATE_CHANGED,
        on_hero_summon_state
    )
    event_bus.subscribe(events.GOLD_MINE_CHANGED, publish_unit)
    event_bus.subscribe(
        events.HERO_SKILL_CHANGED,
        on_hero_skill_changed
    )
    event_bus.subscribe(events.RESOURCE_CHANGED, on_resources)
end

return M
