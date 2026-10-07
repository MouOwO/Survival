local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local projection = require("systems/tower_rank_projection")
local M = {}
local TABLE = "survival_tower_rank"
local tracked, session, generation = {}, "", 0

local function valid(unit)
    return unit and (not unit.IsNull or not unit:IsNull())
end

local function write(key, value)
    if CustomNetTables then CustomNetTables:SetTableValue(TABLE, key, value) end
end

function M.remove(entindex, unit)
    entindex = tonumber(entindex)
    local entry = entindex and tracked[entindex] or nil
    if not entry or (unit and entry.unit ~= unit) then return end
    tracked[entindex] = nil
    write("unit_" .. entindex, { removed = 1, session = session })
end

local function display_name(state, unit)
    local name = state.display_name or unit.survival_display_name
        or state.tower_class_name or (state.definition and state.definition.display_name)
        or unit:GetUnitName()
    -- Quality and upgrade stars already have their own overhead UI elements.
    return tostring(name):gsub("^【.-】", ""):gsub("（进阶 %d+/5）$", "")
end

function M.publish(state)
    if state and state.stats_only == true then return end
    local rank = projection.project(state)
    local unit = state and state.unit
    if not rank or not valid(unit) or (unit.IsAlive and not unit:IsAlive()) then return end
    local entindex = unit:entindex()
    if state.constructing == true or tonumber(state.constructing) == 1
        or (unit.HasModifier and unit:HasModifier("modifier_building_under_construction"))
        or (unit.IsNoDraw and unit:IsNoDraw()) then
        -- Completed buildings normally enter through BUILDING_CREATED only.
        -- Also retire an old entry if Tools reloads or construction reuse expose it.
        M.remove(entindex, unit)
        return
    end
    local player_id = tonumber(state.player_id or unit.survival_player_id)
    if not player_id or player_id < 0 then return end
    rank.entindex = entindex
    rank.player_id = player_id
    rank.team = tonumber(state.team) or unit:GetTeamNumber()
    rank.unit_name = unit:GetUnitName()
    rank.display_name = display_name(state, unit)
    rank.constructing = 0
    rank.session = session
    rank.removed = 0
    local previous = tracked[entindex]
    tracked[entindex] = { unit = unit, rank = rank }
    if previous and previous.unit == unit
        and previous.rank.rarity == rank.rarity
        and previous.rank.stars == rank.stars
        and previous.rank.red_stars == rank.red_stars
        and previous.rank.unit_name == rank.unit_name
        and previous.rank.display_name == rank.display_name
        and previous.rank.constructing == rank.constructing
        and previous.rank.player_id == rank.player_id
        and previous.rank.team == rank.team then return end
    write("unit_" .. entindex, rank)
end

local function sweep()
    local finished = GameRules and GameRules.State_Get and DOTA_GAMERULES_STATE_POST_GAME
        and GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME
    for entindex, entry in pairs(tracked) do
        if finished or not valid(entry.unit)
            or (entry.unit.IsAlive and not entry.unit:IsAlive()) then
            M.remove(entindex)
        end
    end
    return not finished
end

function M.init()
    generation = generation + 1
    local current_generation = generation
    tracked = {}
    session = type(DoUniqueString) == "function" and DoUniqueString("tower_rank")
        or (tostring(generation) .. ":" .. tostring({}))
    -- Session metadata invalidates stale replicated entries on Tools restarts.
    write("_session", { id = session })
    local function subscribe(name, callback)
        event_bus.subscribe(name, function(payload)
            if current_generation == generation then callback(payload or {}) end
        end)
    end
    subscribe(events.BUILDING_CREATED, M.publish)
    subscribe(events.BUILDING_CHANGED, M.publish)
    subscribe(events.TOWER_FUSION_RUNTIME_CHANGED, M.publish)
    subscribe(events.BUILDING_DESTROYED, function(payload)
        M.remove(payload.entindex, payload.unit)
    end)
    subscribe(events.TOWER_FUSION_RUNTIME_REMOVED, function(payload)
        M.remove(payload.entindex)
    end)
    subscribe(events.ENGINE_ENTITY_KILLED, function(payload)
        if valid(payload.victim) then M.remove(payload.victim:entindex(), payload.victim) end
    end)
    local listed = event_bus.request(events.BUILDING_LIST_REQUEST, {})
    for _, state in ipairs(listed and listed.buildings or {}) do M.publish(state) end
    scheduler.every(1, sweep, "tower_rank_lifecycle")
end

M._sweep_for_test = sweep
return M
