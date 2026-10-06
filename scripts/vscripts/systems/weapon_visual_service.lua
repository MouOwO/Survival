local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local weapons = require("config/generated/weapon_definitions")
local profiles = require("config/generated/weapon_visual_profiles")
local owned_visual = require("systems/weapon_owned_visual")
local hero_weapon = require("systems/hero_weapon_cosmetic_service")

local M = {}
local states = {}
local preview_states = {}
local generation = 0
local world_token
local particle_paths = {
    glow = "particles/survival/weapons/weapon_glow.vpcf",
    trail = "particles/survival/weapons/weapon_trail.vpcf",
    shards = "particles/survival/weapons/weapon_shards.vpcf",
}
local poll_task = "weapon_visual_lifecycle"
local progress_by_id = {}

local function valid(unit)
    return unit and not unit:IsNull()
end

local function alive(unit)
    return valid(unit) and unit:IsAlive()
end

local function player_id(value)
    local id = tonumber(value)
    if id and id >= 0 and id == math.floor(id) then return id end
end

local function owner_matches(unit, id)
    if not valid(unit) then return false end
    local owner = tonumber(unit.survival_player_id)
    if owner == nil and unit.GetPlayerOwnerID then
        owner = tonumber(unit:GetPlayerOwnerID())
    end
    return owner == id
end

local function retire_particle(particle)
    -- Release must still run when Destroy fails, and one failed handle must
    -- never prevent cleanup of the remaining independently owned particles.
    local destroyed, destroy_error = pcall(ParticleManager.DestroyParticle,
        ParticleManager, particle, false)
    local released, release_error = pcall(ParticleManager.ReleaseParticleIndex,
        ParticleManager, particle)
    if not destroyed or not released then
        print("[WeaponVisual] particle cleanup failed: "
            .. tostring((not destroyed and destroy_error) or release_error))
    end
end

local function valid_particle(particle)
    return type(particle) == "number" and particle >= 0
        and particle == math.floor(particle)
end

local function clear(current)
    local particles, impacts = current.particles or {}, current.impacts or {}
    -- Revoke ownership before engine calls: an endcap/remove callback must
    -- never observe this same handle as still live and destroy it twice.
    current.particles, current.impacts = {}, {}
    for _, task in pairs(impacts) do if task then scheduler.cancel(task) end end
    for _, particle in ipairs(particles) do
        retire_particle(particle)
    end
    for particle in pairs(impacts) do
        retire_particle(particle)
    end
end

local function rgb(values)
    return Vector(tonumber(values[1]) or 255,
        tonumber(values[2]) or 255, tonumber(values[3]) or 255)
end

local function blend(a, b, progress)
    return tonumber(a) + (tonumber(b) - tonumber(a)) * progress
end

local function visual_binding(unit)
    -- CreateUnitByName can return before its native model is assigned. A
    -- successful particle allocation at that moment still has no valid bone.
    local ok, model = pcall(function() return unit:GetModelName() end)
    if not ok or type(model) ~= "string" or model == "" then return nil end
    local binding = { model = model }
    if type(unit.ScriptLookupAttachment) == "function" then
        -- Native Juggernaut exposes attach_sword (Workshop verified index 2),
        -- while attack1/weapon are absent. Prefer its hand over torso hitloc.
        -- Other hero attachment choices remain model-dependent fallbacks.
        for _, name in ipairs({ "attach_attack1", "attach_weapon", "attach_sword", "attach_hitloc" }) do
            local found, index = pcall(unit.ScriptLookupAttachment, unit, name)
            index = found and tonumber(index) or nil
            if index and index > 0 then
                binding.anchor, binding.index = name, index
                break
            end
        end
    end
    return binding
end

