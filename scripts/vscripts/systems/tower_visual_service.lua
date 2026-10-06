-- Cosmetic projection of authoritative building state. No damage or orders.
local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local projection = require("systems/tower_rank_projection")
local profiles = require("config/generated/tower_visual_profiles")
local laser_effect_selector = require("systems/tower_laser_effect_selector")
local tower_skills = require("systems/tower_skill_runtime")
local laser_visual = require("systems/tower_laser_visual")
local M = {}
local tracked = {}
local generation, bound_world = 0, nil
local base_projectile = "particles/base_attacks/ranged_goodguy.vpcf"
local prefix = "particles/survival/towers/"
local trial_bases = {
    dazzle_weave = "trial/death_ground",
    willow_shadow_realm = "death_willow/shadow_ground",
    leshrac_edict = "trial/mystery_ground",
    kinetic_markers = "trial/lightning_ground",
    clinkz_embers = "trial/multi_ground",
    ice_vortex = "trial/frost_ground",
}
local portal_bases = { io_blue_portal = "ice_portal", io_amber_portal = "amber_portal" }
local portal_layers = { "ground", "dark_center", "interior", "sparkles" }
-- Native Shadow Dance smoke bundle, without Slark-specific eye attachments.
local ultimate_shadow = "particles/units/heroes/hero_slark/slark_shadow_dance_dummy.vpcf"
-- Bulldoze's persistent foot layers; omit its body/hand effects and cast flash.
local machine_base = {
    "particles/units/heroes/hero_spirit_breaker/spirit_breaker_haste_owner_dark.vpcf",
    "particles/units/heroes/hero_spirit_breaker/spirit_breaker_haste_owner_timer.vpcf",
}
local anti_air_base = {
    "particles/units/heroes/hero_templar_assassin/templar_assassin_trap_rings.vpcf",
    "particles/units/heroes/hero_templar_assassin/templar_assassin_trap_rings_inner.vpcf",
}

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

