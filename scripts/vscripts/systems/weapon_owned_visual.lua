local event_bus = require("core/event_bus")
local events = require("core/events")
local weapons = require("config/generated/weapon_definitions")
local profiles = require("config/generated/weapon_visual_profiles")

local M = {}
local states, paths_by_content = {}, {}
local reset_depth = 0

local function player_id(value)
    local id = tonumber(value)
    if id and id >= 0 and id < math.huge and id == math.floor(id) then return id end
end

local function valid(unit)
    return unit and not unit:IsNull()
end

local function owner_matches(unit, id)
    if not valid(unit) then return false end
    local owner = tonumber(unit.survival_player_id)
    if owner == nil and unit.GetPlayerOwnerID then
        owner = tonumber(unit:GetPlayerOwnerID())
    end
    return owner == id
end

local function state(id)
    if not states[id] then states[id] = {} end
    return states[id]
end

local function clear(current)
    local particle = current.particle_id
    -- Revoke ownership first; engine callbacks may re-enter death/cleanup.
    current.particle_id, current.applied_path = nil, nil
    if particle == nil then return end
    current.clearing = true
    local destroyed, destroy_error = pcall(ParticleManager.DestroyParticle,
        ParticleManager, particle, false)
    local released, release_error = pcall(ParticleManager.ReleaseParticleIndex,
        ParticleManager, particle)
    if not destroyed or not released then
        print("[WeaponOwnedVisual] cleanup failed: "
            .. tostring((not destroyed and destroy_error) or release_error))
    end
    current.clearing = nil
end

local function path_from_counts(counts)
    for content_id, count in pairs(counts) do
        if (tonumber(count) or 0) > 0 and paths_by_content[content_id] then
            return paths_by_content[content_id]
        end
    end
end

local function sync_inventory(current, id)
    local result = event_bus.request(events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = id })
    local counts = result and result.ok ~= false and result.snapshot
        and result.snapshot.counts
    if type(counts) == "table" then current.owned_path = path_from_counts(counts) end
end

local function reconcile(current)
    -- Native cleanup callbacks can run a previously scheduled lifecycle while
    -- reset is in progress. It must not recreate a just-retired handle.
    if reset_depth > 0 or current.clearing then return end
    local hero, path = current.hero, current.owned_path
    if current.unavailable or not path or not valid(hero) or not hero:IsAlive() then
        clear(current)
        return
    end
    -- The foot layer never uses weapon/hand bones. Wait for a native model on
    -- first spawn, then let CP0 follow the entity without Lua position updates.
    local loaded, model = pcall(hero.GetModelName, hero)
    if not loaded or type(model) ~= "string" or model == "" then
        clear(current)
        return
    end
    if current.particle_id ~= nil and current.applied_path == path then return end
    clear(current)
    local particle
    local ok, err = pcall(function()
        particle = ParticleManager:CreateParticle(path, PATTACH_ABSORIGIN_FOLLOW, hero)
        assert(type(particle) == "number" and particle >= 0 and particle < math.huge
            and particle == math.floor(particle), "owned particle creation returned no valid ID")
        current.particle_id, current.applied_path = particle, path
        ParticleManager:SetParticleControlEnt(particle, 0, hero,
            PATTACH_ABSORIGIN_FOLLOW, "", hero:GetAbsOrigin(), true)
    end)
    if not ok then
        if current.particle_id == particle then clear(current) end
        if current.setup_error ~= tostring(err) then
            print("[WeaponOwnedVisual] setup failed: " .. tostring(err))
        end
        current.setup_error = tostring(err)
        return
    end
    current.setup_error = nil
end

function M.on_inventory_changed(payload)
    local id = player_id(payload.player_id)
    local counts = payload.snapshot and payload.snapshot.counts
    if not id or type(counts) ~= "table" then return end
    local current = state(id)
    if current.unavailable then return end
    -- Read the final authoritative snapshot, not individual negative/positive
    -- deltas: crafting 00 -> 01 retains the exact same aura handle.
    current.owned_path = path_from_counts(counts)
    reconcile(current)
end

function M.on_hero_summoned(payload)
    local id = player_id(payload.player_id)
    if not id or not owner_matches(payload.unit, id) then return end
    local current = state(id)
    if current.unavailable then return end
    if current.hero ~= payload.unit then clear(current) end
    current.hero = payload.unit
    sync_inventory(current, id)
    reconcile(current)
end

function M.on_unavailable(payload)
    local id = player_id(payload.player_id)
    if not id then return end
    local current = state(id)
    current.unavailable, current.hero, current.owned_path = true, nil, nil
    clear(current)
end

function M.on_hero_removed(payload)
    local id = player_id(payload.player_id)
    local current = id and states[id]
    if not current or current.hero ~= payload.unit then return end
    -- Delete only the entity binding; ownership and player availability survive.
    current.hero = nil
    clear(current)
end

function M.poll()
    for _, current in pairs(states) do reconcile(current) end
end

function M.precache(context)
    local seen = {}
    for _, profile in ipairs(profiles.rows) do
        local path = profile.owned_particle
        if profile.enabled ~= false and path and path ~= "" and not seen[path] then
            PrecacheResource("particle", path, context)
            seen[path] = true
        end
    end
end

function M.reset(same_world)
    reset_depth = reset_depth + 1
    if same_world then
        for _, current in pairs(states) do clear(current) end
    else
        -- Integer particle IDs can be reused by the next Tools world.
        states = {}
    end
    paths_by_content = {}
    for _, definition in ipairs(weapons.rows) do
        local profile = profiles.by_id[definition.series_id]
        local path = profile and profile.owned_particle
        if definition.enabled ~= false and profile and profile.enabled ~= false
            and path and path ~= "" then
            paths_by_content[definition.content_id] = path
        end
    end
    if same_world then
        for id, current in pairs(states) do
            if not current.unavailable then sync_inventory(current, id) end
        end
    end
    reset_depth = reset_depth - 1
end

function M.debug_snapshot(id)
    local current = states[player_id(id)]
    if not current then return nil end
    return { owned_path = current.owned_path, particle_id = current.particle_id,
        applied_path = current.applied_path, unavailable = current.unavailable == true,
        hero = valid(current.hero) and current.hero:entindex() or -1 }
end

return M
