local config = require("config/hero_cosmetics_config")
local asset_catalog = require("config/asset_catalog")
local scheduler = require("core/scheduler")
local logger = require("core/logger")

local M = {}

local cosmetics_by_hero = {}
local generation_by_hero = {}
local SPAWN_PARTICLE_LIFETIME_SECONDS = 1.5

local function definition_for(hero_id)
    local asset = asset_catalog.resolve_bundle(
        "hero_permanent_" .. tostring(hero_id or "")
    )
    if not asset then return config[hero_id] end
    local wearables = {}
    for _, component in ipairs(asset.components or {}) do
        wearables[#wearables + 1] = {
            id = component.component_id,
            model = component.model_path,
            skin = component.model_skin,
            material_group = component.material_group,
        }
    end
    local particles = {}
    local spawn_particles = {}
    for _, effect in ipairs(asset.effects or {}) do
        local target = effect.effect_role == "spawn"
            and spawn_particles or particles
        if effect.effect_role == "ambient" or effect.effect_role == "spawn" then
            target[#target + 1] = {
                id = effect.effect_id,
                path = effect.particle_path,
                owner = effect.owner_component_id,
                attach_type = effect.attach_type,
            }
        end
    end
    local local_definition = config[hero_id] or {}
    return {
        body_model = local_definition.body_model
            or (local_definition.use_asset_body_model and asset.primary_model),
        body_skin = local_definition.body_skin,
        material_group = asset.material_group,
        activity_modifiers = asset.activity_modifiers or {},
        hide_default_wearables = local_definition.hide_default_wearables
            ~= false and #wearables > 0,
        wearables = wearables,
        particles = particles,
        spawn_particles = spawn_particles,
    }
end

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

local function clear_pending_cosmetics(wearables, particles, spawn_particles)
    for _, particle_id in ipairs(particles or {}) do
        destroy_particle(particle_id)
    end
    for _, particle_id in ipairs(spawn_particles or {}) do
        destroy_particle(particle_id)
    end
    for _, wearable in ipairs(wearables or {}) do
        remove_entity(wearable)
    end
end

local function clear_cosmetics(hero_entindex)
    local state = cosmetics_by_hero[hero_entindex]
    if not state then
        return
    end
    for _, particle_id in ipairs(state.particles or {}) do
        destroy_particle(particle_id)
    end
    for _, task_id in ipairs(state.spawn_cleanup_tasks or {}) do
        scheduler.cancel(task_id)
    end
    for _, particle_id in ipairs(state.spawn_particles or {}) do
        destroy_particle(particle_id)
    end
    for _, wearable in ipairs(state.wearables or {}) do
        remove_entity(wearable)
    end
    cosmetics_by_hero[hero_entindex] = nil
end

local function hide_default_wearables(hero, custom_wearables)
    local ok, child = safe_call(hero, "FirstMoveChild")
    if not ok then
        return
    end

    local no_draw = rawget(_G, "EF_NODRAW") or 32

    -- 记录我们自己生成的 wearable
    local custom_indices = {}

    for _, wearable in ipairs(custom_wearables or {}) do
        if valid_entity(wearable) then
            local index_ok, index =
                safe_call(wearable, "entindex")

            if index_ok and index then
                custom_indices[index] = true
            end
        end
    end

    while valid_entity(child) do
        local next_ok, next_child =
            safe_call(child, "NextMovePeer")

        local class_ok, class_name =
            safe_call(child, "GetClassname")

        if class_ok and class_name == "dota_item_wearable" then

            local index_ok, child_index =
                safe_call(child, "entindex")

            -- 只隐藏 Valve 原生 wearable
            -- 不隐藏我们刚刚生成的 custom wearable
            if not (
                index_ok
                and child_index
                and custom_indices[child_index]
            ) then
                safe_call(child, "AddEffects", no_draw)
            end
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
        return "wearable_" .. tostring(index), entry, {}
    end
    if type(entry) == "table" then
        return entry.id or "wearable_" .. tostring(index), entry.model, entry
    end
    return "wearable_" .. tostring(index), nil, {}
end

