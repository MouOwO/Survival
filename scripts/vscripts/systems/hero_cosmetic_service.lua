local ParticleManager = require("systems/combat_effect_visibility").manager()
local config = require("config/hero_cosmetics_config")
local asset_catalog = require("config/asset_catalog")
local scheduler = require("core/scheduler")
local logger = require("core/logger")
local diagnostic_rule = require("config/generated/global_rules").by_id.runtime_detailed_diagnostics
local detailed_diagnostics = diagnostic_rule and diagnostic_rule.enabled ~= false
    and tonumber(diagnostic_rule.value) == 1
local weapon_slot = require("visual/hero_weapon_slot")
local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local cosmetics_by_hero = {}
local mirrors_by_entity = {}
local generation_by_hero = {}
local SPAWN_PARTICLE_LIFETIME_SECONDS = 1.5

local function copy_definition(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy_definition(child) end
    return result
end

local function current_world()
    return GameRules and GameRules.GetGameModeEntity
        and GameRules:GetGameModeEntity() or GameRules or _G
end

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
            entity_class = component.entity_class,
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
                attachment_point = effect.attachment_point,
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

local function clear_mirror_resources(wearables, particles, world)
    -- Destroy/remove callbacks may synchronously start another Tools world.
    -- Its reused particle IDs must never be released or destroyed by this one.
    for _, particle_id in ipairs(particles or {}) do
        if world ~= current_world() then return end
        safe_call(ParticleManager, "DestroyParticle", particle_id, true)
        if world ~= current_world() then return end
        safe_call(ParticleManager, "ReleaseParticleIndex", particle_id)
    end
    for _, wearable in ipairs(wearables or {}) do
        if world ~= current_world() then return end
        remove_entity(wearable)
    end
end

local function retire_cosmetics(state)
    if mirrors_by_entity[state.hero] == state then mirrors_by_entity[state.hero] = nil end
    if state.mirror then
        clear_mirror_resources(state.wearables, state.particles, state.world_token)
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
end

local function clear_cosmetics(hero_entindex)
    local state = cosmetics_by_hero[hero_entindex]
    if not state then return end
    -- Retire ownership before engine cleanup can synchronously re-enter.
    cosmetics_by_hero[hero_entindex] = nil
    retire_cosmetics(state)
end

local function walk_children(hero, visitor)
    local visited = {}
    local function visit(child)
        if not valid_entity(child) then return end
        local index_ok, index = safe_call(child, "entindex")
        local key = index_ok and index or child
        if visited[key] then return end
        visited[key] = true
        visitor(child)
    end

    local ok, child = safe_call(hero, "FirstMoveChild")
    while ok and valid_entity(child) do
        local next_ok, next_child = safe_call(child, "NextMovePeer")
        visit(child)
        child = next_child
        ok = next_ok
    end

    -- Some ReplaceHeroWith paths expose native wearables through GetChildren
    -- but not through the move-peer chain. Keep this as a compatibility
    -- fallback; the entindex guard prevents duplicate processing.
    local children_ok, children = safe_call(hero, "GetChildren")
    if children_ok and type(children) == "table" then
        for _, candidate in pairs(children) do
            visit(candidate)
        end
    end
end

-- ReplaceHeroWith may expose Valve's native wearables as standalone entities
-- owned by the hero instead of move-children.  This is the same ownership
-- sweep used by the building appearance service; keep it local so hero
-- cosmetics do not depend on one particular engine parenting layout.
local function entity_belongs_to(entity, owner)
    local visited = {}
    local function matches(candidate, depth)
        if candidate == owner then return true end
        if candidate == nil or type(candidate) == "number"
            or type(candidate) == "string" then
            return false
        end
        if not valid_entity(candidate) or depth <= 0 then return false end
        local index_ok, index = safe_call(candidate, "entindex")
        local key = index_ok and index or candidate
        if visited[key] then return false end
        visited[key] = true
        for _, method_name in ipairs({
            "GetOwner",
            "GetOwnerEntity",
            "GetParent",
            "GetMoveParent",
        }) do
            local ok, parent = safe_call(candidate, method_name)
            if ok and parent ~= nil and matches(parent, depth - 1) then
                return true
            end
        end
        return candidate.owner == owner
    end

    -- Keep all parent/owner forms in the recursive check: some native
    -- wearables are parented through an intermediate carrier or player owner.
    -- The bounded depth and entindex guard prevent engine-side cycles.
    return matches(entity, 4)
end

local function each_live_entity(class_name, visitor)
    local entities_api = rawget(_G, "Entities")
    if not entities_api then return end
    local seen = {}
    local function visit(entity)
        if not valid_entity(entity) then return end
        local index_ok, index = safe_call(entity, "entindex")
        local key = index_ok and index or entity
        if seen[key] then return end
        seen[key] = true
        visitor(entity)
    end

    if type(entities_api.FindAllByClassname) == "function" then
        local ok, entities = pcall(
            entities_api.FindAllByClassname,
            entities_api,
            class_name
        )
        if ok and type(entities) == "table" then
            for _, entity in ipairs(entities or {}) do visit(entity) end
            return
        end
    end
    if type(entities_api.FindByClassname) == "function" then
        local previous = nil
        for _ = 1, 4096 do
            local ok, entity = pcall(
                entities_api.FindByClassname,
                entities_api,
                previous,
                class_name
            )
            if not ok or not valid_entity(entity) or entity == previous then
                break
            end
            visit(entity)
            previous = entity
        end
    end
end

local function apply_native_wearable_visibility(child, visible)
    if visible then
        safe_call(child, "RemoveNoDraw")
        safe_call(child, "RemoveEffects", rawget(_G, "EF_NODRAW") or 32)
        if type(child.SetRenderAlpha) == "function" then
            safe_call(child, "SetRenderAlpha", 255)
        end
        return
    end
    -- SetRenderAlpha is a reliable fallback for wearables materialized outside
    -- the hero's child chain; AddNoDraw/EF_NODRAW remains the hard hide path.
    if type(child.SetRenderAlpha) == "function" then
        safe_call(child, "SetRenderAlpha", 0)
    end
    safe_call(child, "AddNoDraw")
    safe_call(child, "AddEffects", rawget(_G, "EF_NODRAW") or 32)
end

local function hide_default_wearables(hero, custom_wearables, pass_label)
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

    local child_native_count = 0
    local hidden_count = 0
    local global_native_count = 0
    local owner_match_count = 0
    local unmatched_models = {}
    local hidden_entities = {}
    local function hide_once(entity)
        local index_ok, index = safe_call(entity, "entindex")
        local key = index_ok and index or entity
        if hidden_entities[key] then return end
        hidden_entities[key] = true
        apply_native_wearable_visibility(entity, false)
        hidden_count = hidden_count + 1
    end

    walk_children(hero, function(child)
        local class_ok, class_name =
            safe_call(child, "GetClassname")

        if class_ok and class_name == "dota_item_wearable" then
            child_native_count = child_native_count + 1

            local index_ok, child_index =
                safe_call(child, "entindex")

            -- 只隐藏 Valve 原生 wearable
            -- 不隐藏我们刚刚生成的 custom wearable
            if not (
                index_ok
                and child_index
                and custom_indices[child_index]
            ) then
                hide_once(child)
            end
        end
    end)

    each_live_entity("dota_item_wearable", function(wearable)
        global_native_count = global_native_count + 1
        local index_ok, wearable_index = safe_call(wearable, "entindex")
        if index_ok and wearable_index and custom_indices[wearable_index] then
            return
        end
        if entity_belongs_to(wearable, hero) then
            owner_match_count = owner_match_count + 1
            hide_once(wearable)
        elseif detailed_diagnostics and #unmatched_models < 8 then
            local model_ok, model_path = safe_call(wearable, "GetModelName")
            unmatched_models[#unmatched_models + 1] = model_ok
                and tostring(model_path or "<empty>") or "<unknown>"
        end
    end)

    if detailed_diagnostics then
        logger.info(
            "HeroCosmetic",
            "native_hide hero=" .. tostring(hero:entindex())
                .. " pass=" .. tostring(pass_label or "immediate")
                .. " child=" .. tostring(child_native_count)
                .. " global=" .. tostring(global_native_count)
                .. " owner_match=" .. tostring(owner_match_count)
                .. " hidden=" .. tostring(hidden_count)
                .. " unmatched_models=" .. table.concat(unmatched_models, "|")
        )
    end
end

local function show_default_wearables(hero)
    walk_children(hero, function(child)
        local class_ok, class_name = safe_call(child, "GetClassname")
        if class_ok and class_name == "dota_item_wearable" then
            apply_native_wearable_visibility(child, true)
        end
    end)
    each_live_entity("dota_item_wearable", function(wearable)
        if entity_belongs_to(wearable, hero) then
            apply_native_wearable_visibility(wearable, true)
        end
    end)
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
        tostring(appearance.entity_class or "dota_item_wearable"),
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
    -- NPCs do not consistently expose skin/material getters. Keep the exact
    -- successfully applied declaration on our own component for visual copies.
    wearable.survival_cosmetic_appearance = copy_definition(appearance)
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
    if particle.attachment_point and particle.attachment_point ~= "" then
        local origin_ok, origin = safe_call(owner, "GetAbsOrigin")
        if origin_ok and origin ~= nil then
            local attachment_ok, attachment = safe_call(owner, "ScriptLookupAttachment", particle.attachment_point)
            if not attachment_ok or (tonumber(attachment) or 0) <= 0 then
                safe_call(ParticleManager, "SetParticleControl", particle_id, 0, origin)
                return particle_id
            end
            safe_call(
                ParticleManager,
                "SetParticleControlEnt",
                particle_id,
                0,
                owner,
                rawget(_G, "PATTACH_POINT_FOLLOW") or 5,
                particle.attachment_point,
                origin,
                true
            )
        end
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
    local world = current_world()
    local previous = cosmetics_by_hero[hero_entindex]
    if previous and previous.world_token ~= world then
        -- A fresh Tools world can reuse integer entity/particle IDs.
        cosmetics_by_hero[hero_entindex] = nil
    end
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
    if not definition.hide_default_wearables then
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
    -- SetModel/SetOriginalModel can recreate or re-expose Valve's native
    -- wearables. Hide them only after the final body model is in place; custom
    -- prop_dynamic components remain visible because the helper filters by
    -- classname and custom entity index.
    if definition.hide_default_wearables then
        hide_default_wearables(hero, spawned, "immediate")
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
        hero = hero,
        hero_entindex = hero_entindex,
        world_token = world,
        components = components,
        particle_definitions = definition.particles or {},
        wearables = spawned,
        particles = particles,
        spawn_particles = spawn_particles,
        spawn_cleanup_tasks = {},
        cosmetic_id = hero_id,
        appearance_definition = copy_definition(definition),
        generation = generation,
    }
    local state = cosmetics_by_hero[hero_entindex]
    if definition.hide_default_wearables and GameRules then
        -- ReplaceHeroWith can materialize native wearables over several frames.
        -- Use a few short, generation-guarded passes instead of changing the
        -- hero model architecture or hiding the playable hero itself.
        for retry, delay in ipairs({ 0.10, 0.35, 0.80 }) do
            scheduler.after(
                delay,
                function()
                    if cosmetics_by_hero[hero_entindex] ~= state
                        or generation_by_hero[hero_entindex] ~= generation
                        or not valid_entity(hero) then
                        return
                    end
                    hide_default_wearables(hero, state.wearables,
                        "delayed_" .. tostring(retry))
                end,
                "hero_cosmetic_hide_" .. tostring(hero_entindex)
                    .. "_" .. tostring(retry)
            )
        end
    end
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

local function weapon_context(hero, token, allow_removed)
    if not hero or (not allow_removed and not valid_entity(hero)) then return nil end
    local index = token and token.hero_entindex
    if not index then
        local ok, value = safe_call(hero, "entindex")
        if not ok then return nil end
        index = value
    end
    local state = cosmetics_by_hero[index]
    if not state or state.hero ~= hero or state.world_token ~= current_world() then
        return nil
    end
    if token and token ~= state then return nil end
    return state
end

local function spawn_weapon_wearable(hero, component_id, model_path, appearance)
    local wearable = spawn_wearable(hero, component_id, model_path,
        { entity_class = appearance.entity_class })
    if not wearable then return nil end
    if appearance.skin ~= nil then
        local ok, result = safe_call(wearable, "SetSkin", tonumber(appearance.skin) or 0)
        if not ok or result == false then remove_entity(wearable); return nil end
    end
    if appearance.material_group and appearance.material_group ~= "" then
        local ok, result = safe_call(wearable, "SetMaterialGroup", appearance.material_group)
        if not ok or result == false then remove_entity(wearable); return nil end
    end
    wearable.survival_cosmetic_appearance = copy_definition(appearance)
    return wearable
end

local function weapon_engine(hero, state)
    local function is_current()
        local same_world = state.world_token == current_world()
        return same_world and cosmetics_by_hero[state.hero_entindex] == state
            and generation_by_hero[state.hero_entindex] == state.generation, same_world
    end
    return {
        spawn_wearable = spawn_weapon_wearable,
        spawn_particle = function(unit, particle, components)
            return weapon_slot.spawn_particle(unit, particle, components, is_current)
        end,
        destroy_particle = function(particle_id)
            local _, same_world = is_current()
            if not same_world then return true end
            local destroyed, destroy_result = safe_call(ParticleManager,
                "DestroyParticle", particle_id, true)
            -- Destroy callbacks can enter a fresh Tools world which has
            -- already reused this integer ID; never release its new owner.
            local _, still_same_world = is_current()
            local released, release_result = true, nil
            if still_same_world then
                released, release_result = safe_call(ParticleManager,
                    "ReleaseParticleIndex", particle_id)
            end
            return destroyed and destroy_result ~= false
                and released and release_result ~= false
        end,
        remove_entity = remove_entity,
        is_current = is_current,
    }
end

function M.weapon_snapshot(hero, component_id)
    local state = weapon_context(hero)
    if not state then return nil end
    return weapon_slot.snapshot(state, component_id)
end

local function publish_weapon_change(hero, state, reason)
    if weapon_context(hero) ~= state then return end
    local player_id = tonumber(hero.survival_player_id)
    if player_id == nil then
        local ok, value = safe_call(hero, "GetPlayerOwnerID")
        if ok then player_id = tonumber(value) end
    end
    -- Notify mirrors only after the weapon transaction has committed and
    -- unlocked. Equipment-event subscribers can otherwise observe the old
    -- particle declarations, depending on their dispatch order.
    event_bus.emit(events.HERO_COSMETICS_CHANGED, {
        unit = hero, player_id = player_id, reason = "weapon_" .. reason,
    })
end

function M.apply_weapon(hero, appearance)
    local state = weapon_context(hero)
    if not state or state.cosmetic_id ~= appearance.hero_id then
        return false, "waiting_for_hero_cosmetics"
    end
    local applied, reason, details = weapon_slot.apply(
        hero, state, appearance, weapon_engine(hero, state)
    )
    if applied and reason == "applied" then publish_weapon_change(hero, state, reason) end
    return applied, reason, details
end

function M.clear_weapon(hero, component_id, token)
    local state = weapon_context(hero, token, true)
    if not state then return false, "hero_cosmetics_unavailable" end
    local cleared, reason, details = weapon_slot.clear(
        hero, state, component_id, weapon_engine(hero, state)
    )
    if cleared and reason == "cleared" then publish_weapon_change(hero, state, reason) end
    return cleared, reason, details
end

local function optional_value(entity, method)
    local ok, value = safe_call(entity, method)
    if ok then return value end
    return nil
end

local function current_appearance(entity, declared)
    local appearance = copy_definition(declared or {})
    local model = optional_value(entity, "GetModelName")
    if type(model) == "string" and model ~= "" then appearance.model = model end
    local scale = tonumber(optional_value(entity, "GetModelScale"))
    if scale and scale > 0 then appearance.model_scale = scale end
    local skin = tonumber(optional_value(entity, "GetSkin"))
    if skin ~= nil then appearance.skin = skin end
    local material = optional_value(entity, "GetMaterialGroup")
    if type(material) == "string" and material ~= "" then appearance.material_group = material end
    local material_hash = optional_value(entity, "GetMaterialGroupHash")
    if material_hash ~= nil then appearance.material_group_hash = material_hash end
    return appearance
end

local function appearance_key(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys, result = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local encoded = appearance_key(value[key])
        result[#result + 1] = tostring(key) .. "=" .. #encoded .. ":" .. encoded
    end
    return "{" .. table.concat(result, ";") .. "}"
end

local function set_appearance(entity, appearance, body)
    local function set(method, value)
        if value == nil then return true end
        local ok, result = safe_call(entity, method, value)
        return ok and result ~= false
    end
    if body and (not set("SetOriginalModel", appearance.model)
        or not set("SetModel", appearance.model)) then return false end
    if not set("SetModelScale", appearance.model_scale)
        or not set("SetSkin", appearance.skin)
        or not set("SetMaterialGroup", appearance.material_group) then return false end
    if appearance.material_group_hash ~= nil and type(entity.SetMaterialGroupHash) == "function"
        and not set("SetMaterialGroupHash", appearance.material_group_hash) then return false end
    return true
end

-- Copies committed visual declarations into separately owned entities/particles.
-- It never enters the player equipment service or broadcasts a hero event.
function M.sync_appearance(target, source)
    if target == source or not valid_entity(target) or not valid_entity(source) then return false end
    local source_state = weapon_context(source)
    if source_state and source_state.weapon_slot_transaction then return false end
    local hero_id = source_state and source_state.cosmetic_id or source.survival_hero_id
    if not hero_id then return false end
    local definition = source_state and source_state.appearance_definition or definition_for(hero_id)
    if not definition then return false end
    local body = current_appearance(source, {
        model = definition.body_model, model_scale = definition.model_scale or 1,
        skin = definition.body_skin or 0, material_group = definition.material_group,
    })
    if type(body.model) ~= "string" or body.model == "" then return false end
    local declarations = {}
    if source_state then
        for id, component in pairs(source_state.components or {}) do
            if not valid_entity(component) then return false end
            local appearance = current_appearance(component, component.survival_cosmetic_appearance)
            appearance.id, appearance.model = id, appearance.model
            if not appearance.model or appearance.model == "" then return false end
            declarations[#declarations + 1] = appearance
        end
    else
        for index, entry in ipairs(definition.wearables or {}) do
            local id, model, appearance = normalize_wearable(entry, index)
            appearance = copy_definition(appearance)
            appearance.id, appearance.model = id, model
            declarations[#declarations + 1] = appearance
        end
    end
    table.sort(declarations, function(a, b) return tostring(a.id) < tostring(b.id) end)
    local particles = copy_definition(source_state and source_state.particle_definitions or definition.particles or {})
    local signature = appearance_key({body = body, wearables = declarations, particles = particles,
        activities = definition.activity_modifiers or {}})
    local index, world = target:entindex(), current_world()
    local previous = weapon_context(target)
    local cached = previous and previous.mirror
    if cached and cached.source == source and cached.source_state == source_state
        and cached.source_generation == (source_state and source_state.generation)
        and cached.components == previous.components and cached.particles == previous.particle_definitions
        and cached.signature == signature then
        local complete = true
        for _, wearable in ipairs(previous.wearables or {}) do
            if not valid_entity(wearable) then complete = false; break end
        end
        if complete then return true end
    end
    local generation = (generation_by_hero[index] or 0) + 1
    generation_by_hero[index] = generation
    local spawned, spawned_particles, components = {}, {}, {}
    local old_body = current_appearance(target, previous and previous.mirror_body)
    local body_changed = false
    local source_components = source_state and source_state.components
    local source_particles = source_state and source_state.particle_definitions
    local function active()
        local same_world = world == current_world()
        return same_world and valid_entity(target) and valid_entity(source)
            and generation_by_hero[index] == generation
            and weapon_context(source) == source_state
            and (not source_state or (not source_state.weapon_slot_transaction
                and source_state.components == source_components
                and source_state.particle_definitions == source_particles)), same_world
    end
    local function abort()
        local _, same_world = active()
        if same_world then clear_mirror_resources(spawned, spawned_particles, world) end
        if world == current_world() and generation_by_hero[index] == generation
            and valid_entity(target) and body_changed and old_body.model then
            set_appearance(target, old_body, true)
        end
        return false
    end
    for _, appearance in ipairs(declarations) do
        if not active() then return abort() end
        local wearable = spawn_wearable(target, appearance.id, appearance.model, appearance)
        if wearable then spawned[#spawned + 1] = wearable end
        if not wearable or not active() or not set_appearance(wearable, appearance, false) then return abort() end
        components[appearance.id] = wearable
    end
    body_changed = true
    if not active() or not set_appearance(target, body, true) then return abort() end
    -- The native CP helper also recreates hidden offset carriers. They belong
    -- only to the target and are retired with its other visual entities.
    local particle_components = {}
    for id, component in pairs(components) do particle_components[id] = component end
    particle_components.__mirror_body = target
    for _, particle in ipairs(particles) do
        local binding = copy_definition(particle)
        if binding.owner == nil or binding.owner == "" then binding.owner = "__mirror_body" end
        local particle_id, anchors = weapon_slot.spawn_particle(target, binding, particle_components, active)
        if particle_id == nil then return abort() end
        spawned_particles[#spawned_particles + 1] = particle_id
        for _, anchor in ipairs(anchors or {}) do spawned[#spawned + 1] = anchor end
        if not active() then return abort() end
    end
    if not active() then return abort() end
    for _, modifier in ipairs(definition.activity_modifiers or {}) do
        safe_call(target, "AddActivityModifier", modifier.modifier_name)
    end
    -- Hide only direct target wearables, never a global owner-chain sweep.
    local owned = {}
    for _, wearable in ipairs(spawned) do owned[wearable] = true end
    walk_children(target, function(child)
        if not owned[child] and optional_value(child, "GetClassname") == "dota_item_wearable" then
            apply_native_wearable_visibility(child, false)
        end
    end)
    local state = {hero = target, hero_entindex = index, world_token = world,
        components = components, wearables = spawned, particles = spawned_particles,
        particle_definitions = particles, spawn_particles = {}, spawn_cleanup_tasks = {},
        cosmetic_id = hero_id, appearance_definition = copy_definition(definition), generation = generation,
        mirror_body = body, mirror = {source = source, source_state = source_state,
            source_generation = source_state and source_state.generation, signature = signature,
            components = components, particles = particles}}
    cosmetics_by_hero[index] = state
    mirrors_by_entity[target] = state
    if previous then retire_cosmetics(previous) end
    return cosmetics_by_hero[index] == state and active() == true
end

function M.clear(hero)
    if not hero then return end
    -- Removed NPC handles can no longer answer entindex(). Keep mirror ownership
    -- by the exact handle, independent of a later unit reusing its integer ID.
    local state = mirrors_by_entity[hero]
    if not state then
        for _, candidate in pairs(cosmetics_by_hero) do
            if candidate.hero == hero then state = candidate; break end
        end
    end
    if state then
        local index = state.hero_entindex
        if cosmetics_by_hero[index] == state then
            cosmetics_by_hero[index] = nil
            if state.world_token == current_world() then
                generation_by_hero[index] = (generation_by_hero[index] or 0) + 1
            end
        end
        if state.world_token == current_world() then retire_cosmetics(state)
        elseif mirrors_by_entity[hero] == state then mirrors_by_entity[hero] = nil end
    elseif valid_entity(hero) then
        local index = hero:entindex()
        -- A reentrant clear can cancel a first mirror build before its commit.
        local current = cosmetics_by_hero[index]
        if not current or current.hero == hero then
            generation_by_hero[index] = (generation_by_hero[index] or 0) + 1
        end
    end
end

return M
