local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local ability_utils = require("core/ability_utils")
local logger = require("core/logger")
local heroes = require("config/generated/hero_definitions")
local skills = require("config/generated/hero_skill_definitions")
local initial_skills = require("config/generated/hero_initial_skills")

local M = {}

local state_by_player = {}
local RETURN_HOME_ABILITY = "ability_survival_return_home"

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function rows_for_hero(hero_id)
    local rows = {}
    for _, row in ipairs(initial_skills.rows or {}) do
        if row.enabled ~= false and row.hero_id == hero_id then
            table.insert(rows, row)
        end
    end
    table.sort(rows, function(a, b)
        return (tonumber(a.slot_order) or 0)
            < (tonumber(b.slot_order) or 0)
    end)
    return rows
end

local function skill_projection(skill_id, level)
    local definition = skills.by_id[skill_id]
    return {
        skill_id = skill_id,
        ability_name = definition and definition.ability_name or "",
        display_name = definition and definition.display_name or skill_id,
        description = definition and definition.description or "",
        icon_name = definition and definition.icon_name or "",
        level = level,
        max_level = definition
            and (tonumber(definition.max_level) or 1) or 1,
        effect_type = definition and definition.effect_type or "",
        effect_value_per_level = definition
            and (tonumber(definition.effect_value_per_level) or 0) or 0,
    }
end

local function snapshot(player_id)
    local state = state_by_player[player_id]
    if not state then
        return {
            player_id = player_id,
            hero_ready = 0,
            skill_count = 0,
            skill_capacity = 10,
            skills = {},
        }
    end

    local projected = {}
    for _, skill_id in ipairs(state.order) do
        table.insert(
            projected,
            skill_projection(skill_id, state.levels[skill_id])
        )
    end

    return {
        player_id = player_id,
        hero_ready = valid_entity(state.unit) and 1 or 0,
        hero_id = state.hero_id,
        unit_entindex = valid_entity(state.unit)
            and state.unit:entindex() or -1,
        skill_count = #state.order,
        skill_capacity = state.capacity,
        skills = projected,
        version = state.version,
    }
end

local function publish(player_id, reason)
    local data = snapshot(player_id)
    data.reason = reason or "changed"
    CustomNetTables:SetTableValue(
        "survival_hero_skills",
        "player_" .. tostring(player_id),
        data
    )
    event_bus.emit(events.HERO_SKILL_CHANGED, data)
end

local function ability_map(state)
    local result = { [RETURN_HOME_ABILITY] = true }
    for skill_id, _ in pairs(state.levels) do
        local definition = skills.by_id[skill_id]
        if definition and definition.ability_name then
            result[definition.ability_name] = true
        end
    end
    return result
end

local function synchronize_unit(state)
    if not valid_entity(state.unit) then
        return
    end

    ability_utils.remove_all_except(state.unit, ability_map(state))
    if state.unit.SetAbilityPoints then
        state.unit:SetAbilityPoints(0)
    end

    for _, skill_id in ipairs(state.order) do
        local definition = skills.by_id[skill_id]
        if definition and definition.enabled ~= false then
            local ability = state.unit:FindAbilityByName(
                definition.ability_name
            )
            if not ability then
                ability = state.unit:AddAbility(definition.ability_name)
            end
            if ability then
                ability:SetLevel(state.levels[skill_id])
                ability:SetHidden(false)
                ability:SetActivated(true)
            end
        end
    end
    local return_ability = state.unit:FindAbilityByName(RETURN_HOME_ABILITY)
    if not return_ability then
        return_ability = state.unit:AddAbility(RETURN_HOME_ABILITY)
    end
    if return_ability then
        return_ability:SetLevel(1)
        return_ability:SetHidden(false)
        return_ability:SetActivated(true)
    end
    if state.unit.CalculateStatBonus then
        state.unit:CalculateStatBonus(true)
    end
end

local function grant_to_state(state, skill_id, levels)
    local definition = skills.by_id[skill_id]
    if not definition or definition.enabled == false then
        return { ok = false, error = "skill_invalid" }
    end

    local current = state.levels[skill_id]
    local maximum = math.max(1, tonumber(definition.max_level) or 1)
    local amount = math.max(1, tonumber(levels) or 1)

    if current then
        if current >= maximum then
            return { ok = false, error = "skill_already_max" }
        end
        state.levels[skill_id] =
            math.min(maximum, current + amount)
    else
        if #state.order >= state.capacity then
            return { ok = false, error = "skill_capacity_reached" }
        end
        state.levels[skill_id] = math.min(maximum, amount)
        table.insert(state.order, skill_id)
    end

    state.version = state.version + 1
    synchronize_unit(state)
    publish(state.player_id, "skill_granted")
    return {
        ok = true,
        skill_id = skill_id,
        level = state.levels[skill_id],
        snapshot = snapshot(state.player_id),
    }
end

local function grant_request(payload)
    local player_id = tonumber(payload.player_id)
    local state = state_by_player[player_id]
    if not state then
        return { ok = false, error = "combat_hero_not_ready" }
    end
    return grant_to_state(
        state,
        tostring(payload.skill_id or ""),
        payload.levels
    )
end

local function state_request(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    return { ok = true, snapshot = snapshot(player_id) }
end

local function initialize_hero(payload)
    local definition = heroes.by_id[payload.hero_id]
    local capacity = definition
        and tonumber(definition.skill_capacity) or 10
    local state = {
        player_id = payload.player_id,
        hero_id = payload.hero_id,
        unit = payload.unit,
        capacity = math.max(1, capacity or 10),
        levels = {},
        order = {},
        version = 0,
    }
    state_by_player[payload.player_id] = state

    ability_utils.remove_all(state.unit)
    local rows = rows_for_hero(state.hero_id)
    local expected = definition
        and tonumber(definition.initial_skill_count) or #rows
    expected = math.max(0, expected or 0)

    for index, row in ipairs(rows) do
        if index <= expected then
            grant_to_state(
                state,
                row.skill_id,
                tonumber(row.initial_level) or 1
            )
        end
    end
    if #rows ~= expected then
        logger.warn(
            "HeroSkill",
            tostring(state.hero_id)
            .. " initial rows=" .. tostring(#rows)
            .. " expected=" .. tostring(expected)
        )
    end
    synchronize_unit(state)
    publish(state.player_id, "initial_skills_applied")

    scheduler.after(0.25, function()
        if state_by_player[state.player_id] == state then
            synchronize_unit(state)
            publish(state.player_id, "post_spawn_skill_audit")
        end
    end, "hero_skill_audit_" .. tostring(state.player_id))
end

local function on_hero_summoned(payload)
    if payload.player_id == nil or not valid_entity(payload.unit) then
        return
    end
    scheduler.after(0.03, function()
        initialize_hero(payload)
    end, "hero_skill_init_" .. tostring(payload.player_id))
end

function M.init()
    state_by_player = {}
    event_bus.handle_request(
        events.HERO_SKILL_STATE_GET_REQUEST,
        state_request
    )
    event_bus.handle_request(
        events.HERO_SKILL_GRANT_REQUEST,
        grant_request
    )
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
end

return M
