local visual_config = require("config/monster_visual_config")

local M = {}
local state_by_unit = {}
local MAX_PARTICLES_PER_UNIT = 2
local resource_states = {}

local function mark_resource_ready(key)
    return function() resource_states[key] = "ready" end
end

local function valid(entity)
    return entity and (type(entity.IsNull) ~= "function" or not entity:IsNull())
end

local function safe_call(target, method_name, ...)
    local method = target and target[method_name]
    if type(method) ~= "function" then return false end
    return pcall(method, target, ...)
end

local function remove_entity(entity)
    if not valid(entity) then return end
    if type(UTIL_Remove) == "function" then
        pcall(UTIL_Remove, entity)
    else
        safe_call(entity, "RemoveSelf")
    end
end

local function clear_state(entindex)
    local visual_state = state_by_unit[entindex]
    if not visual_state then return end
    for _, particle in ipairs(visual_state.particles or {}) do
        pcall(function()
            ParticleManager:DestroyParticle(particle, true)
            ParticleManager:ReleaseParticleIndex(particle)
        end)
    end
    for _, attachment in ipairs(visual_state.attachments or {}) do
        remove_entity(attachment)
    end
    state_by_unit[entindex] = nil
end

function M.cleanup(unit_or_entindex)
    local entindex = tonumber(unit_or_entindex)
    if not entindex and valid(unit_or_entindex)
        and type(unit_or_entindex.entindex) == "function" then
        entindex = unit_or_entindex:entindex()
    end
    if entindex then clear_state(entindex) end
end

local function spawn_component(unit, component)
    if type(SpawnEntityFromTableSynchronous) ~= "function" then return nil end
    local ok, attachment = pcall(
        SpawnEntityFromTableSynchronous,
        "prop_dynamic",
        {
            model = component.model_path,
            DefaultAnim = "idle",
            solid = "0",
            disableshadows = "0",
            spawnflags = "256",
        }
    )
    if not ok or not valid(attachment) then return nil end
    safe_call(attachment, "SetOwner", unit)
    safe_call(attachment, "SetParent", unit, "")
    safe_call(attachment, "FollowEntity", unit, true)
    if type(EF_BONEMERGE) == "number" then
        safe_call(attachment, "AddEffects", EF_BONEMERGE)
    end
    return attachment
end

local function create_effect(unit, effect)
    if not ParticleManager or type(ParticleManager.CreateParticle) ~= "function" then
        return nil
    end
    local attach = PATTACH_ABSORIGIN_FOLLOW or PATTACH_ABSORIGIN or 0
    local ok, particle = pcall(
        ParticleManager.CreateParticle,
        ParticleManager,
        effect.particle_path,
        attach,
        unit
    )
    if ok then return particle end
    return nil
end

function M.apply(unit, resolved)
    if not valid(unit) or type(unit.entindex) ~= "function" then
        return false, "invalid_unit"
    end
    if not resolved or tostring(resolved.model_path or "") == "" then
        return false, "visual_missing"
    end

    local entindex = unit:entindex()
    clear_state(entindex)
    local model_ok = safe_call(unit, "SetModel", resolved.model_path)
    local original_ok = safe_call(unit, "SetOriginalModel", resolved.model_path)
    if not model_ok and not original_ok then return false, "model_apply_failed" end
    safe_call(unit, "SetModelScale", tonumber(resolved.model_scale) or 1)

    local visual_state = { attachments = {}, particles = {} }
    for _, component in ipairs(resolved.components or {}) do
        if component.enabled ~= false and tostring(component.model_path or "") ~= "" then
            local attachment = spawn_component(unit, component)
            if attachment then
                visual_state.attachments[#visual_state.attachments + 1] = attachment
            end
        end
    end
    for _, effect in ipairs(resolved.effects or {}) do
        local per_effect_limit = math.max(0, math.floor(tonumber(effect.max_per_unit) or 1))
        local remaining = MAX_PARTICLES_PER_UNIT - #visual_state.particles
        local create_count = math.min(per_effect_limit, remaining)
        for _ = 1, create_count do
            local particle = create_effect(unit, effect)
            if particle == nil then break end
            visual_state.particles[#visual_state.particles + 1] = particle
        end
        if #visual_state.particles >= MAX_PARTICLES_PER_UNIT then break end
    end
    state_by_unit[entindex] = visual_state
    unit.survival_monster_visual_asset_id = resolved.visual_asset_id
    unit.survival_monster_visual_role = resolved.visual_role
    return true, resolved.visual_asset_id
end

function M.resolve_and_apply(unit, wave_number, member_role, normal_index)
    local resolved, error_code = visual_config.resolve(
        wave_number,
        member_role,
        normal_index
    )
    if not resolved then return false, error_code end
    return M.apply(unit, resolved)
end

function M.precache_wave(context, wave_number)
    if type(PrecacheResource) ~= "function" then return 0 end
    local count = 0
    for _, resource in ipairs(visual_config.resources_for_wave(wave_number)) do
        PrecacheResource(resource.resource_type, resource.path, context)
        resource_states[resource.resource_type .. ":" .. resource.path] = "ready"
        count = count + 1
    end
    return count
end

function M.queue_wave(wave_number)
    local loading = 0
    local failed = 0
    for _, resource in ipairs(visual_config.resources_for_wave(wave_number)) do
        local key = resource.resource_type .. ":" .. resource.path
        local status = resource_states[key]
        if status == "loading" then
            loading = loading + 1
        elseif status ~= "ready" then
            local async_unit_name = tostring(resource.async_unit_name or "")
            if resource.resource_type ~= "model" or async_unit_name == ""
                or type(PrecacheUnitByNameAsync) ~= "function" then
                resource_states[key] = "failed"
                failed = failed + 1
            else
                resource_states[key] = "loading"
                local ok = pcall(
                    PrecacheUnitByNameAsync,
                    async_unit_name,
                    mark_resource_ready(key),
                    -1
                )
                if ok then
                    loading = loading + 1
                else
                    resource_states[key] = "failed"
                    failed = failed + 1
                end
            end
        end
    end
    if failed > 0 then return false, "runtime_preload_failed" end
    if loading > 0 then return true, "loading" end
    return true, "ready"
end

function M.precache_range(context, first_wave, last_wave)
    local count = 0
    for wave_number = tonumber(first_wave) or 1, tonumber(last_wave) or 0 do
        count = count + M.precache_wave(context, wave_number)
    end
    return count
end

function M._state_for_test(entindex)
    return state_by_unit[tonumber(entindex)]
end

return M