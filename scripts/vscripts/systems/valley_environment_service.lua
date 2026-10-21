-- Shared by the released map and its art review. No preview camera/game rules.
local scheduler = require("core/scheduler")
local event_bus = require("core/event_bus")
local events = require("core/events")
local M = {}
-- Retain ownership across a Lua hot reload, but never use particle indices or
-- entity handles after the game-mode entity (and therefore world) changes.
local runtime_key = "SURVIVAL_VALLEY_ENVIRONMENT_RUNTIME"
local runtime = rawget(_G, runtime_key) or { particles = {}, props = {}, generation = 0 }
rawset(_G, runtime_key, runtime)
local effect = "particles/units/heroes/heroes_underlord/abbysal_underlord_portal_ambient.vpcf"
local model = "models/heroes/abyssal_underlord/abyssal_underlord_portal_model.vmdl"
-- Player slots are east, south, west, north. Monsters leave the central
-- sanctuary along these outward lanes; the native door's normal is local X.
local lane_yaws = { 0, 270, 180, 90 }
local dedicated_modes = { rich = true, cold = true, scourge = true }
local attachment_height, ground_clearance = 97.362, 12

local function selected_mode()
    local setup = package.loaded["systems/match_setup_service"]
    return setup and setup.get_mode and setup.get_mode() or "standard"
end

local function current_world()
    return GameRules:GetGameModeEntity()
end

local function supported_map()
    local name = GetMapName()
    return name == "template_map" or name == "valley_decor_review"
end

function M.precache(context)
    if supported_map() then
        PrecacheResource("particle", effect, context)
        PrecacheResource("model", model, context)
    end
end

function M.clear()
    local old_particles, old_props = runtime.particles, runtime.props
    runtime.particles, runtime.props, runtime.mode = {}, {}, nil
    if runtime.world ~= current_world() then return end
    for _, id in ipairs(old_particles) do
        pcall(ParticleManager.DestroyParticle, ParticleManager, id, true)
        pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, id)
    end
    for _, prop in ipairs(old_props) do
        if not prop:IsNull() then UTIL_Remove(prop) end
    end
end

local function create_portal(marker, lane, flat)
    local origin = marker:GetAbsOrigin()
    local center = Vector(origin.x, origin.y, GetGroundHeight(origin, nil) + ground_clearance)
    local yaw = lane_yaws[lane]
    local radians = math.rad(yaw)
    local forward = flat and Vector(0, 0, 1) or Vector(math.cos(radians), math.sin(radians), 0)
    local right = Vector(math.sin(radians), -math.cos(radians), 0)
    local up = flat and Vector(-math.cos(radians), -math.sin(radians), 0) or Vector(0, 0, 1)
    -- The native vortex is 97.362 units above its model origin. Pitching the
    -- original root alone turns that height into a lateral offset. Translate
    -- the root back so attach_portal stays centered on the authored marker.
    local position = flat and Vector(center.x - up.x * attachment_height,
        center.y - up.y * attachment_height, center.z) or center
    local attachment = flat and center or center + Vector(0, 0, attachment_height)
    local pitch = flat and -90 or 0
    local prop = SpawnEntityFromTableSynchronous("prop_dynamic", {
        targetname = "survival_underlord_portal_" .. lane,
        model = model, solid = 0, DefaultAnim = "au_portal_chanelling",
        origin = string.format("%f %f %f", position.x, position.y, position.z),
        angles = string.format("%d %d 0", pitch, yaw),
    })
    assert(prop and not prop:IsNull(), "Underlord portal model spawn failed")
    runtime.props[#runtime.props + 1] = prop
    prop:SetAbsOrigin(position)
    prop:SetAngles(pitch, yaw, 0)
    DoEntFireByInstanceHandle(prop, "SetAnimation", "au_portal_chanelling", 0, prop, prop)
    local id = ParticleManager:CreateParticle(effect, PATTACH_ABSORIGIN_FOLLOW, prop)
    assert(type(id) == "number" and id >= 0, "Underlord portal particle creation failed")
    runtime.particles[#runtime.particles + 1] = id
    ParticleManager:SetParticleControlEnt(id, 0, prop,
        PATTACH_ABSORIGIN_FOLLOW, "", position, true)
    -- Both modes retain the real attachment, including its model rotation.
    ParticleManager:SetParticleControlEnt(id, 1, prop,
        PATTACH_POINT_FOLLOW, "attach_portal", attachment, true)
    for _, cp in ipairs({0, 2}) do
        ParticleManager:SetParticleControl(id, cp, position)
        ParticleManager:SetParticleControlOrientation(id, cp, forward, right, up)
    end
    -- CP4 is native size/channel state, not a position; CP61 selects the
    -- original orange style. Leaving both zero keeps a fully idle portal.
    ParticleManager:SetParticleControl(id, 4, Vector(0, 0, 0))
    ParticleManager:SetParticleControl(id, 61, Vector(0, 0, 0))
end

function M.apply()
    if not supported_map() then return 0 end
    M.clear()
    runtime.world = current_world()
    local mode = selected_mode()
    local flat = dedicated_modes[mode] == true
    for i = 1, 4 do
        local name = flat and ("mode_" .. mode .. "_monster_" .. (i - 1) .. "_spawn")
            or ("monsterborn_player" .. i)
        local marker = Entities:FindByName(nil, name)
        local old = Entities:FindByName(nil, "valley_decor_v1_fx_monsterborn_player" .. i)
        if old then DoEntFireByInstanceHandle(old, "Stop", "", 0, old, old) end
        if marker then
            local ok, err = pcall(create_portal, marker, i, flat)
            if not ok then
                M.clear()
                print("[ValleyEnvironment] portal setup failed: " .. tostring(err))
                return 0
            end
        end
    end
    runtime.mode = mode
    print("VALLEY_UNDERLORD_PORTALS", #runtime.particles, mode, flat and "ground" or "upright")
    return #runtime.particles
end

function M.init()
    if runtime.bus then
        for _, subscription in ipairs(runtime.subscriptions or {}) do
            runtime.bus.unsubscribe(subscription)
        end
    end
    M.clear()
    local world = current_world()
    runtime.world = world
    runtime.generation = runtime.generation + 1
    local current_generation = runtime.generation
    local function refresh()
        if runtime.generation == current_generation and current_world() == world
            and runtime.mode ~= selected_mode() then M.apply() end
    end
    -- Selection publishes WAVE_CHANGED before profile/builders finish loading.
    -- Builder readiness also recovers a service rebound during that sequence.
    runtime.bus = event_bus
    runtime.subscriptions = {
        event_bus.subscribe(events.WAVE_CHANGED, refresh),
        event_bus.subscribe(events.BUILDER_READY, refresh),
    }
    scheduler.after(0, function()
        refresh()
    end, "valley_environment_initialise")
end

return M
