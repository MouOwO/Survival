local construction_rules = require(
    "config/generated/building_construction_rules"
)

local M = {}
local active_by_entindex = {}
local KEEN_LOOP_PARTICLE = "particles/items2_fx/teleport_start.vpcf"

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

local function origin_for(unit)
    if not valid_entity(unit) or type(unit.GetAbsOrigin) ~= "function" then
        return nil
    end
    local ok, origin = pcall(unit.GetAbsOrigin, unit)
    if ok then return origin end
    return nil
end

local function visual_origins(unit, definition)
    local origin = origin_for(unit)
    if not origin then return {} end
    local scale = math.max(1, tonumber(definition and definition.build_visual_scale) or 1)
    if scale <= 1 then return { origin } end

    -- Valve's default teleport particle has a fixed 128-unit visual footprint
    -- and does not expose a reliable radius CP. Spread four native instances
    -- over large buildings instead of writing a fake scale control point.
    local offset = 64 * math.min(scale, 3)
    return {
        Vector(origin.x - offset, origin.y - offset, origin.z),
        Vector(origin.x - offset, origin.y + offset, origin.z),
        Vector(origin.x + offset, origin.y - offset, origin.z),
        Vector(origin.x + offset, origin.y + offset, origin.z),
    }
end

local function create_particle(path, unit, origin, duration)
    if not nonempty(path) or not origin or not ParticleManager then return nil end
    local ok, particle = pcall(function()
        return ParticleManager:CreateParticle(
            path,
            PATTACH_WORLDORIGIN,
            unit
        )
    end)
    if not ok or particle == nil then return nil end
    pcall(function()
        ParticleManager:SetParticleControl(particle, 0, origin)
        if path == KEEN_LOOP_PARTICLE then
            -- teleport_start reads CP7.x for its channel duration/counter.
            ParticleManager:SetParticleControl(
                particle,
                7,
                Vector(math.max(0.1, tonumber(duration) or 3), 0, 0)
            )
        end
    end)
    return particle
end

local function release_index(particle)
    if particle == nil then return end
    pcall(function() ParticleManager:ReleaseParticleIndex(particle) end)
end

local function destroy_particle(particle, immediate)
    if particle == nil then return end
    pcall(function()
        ParticleManager:DestroyParticle(particle, immediate == true)
    end)
    release_index(particle)
end

local function play_one_shot(path, unit, origins, duration)
    if not nonempty(path) then return 0 end
    local created = 0
    for _, origin in ipairs(origins or {}) do
        local particle = create_particle(path, unit, origin, duration)
        if particle ~= nil then
            release_index(particle)
            created = created + 1
        end
    end
    return created
end

local function state_for(value)
    if type(value) == "table" and value.visual_state_marker == M then
        return value
    end
    local entindex = type(value) == "number" and value or entindex_for(value)
    return entindex and active_by_entindex[entindex] or nil
end

local function retire(state, immediate)
    if not state or state.retired then return false end
    state.retired = true
    if active_by_entindex[state.entindex] == state then
        active_by_entindex[state.entindex] = nil
    end
    for _, particle in ipairs(state.loop_particles or {}) do
        destroy_particle(particle, immediate)
    end
    state.loop_particles = {}
    return true
end

function M.start(unit, definition)
    if not valid_entity(unit) then return nil end
    local entindex = entindex_for(unit)
    if not entindex then return nil end
    M.cancel(entindex)

    local origins = visual_origins(unit, definition)
    local start_path = definition and definition.build_start_particle
    local loop_path = definition and (
        definition.build_loop_particle or definition.build_particle
    )
    local duration = tonumber(definition and definition.build_time) or 3
    play_one_shot(start_path, unit, origins, duration)

    local state = {
        visual_state_marker = M,
        entindex = entindex,
        unit = unit,
        origins = origins,
        duration = duration,
        loop_particles = {},
        retired = false,
    }
    for _, origin in ipairs(origins) do
        local particle = create_particle(loop_path, unit, origin, duration)
        if particle ~= nil then
            state.loop_particles[#state.loop_particles + 1] = particle
        end
    end
    active_by_entindex[entindex] = state
    return state
end

function M.complete(value, unit, definition)
    local state = state_for(value)
    -- A graceful stop preserves teleport_start's short falling-ring End Cap.
    -- The full teleport_end burst is intentionally omitted.
    return state ~= nil and retire(state, false)
end

function M.cancel(value)
    local state = state_for(value)
    return retire(state, true)
end

function M.precache(context)
    if type(PrecacheResource) ~= "function" then return 0 end
    local seen = {}
    local count = 0
    for _, row in ipairs(construction_rules.rows or {}) do
        if row.enabled ~= false then
            for _, path in ipairs({
                row.build_start_particle,
                row.build_loop_particle or row.build_particle,
            }) do
                if nonempty(path) and not seen[path] then
                    PrecacheResource("particle", path, context)
                    seen[path] = true
                    count = count + 1
                end
            end
        end
    end
    return count
end

function M.reset()
    local states = {}
    for _, state in pairs(active_by_entindex) do states[#states + 1] = state end
    for _, state in ipairs(states) do retire(state, true) end
end

M._active_count_for_test = function()
    local count = 0
    for _ in pairs(active_by_entindex) do count = count + 1 end
    return count
end

return M