local event_bus = require("core/event_bus")
local events = require("core/events")
local stages = require("config/generated/builder_ability_stages")

local M = {}

local state_by_team = {}
local managed_abilities = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function create_state()
    return {
        hero = nil,
        player_id = -1,
        team = -1,
        stage_id = "",
        wall_built_once = false,
        city_level = 0,
        hero_summoned = false,
        counts = {},
    }
end

local function ensure(team)
    if not state_by_team[team] then
        state_by_team[team] = create_state()
        state_by_team[team].team = team
    end
    return state_by_team[team]
end

local function count(state, building_id)
    return state.counts[building_id] or 0
end

local function stage_for(state)
    if not state.wall_built_once then
        return "wall_pending"
    end
    if count(state, "main_city") < 1 then
        return "city_pending"
    end
    return "city_built"
end

local function rows_for(stage_id)
    local rows = {}
    for _, row in ipairs(stages.rows or {}) do
        if row.enabled ~= false and row.stage_id == stage_id then
            table.insert(rows, row)
            managed_abilities[row.ability_name] = true
        end
    end
    table.sort(rows, function(a, b)
        return (a.slot_order or 0) < (b.slot_order or 0)
    end)
    return rows
end

local function remove_managed(hero)
    if not valid_entity(hero) then
        return
    end
    for ability_name, _ in pairs(managed_abilities) do
        if hero:FindAbilityByName(ability_name) then
            hero:RemoveAbility(ability_name)
        end
    end
end

local function can_activate(state, row)
    if state.city_level < (tonumber(row.required_city_level) or 0) then
        return false
    end
    local maximum = tonumber(row.max_building_count) or 0
    if maximum > 0 and count(state, row.building_id) >= maximum then
        return false
    end
    if row.disable_after_hero_summoned == true
        and state.hero_summoned then
        return false
    end
    return true
end

local function add_stage_abilities(state, stage_rows)
    local hero = state.hero
    if not valid_entity(hero) then
        return
    end

    for _, row in ipairs(stage_rows) do
        local ability = hero:FindAbilityByName(row.ability_name)
        if not ability then
            ability = hero:AddAbility(row.ability_name)
        end
        if ability then
            ability:SetLevel(1)
            ability:SetHidden(false)
            ability:SetActivated(can_activate(state, row))
        end
    end
end

local function public_counts(state)
    local result = {}
    for building_id, value in pairs(state.counts) do
        result[building_id] = value
    end
    return result
end

local function publish(state)
    if not valid_entity(state.hero) then
        return
    end
    local payload = {
        unit = state.hero,
        entindex = state.hero:entindex(),
        player_id = state.player_id,
        team = state.team,
        building_id = "builder",
        level = 1,
        city_level = state.city_level,
        builder_stage = state.stage_id,
        hero_summoned = state.hero_summoned and 1 or 0,
        building_counts = public_counts(state),
    }
    event_bus.emit(events.BUILDER_STAGE_CHANGED, payload)
    event_bus.emit(events.BUILDER_UNLOCK_CHANGED, payload)
end

local function sync(state)
    local next_stage = stage_for(state)
    local stage_changed = next_stage ~= state.stage_id
    state.stage_id = next_stage
    local rows = rows_for(next_stage)

    if stage_changed then
        remove_managed(state.hero)
    end
    add_stage_abilities(state, rows)
    publish(state)
end

local function on_hero_ready(payload)
    local state = ensure(payload.team)
    state.hero = payload.hero
    state.player_id = payload.player_id
    managed_abilities = {}
    for _, row in ipairs(stages.rows or {}) do
        managed_abilities[row.ability_name] = true
    end
    sync(state)
end

local function on_building_created(payload)
    local state = ensure(payload.team)
    local building_id = tostring(payload.building_id or "")
    state.counts[building_id] = count(state, building_id) + 1
    if building_id == "wall" then
        state.wall_built_once = true
    end
    if building_id == "main_city" then
        state.city_level = tonumber(payload.level) or 1
    end
    sync(state)
end

local function on_building_changed(payload)
    local state = ensure(payload.team)
    if payload.building_id == "main_city" then
        state.city_level = tonumber(payload.level) or state.city_level
        sync(state)
    end
end

local function on_building_destroyed(payload)
    local state = ensure(payload.team)
    local building_id = tostring(payload.building_id or "")
    state.counts[building_id] = math.max(0, count(state, building_id) - 1)
    if building_id == "main_city" then
        state.city_level = 0
    end
    sync(state)
end

local function on_hero_summoned(payload)
    local state = ensure(payload.team)
    state.hero_summoned = true
    sync(state)
end

function M.init()
    state_by_team = {}
    managed_abilities = {}
    event_bus.subscribe(events.HERO_READY, on_hero_ready)
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
end

return M
