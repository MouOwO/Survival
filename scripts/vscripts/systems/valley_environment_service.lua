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
local rich_effect = "particles/survival_environment/rich_portal/ambient.vpcf"
local model = "models/heroes/abyssal_underlord/abyssal_underlord_portal_model.vmdl"
-- Player slots are east, south, west, north. Monsters leave the central
-- sanctuary along these outward lanes; the native door's normal is local X.
local lane_yaws = { 0, 270, 180, 90 }
local dedicated_modes = { rich = true, cold = true, scourge = true, ruins = true }
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
        PrecacheResource("particle", rich_effect, context)
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

local function create_effect(path, position, attachment, forward, right, up)
    local id = ParticleManager:CreateParticle(path, PATTACH_WORLDORIGIN, nil)
    assert(type(id) == "number" and id >= 0, "Underlord portal particle creation failed")
    runtime.particles[#runtime.particles + 1] = id
    ParticleManager:SetParticleAlwaysSimulate(id)
    ParticleManager:SetParticleShouldCheckFoW(id, false)
    for _, cp in ipairs({0, 1, 2}) do
        ParticleManager:SetParticleControl(id, cp, cp == 1 and attachment or position)
        ParticleManager:SetParticleControlOrientation(id, cp, forward, right, up)
    end
    -- These are native style/channel controls, rather than world positions.
    for _, cp in ipairs({4, 61, 62}) do
        ParticleManager:SetParticleControl(id, cp, Vector(0, 0, 0))
    end
end

local function create_rich_portal(marker)
    local origin = marker:GetAbsOrigin()
    local center = Vector(origin.x, origin.y, GetGroundHeight(origin, nil) + ground_clearance)
    -- One horizontal vortex serves the four rich-mode monster landings.
    -- Its own resource scales the complete native effect by three.
    create_effect(rich_effect, center, center,
        Vector(0, 0, 1), Vector(1, 0, 0), Vector(0, -1, 0))
end

local function create_portal(marker, lane, flat, configured_yaw)
    local origin = marker:GetAbsOrigin()
    local center = Vector(origin.x, origin.y, GetGroundHeight(origin, nil) + ground_clearance)
    local yaw = configured_yaw or lane_yaws[lane]
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
    -- These map landmarks never move. Keeping the effect independent of the
    -- prop also keeps its emitters positioned when the client puts the prop
    -- to sleep and stops evaluating attach_portal outside the camera/vision.
    create_effect(effect, position, attachment, forward, right, up)
end

function M.apply()
    if not supported_map() then return 0 end
    M.clear()
    runtime.world = current_world()
    local mode = selected_mode()
    local dedicated = dedicated_modes[mode] == true
    local flat = dedicated and mode ~= "ruins"
    local portal_yaws = mode == "ruins" and require("config/mode_spawn_config").modes.ruins.portal_yaws
    for i = 1, 4 do
        local old = Entities:FindByName(nil, "valley_decor_v1_fx_monsterborn_player" .. i)
        if old then DoEntFireByInstanceHandle(old, "Stop", "", 0, old, old) end
    end
    if mode == "rich" then
        local marker = Entities:FindByName(nil, "rich_start")
        if marker then
            local ok, err = pcall(create_rich_portal, marker)
            if not ok then
                M.clear()
                print("[ValleyEnvironment] portal setup failed: " .. tostring(err))
                return 0
            end
        end
    else
        for i = 1, 4 do
            local name = dedicated and ("mode_" .. mode .. "_monster_" .. (i - 1) .. "_spawn")
                or ("monsterborn_player" .. i)
            local marker = Entities:FindByName(nil, name)
            if marker then
                local ok, err = pcall(create_portal, marker, i, flat, portal_yaws and portal_yaws[i - 1])
                if not ok then
                    M.clear()
                    print("[ValleyEnvironment] portal setup failed: " .. tostring(err))
                    return 0
                end
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
    if runtime.world == current_world() then
        for _, listener in ipairs(runtime.listeners or {}) do StopListeningToGameEvent(listener) end
    end
    M.clear()
    local world = current_world()
    runtime.world = world
    runtime.generation = runtime.generation + 1
    local current_generation = runtime.generation
    local ready_players = {}
    local function connected_player_present()
        if not PlayerResource then return false end
        for player_id = 0, (DOTA_MAX_TEAM_PLAYERS or 24) - 1 do
            if PlayerResource:GetPlayer(player_id)
                and PlayerResource:GetConnectionState(player_id) == DOTA_CONNECTION_STATE_CONNECTED then
                return true
            end
        end
        return false
    end
    local function refresh(force)
        if runtime.generation == current_generation and current_world() == world
            and connected_player_present()
            and (force or runtime.mode ~= selected_mode()) then M.apply() end
    end
    local function player_ready(payload)
        local id = payload and payload.player_id
        local first_ready = id ~= nil and not ready_players[id]
        if id ~= nil then ready_players[id] = true end
        refresh(first_ready)
    end
    -- Activate runs before clients connect. Particle messages sent then have no
    -- recipients, although the prop entities subsequently replicate normally.
    -- Create only for connected clients and replay after full connection (also
    -- on reconnect); later readiness covers the client's loading barrier.
    runtime.listeners = {
        ListenToGameEvent("player_connect_full", function()
            scheduler.after(0.2, function() refresh(true) end, "valley_environment_player_connected")
        end, nil),
    }
    runtime.bus = event_bus
    runtime.subscriptions = {
        event_bus.subscribe(events.WAVE_CHANGED, function() refresh(false) end),
        event_bus.subscribe(events.BUILDER_READY, player_ready),
        event_bus.subscribe(events.HERO_READY, player_ready),
    }
    scheduler.after(0, function()
        refresh(false)
    end, "valley_environment_initialise")
end

return M