local function spawn_wearable(hero, component_id, model_path, appearance)
    if not model_path or model_path == "" then
        logger.warn("HeroCosmetic", "missing model for " .. tostring(component_id))
        return nil
    end
    local ok, wearable = pcall(
        SpawnEntityFromTableSynchronous,
        "dota_item_wearable",
        {
            model = model_path,
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

    appearance = appearance or {}
    if appearance.skin ~= nil then
        safe_call(wearable, "SetSkin", tonumber(appearance.skin) or 0)
    end
    if appearance.material_group then
        safe_call(wearable, "SetMaterialGroup", appearance.material_group)
    end
    local owner_call_ok, owner_result = safe_call(wearable, "SetOwner", hero)
    local follow_call_ok, follow_result = safe_call(
        wearable,
        "FollowEntity",
        hero,
        true
    )
    local index_ok, entity_index = safe_call(wearable, "entindex")
    local class_ok, class_name = safe_call(wearable, "GetClassname")
    local effects_ok, render_effects = safe_call(wearable, "GetEffects")
    local null_ok, is_null = safe_call(wearable, "IsNull")
    logger.info(
        "HeroCosmetic",
        "wearable component=" .. tostring(component_id)
            .. " model=" .. tostring(model_path)
            .. " entity=" .. tostring(index_ok and entity_index or "unknown")
            .. " class=" .. tostring(class_ok and class_name or "unknown")
            .. " null=" .. tostring(null_ok and is_null or false)
            .. " effects=" .. tostring(effects_ok and render_effects or "unknown")
            .. " owner_call=" .. tostring(owner_call_ok)
            .. " owner_result=" .. tostring(owner_result)
            .. " follow_call=" .. tostring(follow_call_ok)
            .. " follow_result=" .. tostring(follow_result)
    )
    if not owner_call_ok or owner_result == false
        or not follow_call_ok or follow_result == false then
        logger.warn(
            "HeroCosmetic",
            "failed to attach wearable " .. tostring(component_id)
                .. ": " .. tostring(model_path)
        )
        remove_entity(wearable)
        return nil
    end
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
    local definitions = { config.builder_undying }
    for _, definition in ipairs(definitions) do
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

    local definition = definition_for(hero_id)
    if not definition then
        return false
    end
    local hero_entindex = hero:entindex()
    local generation = (generation_by_hero[hero_entindex] or 0) + 1
    generation_by_hero[hero_entindex] = generation
    local spawned = {}
    local components = {}
    for index, entry in ipairs(definition.wearables or {}) do
        local component_id, model_path, appearance =
            normalize_wearable(entry, index)
        local wearable = spawn_wearable(
            hero,
            component_id,
            model_path,
            appearance
        )
        if wearable then
            table.insert(spawned, wearable)
            components[component_id] = wearable
        else
            for _, pending in ipairs(spawned) do remove_entity(pending) end
            logger.warn(
                "HeroCosmetic",
                tostring(hero_id) .. " transaction aborted component="
                    .. tostring(component_id) .. " generation=" .. tostring(generation)
            )
            return false
        end
    end

    if generation_by_hero[hero_entindex] ~= generation then
        for _, pending in ipairs(spawned) do remove_entity(pending) end
        return false
    end

    clear_cosmetics(hero_entindex)
    if definition.hide_default_wearables then
        hide_default_wearables(hero, spawned)
    else
        show_default_wearables(hero)
    end

    if definition.body_model and definition.body_model ~= "" then
        local original_ok, original_result = safe_call(
            hero, "SetOriginalModel", definition.body_model
        )
        local model_ok, model_result = safe_call(
            hero, "SetModel", definition.body_model
        )
        if not original_ok or original_result == false
            or not model_ok or model_result == false then
            clear_pending_cosmetics(spawned, {}, {})
            logger.warn("HeroCosmetic", tostring(hero_id)
                .. " transaction aborted body_model="
                .. tostring(definition.body_model))
            return false
        end
    end
    if definition.body_skin ~= nil then
        safe_call(hero, "SetSkin", tonumber(definition.body_skin) or 0)
    end
    if definition.material_group then
        safe_call(hero, "SetMaterialGroup", definition.material_group)
    end
    for _, modifier in ipairs(definition.activity_modifiers or {}) do
        safe_call(hero, "AddActivityModifier", modifier.modifier_name)
    end

    local particles = {}
    local spawn_particles = {}
    for _, particle in ipairs(definition.particles or {}) do
        local particle_id = spawn_particle(hero, particle, components)
        if particle_id == nil then
            clear_pending_cosmetics(spawned, particles, spawn_particles)
            logger.warn(
                "HeroCosmetic",
                tostring(hero_id) .. " transaction aborted particle="
                    .. tostring(particle.id) .. " generation=" .. tostring(generation)
            )
            return false
        end
        table.insert(particles, particle_id)
    end
    for _, particle in ipairs(definition.spawn_particles or {}) do
        local particle_id = spawn_particle(hero, particle, components)
        if particle_id == nil then
            clear_pending_cosmetics(spawned, particles, spawn_particles)
            logger.warn(
                "HeroCosmetic",
                tostring(hero_id) .. " transaction aborted spawn_particle="
                    .. tostring(particle.id) .. " generation=" .. tostring(generation)
            )
            return false
        end
        table.insert(spawn_particles, particle_id)
    end

    cosmetics_by_hero[hero_entindex] = {
        wearables = spawned,
        particles = particles,
        spawn_particles = spawn_particles,
        spawn_cleanup_tasks = {},
        cosmetic_id = hero_id,
        generation = generation,
    }
    local state = cosmetics_by_hero[hero_entindex]
    for _, particle_id in ipairs(spawn_particles) do
        local task_id
        task_id = scheduler.after(
            SPAWN_PARTICLE_LIFETIME_SECONDS,
            function()
                if cosmetics_by_hero[hero_entindex] ~= state
                    or generation_by_hero[hero_entindex] ~= generation then
                    return
                end
                for index, active_task_id in ipairs(state.spawn_cleanup_tasks or {}) do
                    if active_task_id == task_id then
                        table.remove(state.spawn_cleanup_tasks, index)
                        break
                    end
                end
                for index, active_id in ipairs(state.spawn_particles or {}) do
                    if active_id == particle_id then
                        table.remove(state.spawn_particles, index)
                        break
                    end
                end
                destroy_particle(particle_id)
            end,
            "hero_cosmetic_spawn_" .. tostring(hero_entindex)
                .. "_" .. tostring(particle_id)
        )
        table.insert(state.spawn_cleanup_tasks, task_id)
    end
    logger.info(
        "HeroCosmetic",
        hero_id
        .. " applied wearables="
        .. tostring(#spawned)
        .. " particles="
        .. tostring(#particles + #spawn_particles)
        .. " ambient=" .. tostring(#(definition.particles or {}))
        .. " spawn=" .. tostring(#spawn_particles)
    )
    return true
end

function M.clear(hero)
    if not valid_entity(hero) then
        return
    end
    local entindex = hero:entindex()
    generation_by_hero[entindex] = (generation_by_hero[entindex] or 0) + 1
    clear_cosmetics(entindex)
end

return M