local function add_ultimate_shadow(entry)
    local unit = entry.unit
    local id = ParticleManager:CreateParticle(ultimate_shadow,
        PATTACH_ABSORIGIN_FOLLOW, unit)
    assert(type(id) == "number" and id >= 0, "ultimate shadow returned no valid ID")
    entry.particles[#entry.particles + 1] = id
    local origin = unit:GetAbsOrigin()
    ParticleManager:SetParticleControlEnt(id, 0, unit,
        PATTACH_ABSORIGIN_FOLLOW, "", origin, true)
    -- All native smoke layers emit around CP1. Bind to the torso so the
    -- cloud surrounds the model and follows relocation without a Lua thinker.
    ParticleManager:SetParticleControlEnt(id, 1, unit,
        PATTACH_POINT_FOLLOW, "attach_hitloc",
        Vector(origin.x, origin.y, origin.z + 80), true)
end

local function add_machine_base(entry, ring_only)
    for offset, path in ipairs(machine_base) do
        if not ring_only or offset == 2 then
            local id = ParticleManager:CreateParticle(path,
                PATTACH_ABSORIGIN_FOLLOW, entry.unit)
            assert(type(id) == "number" and id >= 0, "machine base returned no valid ID")
            entry.particles[#entry.particles + 1] = id
            -- Native layers supply their own ground offset (18/20 units) and size.
            -- Bind at the feet, not at attach_hitloc; ring_only omits the dark layer.
            ParticleManager:SetParticleControlEnt(id, 0, entry.unit,
                PATTACH_ABSORIGIN_FOLLOW, "", entry.unit:GetAbsOrigin(), true)
        end
    end
end

local function add_anti_air_base(entry)
    for _, path in ipairs(anti_air_base) do
        local id = ParticleManager:CreateParticle(path,
            PATTACH_ABSORIGIN_FOLLOW, entry.unit)
        assert(type(id) == "number" and id >= 0, "anti-air base returned no valid ID")
        entry.particles[#entry.particles + 1] = id
        ParticleManager:SetParticleControlEnt(id, 0, entry.unit,
            PATTACH_ABSORIGIN_FOLLOW, "", entry.unit:GetAbsOrigin(), true)
        -- These native children normally receive neutral HSV from the trap
        -- parent. Zero saturation/value would make the standalone rings dark.
        ParticleManager:SetParticleControl(id, 62, Vector(0, 1, 1))
    end
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
    local native_base = ""
    if profile and rank.rarity ~= "N" then
        -- CSV row rarity differs from overhead rank. Resolve form overrides
        -- using the authoritative absolute route position (Fireline is R).
        native_base = profile["native_base_" .. string.lower(rank.rarity)]
            or profile.native_base or ""
    end
    local radius, color
    if profile then
        local tier = string.lower(rank.rarity)
        radius = profile["radius_" .. tier] or profile.radius_ssr
        local tier_color = profile["color_" .. tier]
        color = type(tier_color) == "table" and #tier_color >= 3
            and tier_color or profile.color
    end
    -- The replacement has no red-star crown; all ten SSR upgrades share its
    -- color and lifetime. Other profiles retain their existing accent policy.
    local red_accent = rank.red_stars > 0
        and native_base ~= "willow_shadow_realm" and not portal_bases[native_base]
    local key = tostring(profile_id) .. ":" .. rank.rarity
        .. ":" .. tostring(red_accent)
        .. ":" .. tostring(native_base)
    if profile then
        -- A same-tier visual configuration update must retire the old ring.
        key = key .. ":" .. tostring(radius) .. ":" .. tostring(profile.alpha)
            .. ":" .. table.concat(color or {}, ",")
    end
    if profile_id == "class_7" then
        -- Native trap rings initialize world-space particles, without position
        -- lock. Recreate on the existing move event; no polling/update timer.
        local origin = unit:GetAbsOrigin()
        key = key .. ":" .. tostring(origin.x) .. ":" .. tostring(origin.y)
            .. ":" .. tostring(origin.z)
    end
    local laser
    for id in pairs(tower_skills.get(unit) or {}) do
        local effect = laser_effect_selector.get(unit, id, state)
        if effect and effect.enabled ~= false then laser = effect; break end
    end
    key = key .. ":" .. tostring(laser and laser.effect_key or "")
    if laser then
        unit.survival_projectile_model = ""
        unit:SetRangedProjectileName("")
    end
    if rank.rarity ~= "N" and (not profile or profile.enabled == false) then
        M.remove(index)
        return false
    end
    local old = tracked[index]
    if old and old.unit == unit and old.key == key then return true end
    M.remove(index)
    local entry = { unit = unit, key = key, particles = {} }
    tracked[index] = entry
    if laser and laser.beam_mode ~= "native" then
        local ok, err = pcall(function()
            add(entry, "laser_charge", 1, 1, { laser.color_r, laser.color_g, laser.color_b })
            ParticleManager:SetParticleControl(entry.particles[#entry.particles], 2, laser_visual.color(laser))
        end)
        if not ok then M.remove(index); print("[TowerVisual] laser charge failed: " .. tostring(err)); return false end
    end
    if rank.rarity == "N" then
        -- Reference low-tier towers also use this native projectile. Only its
        -- art changes; native attack timing/speed and damage remain untouched.
        return true
    end
    local ok, err = pcall(function()
        -- A replacement owns the whole base, including former detail/crown art.
        local portal = portal_bases[native_base]
        if portal then
            -- Bind every layer explicitly. An invisible empty parent must not
            -- decide the visibility or CP inheritance of the permanent base.
            for _, layer in ipairs(portal_layers) do
                add(entry, portal .. "/" .. layer, radius, profile.alpha, color)
            end
            return
        end
        local trial = trial_bases[native_base]
        if trial then add(entry, trial, radius, profile.alpha, color); return end
        if native_base == "bulldoze_ring" then
            add_machine_base(entry, true); return
        end
        if native_base == "bulldoze" then
            add(entry, "trial/valley_durable", radius, profile.alpha, color)
            add_machine_base(entry); return end
        if native_base == "psionic_trap" then
            add(entry, "trial/valley_evil", radius, profile.alpha, color)
            add_anti_air_base(entry); return end
        add(entry, profile.core, radius, profile.alpha, color)
        if rank.rarity ~= "R" then
            local detail = rank.rarity == "SSR" and profile.detail_ssr or profile.detail
            -- Profession detail stays inside the core footprint. SSR changes
            -- its pattern/rhythm without allocating additional outer rings.
            add(entry, detail, radius, profile.alpha * 0.48, color)
        end
        if rank.rarity == "UR" or rank.red_stars > 0 then
            add(entry, profile.crown, radius * 0.78, profile.alpha * 0.38, color)
        end
        if rank.rarity == "UR" then add_ultimate_shadow(entry) end
    end)
    if not ok then
        M.remove(index)
        print("[TowerVisual] particle setup failed: " .. tostring(err))
    end
    return ok
end

function M.precache(context)
    PrecacheResource("particle", base_projectile, context)
    PrecacheResource("particle", "particles/units/heroes/hero_clinkz/clinkz_searing_arrow_linear_proj.vpcf", context)
    PrecacheResource("particle", ultimate_shadow, context)
    for _, name in pairs(trial_bases) do
        PrecacheResource("particle", prefix .. name .. ".vpcf", context)
    end
    for _, portal in pairs(portal_bases) do
        for _, layer in ipairs(portal_layers) do
            PrecacheResource("particle", prefix .. portal .. "/" .. layer .. ".vpcf", context)
        end
    end
    for _, style in ipairs({"dark", "durable", "evil"}) do
        PrecacheResource("particle", prefix .. "trial/valley_" .. style .. ".vpcf", context)
    end
    for _, path in ipairs(machine_base) do PrecacheResource("particle", path, context) end
    for _, path in ipairs(anti_air_base) do PrecacheResource("particle", path, context) end
    PrecacheResource("particle", prefix .. "laser_charge.vpcf", context)
    PrecacheResource("particle", prefix .. "laser_blood.vpcf", context)
    PrecacheResource("particle", prefix .. "laser_afterglow.vpcf", context)
    local seen = {}
    for _, row in ipairs(profiles.rows) do
        if row.enabled ~= false then
            for _, key in ipairs({"core", "detail", "detail_ssr", "crown"}) do
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
