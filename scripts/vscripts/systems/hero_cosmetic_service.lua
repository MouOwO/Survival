local config = require("config/hero_cosmetics_config")
local logger = require("core/logger")

local M = {}

local cosmetics_by_hero = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function safe_call(target, method_name, ...)
    local method = target and target[method_name]
    if type(method) ~= "function" then
        return false, nil
    end
    return pcall(method, target, ...)
end

local function remove_entity(entity)
    if not valid_entity(entity) then
        return
    end
    if type(UTIL_Remove) == "function" then
        pcall(UTIL_Remove, entity)
        return
    end
    safe_call(entity, "RemoveSelf")
end

local function destroy_particle(particle_id)
    if particle_id == nil or not ParticleManager then
        return
    end
    safe_call(ParticleManager, "DestroyParticle", particle_id, true)
    safe_call(ParticleManager, "ReleaseParticleIndex", particle_id)
end

local function clear_cosmetics(hero_entindex)
    local state = cosmetics_by_hero[hero_entindex]
    if not state then
        return
    end
    for _, particle_id in ipairs(state.particles or {}) do
        destroy_particle(particle_id)
    end
    for _, wearable in ipairs(state.wearables or {}) do
        remove_entity(wearable)
    end
    cosmetics_by_hero[hero_entindex] = nil
end

local function hide_default_wearables(hero)
    local ok, child = safe_call(hero, "FirstMoveChild")
    if not ok then
        return
    end

    local no_draw = rawget(_G, "EF_NODRAW") or 32

    while valid_entity(child) do
        local next_ok, next_child = safe_call(child, "NextMovePeer")
        local class_ok, class_name = safe_call(child, "GetClassname")
        if class_ok and class_name == "dota_item_wearable" then
            safe_call(child, "AddEffects", no_draw)
        end
        child = next_ok and next_child or nil
    end
end

local function show_default_wearables(hero)
    local ok, child = safe_call(hero, "FirstMoveChild")
    if not ok then return end
    local no_draw = rawget(_G, "EF_NODRAW") or 32
    while valid_entity(child) do
        local next_ok, next_child = safe_call(child, "NextMovePeer")
        local class_ok, class_name = safe_call(child, "GetClassname")
        if class_ok and class_name == "dota_item_wearable" then
            safe_call(child, "RemoveEffects", no_draw)
        end
        child = next_ok and next_child or nil
    end
end

local function normalize_wearable(entry, index)
    if type(entry) == "string" then
        return "wearable_" .. tostring(index), entry
    end
    if type(entry) == "table" then
        return entry.id or "wearable_" .. tostring(index), entry.model
    end
    return "wearable_" .. tostring(index), nil
end

local function spawn_wearable(hero, component_id, model_path)
    if not model_path or model_path == "" then
        logger.warn("HeroCosmetic", "missing model for " .. tostring(component_id))
        return nil
    end
    local ok, wearable = pcall(
        SpawnEntityFromTableSynchronous,
        "prop_dynamic",
        {
            model = model_path,
            DefaultAnim = "idle",
        }
    )
    if not ok or not valid_entity(wearable) then
        logger.warn(
            "HeroCosmetic",
            "failed to create wearable " .. tostring(component_id)
                .. ": " .. tostring(model_path)
        )
        return nil
    end

    safe_call(wearable, "SetOwner", hero)
    safe_call(wearable, "FollowEntity", hero, true)
    return wearable
end

local function resolve_attach_type(name)
    if type(name) == "number" then
        return name
    end
    if type(name) == "string" then
        local value = rawget(_G, name)
        if type(value) == "number" then
            return value
        end
    end
    return rawget(_G, "PATTACH_ABSORIGIN_FOLLOW") or 1
end

local function spawn_particle(hero, particle, components)
    if not ParticleManager or type(particle) ~= "table"
        or not particle.path or particle.path == "" then
        return nil
    end
    local owner = components[particle.owner] or hero
    local ok, particle_id = safe_call(
        ParticleManager,
        "CreateParticle",
        particle.path,
        resolve_attach_type(particle.attach_type),
        owner
    )
    if not ok or particle_id == nil then
        logger.warn(
            "HeroCosmetic",
            "failed to create particle " .. tostring(particle.id)
                .. ": " .. tostring(particle.path)
        )
        return nil
    end
    return particle_id
end

function M.precache(context)
    for _, definition in pairs(config) do
        for index, entry in ipairs(definition.wearables or {}) do
            local _, model_path = normalize_wearable(entry, index)
            local ok, error_message = pcall(
                PrecacheResource,
                "model",
                model_path,
                context
            )
            if not ok then
                logger.warn(
                    "HeroCosmetic",
                    "precache failed: "
                    .. tostring(model_path)
                    .. " / "
                    .. tostring(error_message)
                )
            end
        end
        for _, particle in ipairs(definition.particles or {}) do
            local ok, error_message = pcall(
                PrecacheResource,
                "particle",
                particle.path,
                context
            )
            if not ok then
                logger.warn(
                    "HeroCosmetic",
                    "particle precache failed: " .. tostring(particle.path)
                        .. " / " .. tostring(error_message)
                )
            end
        end
    end
end

function M.apply(hero, hero_id)
    if not valid_entity(hero) then
        return false
    end

    local definition = config[hero_id]
    if not definition then
        return false
    end

    local hero_entindex = hero:entindex()
    clear_cosmetics(hero_entindex)

    if definition.hide_default_wearables then
        hide_default_wearables(hero)
    else
        show_default_wearables(hero)
    end

    if definition.material_group then
        safe_call(
            hero,
            "SetMaterialGroup",
            definition.material_group
        )
    end

    local spawned = {}
    local components = {}
    for index, entry in ipairs(definition.wearables or {}) do
        local component_id, model_path = normalize_wearable(entry, index)
        local wearable = spawn_wearable(hero, component_id, model_path)
        if wearable then
            table.insert(spawned, wearable)
            components[component_id] = wearable
        end
    end

    local particles = {}
    for _, particle in ipairs(definition.particles or {}) do
        local particle_id = spawn_particle(hero, particle, components)
        if particle_id ~= nil then
            table.insert(particles, particle_id)
        end
    end

    cosmetics_by_hero[hero_entindex] = {
        wearables = spawned,
        particles = particles,
        cosmetic_id = hero_id,
    }
    logger.info(
        "HeroCosmetic",
        hero_id
        .. " applied wearables="
        .. tostring(#spawned)
        .. " particles="
        .. tostring(#particles)
    )
    return true
end

function M.clear(hero)
    if not valid_entity(hero) then
        return
    end
    clear_cosmetics(hero:entindex())
end

return M
