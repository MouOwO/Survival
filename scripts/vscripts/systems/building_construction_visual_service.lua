local construction_rules = require(
    "config/generated/building_construction_rules"
)

local M = {}
local active_by_entindex = {}
local warp = require("systems/building_warp_effects")

local function nonempty(value)
    return type(value) == "string" and value ~= ""
end

local function valid_entity(entity)
    if not entity then return false end
    if type(entity.IsNull) == "function" then
        local ok, is_null = pcall(entity.IsNull, entity)
        if not ok or is_null then return false end
    end
    return true
end

local function entindex_for(unit)
    if not unit or type(unit.entindex) ~= "function" then return nil end
    local ok, entindex = pcall(unit.entindex, unit)
    if ok then return tonumber(entindex) end
    return nil
end

local function hide_model(unit)
    if not valid_entity(unit) or type(unit.AddNoDraw) ~= "function" then
        return false
    end
    return pcall(unit.AddNoDraw, unit)
end

local function show_model(unit)
    if not valid_entity(unit) then return false end
    local restored = false
    if type(unit.RemoveNoDraw) == "function" then
        restored = pcall(unit.RemoveNoDraw, unit)
    end
    -- Clear render alpha left by an older Workshop Tools session that loaded
    -- the superseded construction-opacity implementation.
    if type(unit.SetRenderAlpha) == "function" then
        pcall(unit.SetRenderAlpha, unit, 255)
    end
    return restored
end

local function state_for(value)
    if type(value) == "table" and value.visual_state_marker == M then
        return value
    end
    local entindex = type(value) == "number" and value or entindex_for(value)
    return entindex and active_by_entindex[entindex] or nil
end

local function retire(state, reveal_model)
    if not state or state.retired then return false end
    state.retired = true
    if active_by_entindex[state.entindex] == state then
        active_by_entindex[state.entindex] = nil
    end
    for _, particle in ipairs(state.loop_particles or {}) do
        warp.destroy(particle)
    end
    state.loop_particles = {}
    warp.destroy(state.start_particle)
    state.start_particle = nil
    if reveal_model then show_model(state.unit) end
    return true
end

function M.start(unit, definition)
    if not valid_entity(unit) then return nil end
    local entindex = entindex_for(unit)
    if not entindex then return nil end
    M.cancel(entindex)
    -- Reveal the completed building only after the construction transaction.
    hide_model(unit)

    definition = definition or {}
    local start_path = definition and definition.build_start_particle
    local loop_path = definition and (
        definition.build_loop_particle or definition.build_particle
    )
    local duration = tonumber(definition and definition.build_time) or 3
    local start_particle = warp.create(start_path, unit, definition, duration)

    local state = {
        visual_state_marker = M,
        entindex = entindex,
        unit = unit,
        definition = definition,
        start_particle = start_particle,
        duration = duration,
        loop_particles = {},
        retired = false,
    }
    local particle = warp.create(loop_path, unit, definition, duration)
    if particle ~= nil then state.loop_particles[1] = particle end
    -- Never leave only a health bar if a visual resource fails to spawn.
    if particle == nil and warp.is_white(loop_path) then show_model(unit) end
    active_by_entindex[entindex] = state
    return state
end

function M.complete(value, unit, definition)
    local state = state_for(value)
    if not state or not retire(state, true) then return false end
    if valid_entity(state.unit) then
        warp.create(state.definition.build_complete_particle, state.unit,
            state.definition, state.duration, true)
    end
    return true
end

function M.cancel(value)
    local state = state_for(value)
    -- Cancellation is used by the death path, so do not reveal a model that is
    -- already dead or about to be removed.
    return retire(state, false)
end

function M.precache(context)
    if type(PrecacheResource) ~= "function" then return 0 end
    local seen = {}
    local count = 0
    for _, row in ipairs(construction_rules.rows or {}) do
        if row.enabled ~= false then
            for _, field in ipairs({ "build_start_particle", "build_loop_particle",
                "build_particle", "build_complete_particle" }) do
                local path = row[field]
                if nonempty(path) and not seen[path] then
                    PrecacheResource("particle", path, context)
                    seen[path] = true
                    count = count + 1
                end
            end
        end
    end
    return count + warp.precache_shells(context)
end

function M.reset()
    local states = {}
    for _, state in pairs(active_by_entindex) do states[#states + 1] = state end
    -- Workshop Tools can preserve Lua entities across Run sessions. Restore
    -- surviving units while retiring stale construction particle state.
    for _, state in ipairs(states) do retire(state, true) end
    warp.reset_shells()
end

M._active_count_for_test = function()
    local count = 0
    for _ in pairs(active_by_entindex) do count = count + 1 end
    return count
end

return M