local function add_layer(current, path, radius, emission, alpha, color)
    local unit, point = current.hero, current.anchor
    local attach = point and PATTACH_POINT_FOLLOW or PATTACH_ABSORIGIN_FOLLOW
    local particle = ParticleManager:CreateParticle(path, attach, unit)
    assert(valid_particle(particle), "weapon particle creation returned no valid ID")
    current.particles[#current.particles + 1] = particle
    ParticleManager:SetParticleControlEnt(
        particle, 0, unit, attach, point or "", unit:GetAbsOrigin(), true)
    ParticleManager:SetParticleControl(particle, 1, Vector(radius, emission, alpha))
    ParticleManager:SetParticleControl(particle, 2, rgb(color))
end

local function refresh(current, binding)
    clear(current)
    local definition = weapons.by_id[current.content_id]
    local profile = definition and profiles.by_id[definition.series_id]
    if not profile or profile.enabled == false
        or definition.equipment_slot ~= "main_hand" then
        current.profile = nil
        return
    end
    current.profile = profile
    if not alive(current.hero) then return end
    binding = binding or visual_binding(current.hero)
    current.model_name = binding and binding.model or nil
    current.anchor = binding and binding.anchor or nil
    current.anchor_index = binding and binding.index or nil
    if not binding then return true, "waiting_for_model" end
    local ok, err = pcall(function()
        local progress = progress_by_id[current.content_id] or 0
        local glow = blend(profile.glow_radius_min, profile.glow_radius_max, progress)
        local trail = blend(profile.trail_radius_min, profile.trail_radius_max, progress)
        local emission = blend(profile.emission_min, profile.emission_max, progress)
        local alpha = blend(profile.alpha_min, profile.alpha_max, progress)
        add_layer(current, particle_paths.glow, glow, 1, alpha, profile.primary_rgb)
        add_layer(current, particle_paths.trail, trail, emission, alpha,
            profile.secondary_rgb)
        if profile.shards == true then
            add_layer(current, particle_paths.shards, 3 + progress * 2,
                3 + progress * 3, alpha * 0.7, profile.secondary_rgb)
        end
    end)
    if not ok then
        clear(current)
        if current.setup_error ~= tostring(err) then
            print("[WeaponVisual] particle setup failed: " .. tostring(err))
        end
        current.setup_error = tostring(err)
        return false, err
    end
    current.setup_error = nil
    return true
end

local function state(id)
    if not states[id] then
        states[id] = { content_id = "", particles = {}, impacts = {}, next_impact = 0 }
    end
    return states[id]
end

local function on_equipped(payload)
    local id = player_id(payload.player_id)
    if not id or payload.slot ~= "main_hand" then return end
    hero_weapon.on_equipped(payload)
    local current = state(id)
    local content_id = tostring(payload.content_id or "")
    if current.content_id == content_id then return end
    current.content_id = content_id
    refresh(current)
end

local function on_hero(payload)
    local id = player_id(payload.player_id)
    if not id or not owner_matches(payload.unit, id) then return end
    owned_visual.on_hero_summoned(payload)
    hero_weapon.on_hero_summoned(payload)
    local current = state(id)
    clear(current)
    current.hero = payload.unit
    current.next_impact = 0
    local result = event_bus.request(events.WEAPON_EQUIPMENT_GET_REQUEST, {
        player_id = id,
    })
    if result and result.snapshot then
        current.content_id = tostring(result.snapshot.main_hand_content_id or "")
    end
    refresh(current)
end

local function on_attack(payload)
    local id = player_id(payload.player_id)
    local current = id and states[id]
    if not current or payload.attacker ~= current.hero
        or payload.is_multishot_secondary == true
        or payload.is_main_attack == false
        or not alive(current.hero) or not valid(payload.target) then return end
    local profile = current.profile
    local path = profile and profile.impact_particle
    if not path or path == "" then return end
    local now = GameRules:GetGameTime()
    if now < current.next_impact then return end
    current.next_impact = now + math.max(0.35, tonumber(profile.impact_cooldown) or 0.6)
    local position = payload.target:GetAbsOrigin()
    local particle
    local ok, err = pcall(function()
        particle = ParticleManager:CreateParticle(path, PATTACH_WORLDORIGIN, current.hero)
        assert(valid_particle(particle), "weapon impact creation returned no valid ID")
        -- Own the handle before control-point calls, which can fail. False marks
        -- an owned impact whose expiry task has not yet been created.
        current.impacts[particle] = false
        ParticleManager:SetParticleControl(particle, 0, position)
        -- Native Skadi/Desolator explosion children originate from CP3; leaving
        -- it unset emits their sparks at world zero. Liquid Fire reads CP1 as
        -- its visual ring radius and expansion speed, independent of damage.
        ParticleManager:SetParticleControl(particle, 3, position)
        ParticleManager:SetParticleControl(particle, 1,
            Vector((tonumber(profile.glow_radius_max) or 20) * 4, 0, 60))
        -- Finite impact is still bounded explicitly, including during an equipment
        -- swap or hero removal. It never creates projectiles or applies damage.
        if current.impacts[particle] == nil then return end
        current.impacts[particle] = scheduler.after(1.5, function()
            if current.impacts[particle] ~= nil then
                current.impacts[particle] = nil
                retire_particle(particle)
            end
        end)
    end)
    if not ok then
        if valid_particle(particle) and current.impacts[particle] ~= nil then
            local task = current.impacts[particle]
            current.impacts[particle] = nil
            if task then scheduler.cancel(task) end
            retire_particle(particle)
        end
        print("[WeaponVisual] impact setup failed: " .. tostring(err))
    end
end

local function poll_states(collection)
    for _, current in pairs(collection) do
        if not alive(current.hero) then
            if #current.particles > 0 or next(current.impacts) then clear(current) end
            if not valid(current.hero) then current.hero = nil end
        elseif current.profile then
            local binding = visual_binding(current.hero)
            if not binding then
                if #current.particles > 0 or next(current.impacts) then clear(current) end
                current.model_name, current.anchor, current.anchor_index = nil, nil, nil
            elseif #current.particles == 0 or current.model_name ~= binding.model
                or current.anchor ~= binding.anchor or current.anchor_index ~= binding.index then
                refresh(current, binding)
            end
        end
    end
end

local function lifecycle()
    poll_states(states)
    poll_states(preview_states)
    owned_visual.poll()
    hero_weapon.poll()
end

-- A Tools display uses exactly the production profile, stage normalization,
-- attachment selection and refresh path. It owns no player equipment state
-- and never publishes HERO_SUMMONED / WEAPON_EQUIPPED_CHANGED events.
function M.preview(hero, content_id)
    if type(IsServer) ~= "function" or not IsServer()
        or type(IsInToolsMode) ~= "function" or not IsInToolsMode() then
        return nil, "tools_server_required"
    end
    local current_world = GameRules.GetGameModeEntity
        and GameRules:GetGameModeEntity() or GameRules
    if generation == 0 or current_world ~= world_token then
        return nil, "weapon_visual_service_not_initialized_for_world"
    end
    if not alive(hero) then return nil, "live_preview_hero_required" end
    local definition = weapons.by_id[tostring(content_id or "")]
    local profile = definition and profiles.by_id[definition.series_id]
    if not definition or definition.equipment_slot ~= "main_hand"
        or not profile or profile.enabled == false then
        return nil, "enabled_main_hand_profile_required"
    end
    for _, current in pairs(states) do
        if current.hero == hero then return nil, "hero_has_live_equipment_visual_state" end
    end
    for _, current in pairs(preview_states) do
        if current.hero == hero then return nil, "hero_already_has_preview" end
    end
    local current = { hero = hero, content_id = definition.content_id,
        particles = {}, impacts = {}, next_impact = 0 }
    local handle = {}
    local expected_generation = generation
    preview_states[handle] = current
    local function active()
        local world = GameRules.GetGameModeEntity
            and GameRules:GetGameModeEntity() or GameRules
        return expected_generation == generation and world == current_world
            and preview_states[handle] == current
    end
    function handle:dispose()
        if active() then
            preview_states[self] = nil
            clear(current)
        end
    end
    function handle:status()
        local is_active = active()
        local ids = {}
        if is_active then
            for index, id in ipairs(current.particles) do ids[index] = id end
        end
        return { active = is_active, content_id = current.content_id,
            series_id = definition.series_id, stage = definition.stage,
            progress = progress_by_id[current.content_id], anchor = current.anchor,
            model_name = current.model_name, anchor_index = current.anchor_index,
            binding_state = current.model_name and "ready" or "waiting_for_model",
            particle_count = #ids, particle_ids = ids,
            hero = is_active and valid(hero) and hero:entindex() or -1 }
    end
    local ok, applied, err = pcall(refresh, current)
    if not ok or applied == false then
        handle:dispose()
        return nil, "preview_apply_failed: " .. tostring(ok and err or applied)
    end
    return handle, current.model_name and "ready" or "waiting_for_model"
end

function M.precache(context)
    owned_visual.precache(context)
    hero_weapon.precache(context)
    for _, path in pairs(particle_paths) do PrecacheResource("particle", path, context) end
    local seen = {}
    for _, profile in ipairs(profiles.rows) do
        local path = profile.impact_particle
        if profile.enabled ~= false and path and path ~= "" and not seen[path] then
            PrecacheResource("particle", path, context)
            seen[path] = true
        end
    end
end

local function on_player_unavailable(payload)
    owned_visual.on_unavailable(payload)
    hero_weapon.on_unavailable(payload)
end

function M.init()
    local current_world = GameRules.GetGameModeEntity
        and GameRules:GetGameModeEntity() or GameRules
    owned_visual.reset(current_world == world_token)
    hero_weapon.reset(current_world == world_token)
    if current_world == world_token then
        for _, current in pairs(states) do clear(current) end
        for _, current in pairs(preview_states) do clear(current) end
    end
    -- A new Tools world may already have reused an old particle's integer
    -- handle. Discard stale ownership instead of destroying that new effect.
    world_token = current_world
    scheduler.cancel(poll_task)
    states, preview_states, progress_by_id = {}, {}, {}
    generation = generation + 1
    local active_generation = generation
    local grouped = {}
    for _, definition in ipairs(weapons.rows) do
        if definition.equipment_slot == "main_hand" then
            local series = definition.series_id
            grouped[series] = grouped[series] or {}
            table.insert(grouped[series], definition)
        end
    end
    for _, definitions in pairs(grouped) do
        table.sort(definitions, function(a, b)
            return (tonumber(a.stage) or 0) < (tonumber(b.stage) or 0)
        end)
        for index, definition in ipairs(definitions) do
            -- Stage 99 denotes max in early series; epic starts at stage 0.
            -- Normalize actual CSV progression rather than treating 99 as 99x.
            progress_by_id[definition.content_id] = (index - 1) / math.max(1, #definitions - 1)
        end
    end
    -- event_bus.reset reuses numeric subscription tokens between Tools runs.
    -- Old tokens must not unsubscribe a different module in a new session.
    -- Generation guards also make an explicit hot init harmless.
    for event_name, handler in pairs({
        [events.WEAPON_EQUIPPED_CHANGED] = on_equipped,
        [events.HERO_SUMMONED] = on_hero,
        [events.HERO_MAIN_ATTACK_LANDED] = on_attack,
        [events.CONTENT_INVENTORY_CHANGED] = owned_visual.on_inventory_changed,
        [events.PLAYER_DEFEATED] = on_player_unavailable,
        [events.PLAYER_DISCONNECTED] = on_player_unavailable,
    }) do
        local callback = handler
        event_bus.subscribe(event_name, function(payload)
            if generation == active_generation then callback(payload) end
        end)
    end
    scheduler.every(0.25, lifecycle, poll_task)
end

function M.debug_snapshot(id)
    local current = states[player_id(id)]
    if not current then return nil end
    return { content_id = current.content_id, anchor = current.anchor,
        model_name = current.model_name, anchor_index = current.anchor_index,
        binding_state = current.model_name and "ready" or "waiting_for_model",
        particle_count = #current.particles,
        hero = valid(current.hero) and current.hero:entindex() or -1 }
end

return M
