-- Cosmetic projection of authoritative building state. No damage or orders.
local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local projection = require("systems/tower_rank_projection")
local profiles = require("config/generated/tower_visual_profiles")
local M = {}
local tracked = {}
local generation, bound_world = 0, nil
local base_projectile = "particles/base_attacks/ranged_goodguy.vpcf"
local prefix = "particles/survival/towers/"

local function valid(unit)
    return unit and not unit:IsNull()
end

function M.remove(entindex, unit)
    local entry = tracked[tonumber(entindex)]
    if not entry or (unit and entry.unit ~= unit) then return end
    -- Drop ownership before engine calls; death/removal may re-enter cleanup.
    tracked[tonumber(entindex)] = nil
    for _, id in ipairs(entry.particles) do
        -- A failed optional engine visual must not strand the remaining IDs.
        local destroyed, destroy_error = pcall(ParticleManager.DestroyParticle,
            ParticleManager, id, true)
        local released, release_error = pcall(ParticleManager.ReleaseParticleIndex,
            ParticleManager, id)
        if not destroyed or not released then
            print("[TowerVisual] particle cleanup failed: "
                .. tostring((not destroyed and destroy_error) or release_error))
        end
    end
end

local function add(entry, name, radius, alpha, color)
    if not name or name == "" then return end
    local id = ParticleManager:CreateParticle(prefix .. name .. ".vpcf",
        PATTACH_ABSORIGIN_FOLLOW, entry.unit)
    assert(type(id) == "number" and id >= 0, "tower particle creation returned no valid ID")
    entry.particles[#entry.particles + 1] = id
    ParticleManager:SetParticleControlEnt(id, 0, entry.unit,
        PATTACH_ABSORIGIN_FOLLOW, "", entry.unit:GetAbsOrigin(), true)
    ParticleManager:SetParticleControl(id, 1, Vector(radius, 0, alpha))
    ParticleManager:SetParticleControl(id, 2, Vector(
        tonumber(color[1]) or 255, tonumber(color[2]) or 255, tonumber(color[3]) or 255))
end

function M.apply(state)
    local rank = projection.project(state)
    local unit = state and state.unit
    if not rank or not valid(unit) then return false end
    local index = unit:entindex()
    if not unit:IsAlive() then M.remove(index, unit); return false end
    if rank.rarity == "N" then
        -- apply_tower_level restores the row's projectile on every upgrade.
        -- Reapply this art even when the unchanged base style needs no rebuild.
        -- Relocation's deferred native refresh reads this same visual cache.
        unit.survival_projectile_model = base_projectile
        unit:SetRangedProjectileName(base_projectile)
    end
    local profile_id = rank.rarity == "UR" and "ultimate" or state.tower_class
    local profile = profiles.by_id[profile_id]
    local key = tostring(profile_id) .. ":" .. rank.rarity
        .. ":" .. tostring(rank.red_stars > 0)
    if rank.rarity ~= "N" and (not profile or profile.enabled == false) then
        M.remove(index)
        return false
    end
    local old = tracked[index]
    if old and old.unit == unit and old.key == key then return true end
    M.remove(index)
    local entry = { unit = unit, key = key, particles = {} }
    tracked[index] = entry
    if rank.rarity == "N" then
        -- Reference low-tier towers also use this native projectile. Only its
        -- art changes; native attack timing/speed and damage remain untouched.
        return true
    end
    local radius = profile["radius_" .. string.lower(rank.rarity)] or profile.radius_ssr
    local ok, err = pcall(function()
        add(entry, profile.core, radius, profile.alpha, profile.color)
        if rank.rarity ~= "R" then
            add(entry, profile.detail, radius * 1.08, profile.alpha * 0.65, profile.color)
        end
        if rank.rarity == "UR" or rank.red_stars > 0 then
            add(entry, profile.crown, radius * 0.78, profile.alpha * 0.55, profile.color)
        end
    end)
    if not ok then
        M.remove(index)
        print("[TowerVisual] particle setup failed: " .. tostring(err))
    end
    return ok
end

function M.precache(context)
    PrecacheResource("particle", base_projectile, context)
    local seen = {}
    for _, row in ipairs(profiles.rows) do
        if row.enabled ~= false then
            for _, key in ipairs({"core", "detail", "crown"}) do
                local name = row[key]
                if name and name ~= "" and not seen[name] then
                    PrecacheResource("particle", prefix .. name .. ".vpcf", context)
                    seen[name] = true
                end
            end
        end
    end
end

local function sweep()
    local finished = GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME
    for index, entry in pairs(tracked) do
        if finished or not valid(entry.unit) or not entry.unit:IsAlive() then M.remove(index) end
    end
    return not finished
end

function M.init()
    local world = GameRules:GetGameModeEntity()
    if world == bound_world then
        -- Explicit reinitialization in the same world must retire live effects.
        for index in pairs(tracked) do M.remove(index) end
    end
    -- A new world can reuse particle IDs; never destroy those from the old one.
    tracked = {}
    bound_world = world
    generation = generation + 1
    local current_generation = generation
    local function subscribe(name, callback)
        event_bus.subscribe(name, function(payload)
            if current_generation == generation then callback(payload or {}) end
        end)
    end
    subscribe(events.BUILDING_CREATED, M.apply)
    subscribe(events.BUILDING_CHANGED, M.apply)
    subscribe(events.TOWER_FUSION_RUNTIME_CHANGED, M.apply)
    subscribe(events.BUILDING_DESTROYED, function(payload)
        M.remove(payload.entindex, payload.unit)
    end)
    subscribe(events.TOWER_FUSION_RUNTIME_REMOVED, function(payload)
        M.remove(payload.entindex)
    end)
    subscribe(events.ENGINE_ENTITY_KILLED, function(payload)
        if valid(payload.victim) then M.remove(payload.victim:entindex(), payload.victim) end
    end)
    local result = event_bus.request(events.BUILDING_LIST_REQUEST, {})
    for _, state in ipairs(result and result.buildings or {}) do M.apply(state) end
    scheduler.every(0.5, function()
        if current_generation ~= generation then return false end
        return sweep()
    end, "tower_visual_lifecycle")
end

function M.debug_snapshot(entindex)
    if entindex ~= nil then
        local entry = tracked[tonumber(entindex)]
        local ids = {}
        for _, id in ipairs(entry and entry.particles or {}) do ids[#ids + 1] = id end
        return { tracked = entry ~= nil, key = entry and entry.key or "", particle_ids = ids }
    end
    local towers, count = 0, 0
    for _, entry in pairs(tracked) do
        towers = towers + 1
        count = count + #entry.particles
    end
    return { towers = towers, particles = count }
end

M._sweep_for_test = sweep
return M
