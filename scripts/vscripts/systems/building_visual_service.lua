local catalog = require("config/asset_catalog")
local preload = require("systems/asset_preload_service")
local logger = require("core/logger")
local appearance = require("visual/model_appearance_service")
-- Only used to clean up carriers left by an older script version.
local native_carrier = require("visual/native_wearable_carrier_service")

local M = {}
local activity_modifiers_by_unit = {}
local particles_by_unit = {}
local bodygroups_by_unit = {}
local NATIVE_TOWER_MODELS = {
    ["models/props_structures/tower_dragon_black.vmdl"] = true,
    ["models/props_structures/rock_golem/tower_radiant_rock_golem.vmdl"] = true,
    ["models/props_structures/tower_dragon_white.vmdl"] = true,
    ["models/props_structures/tower_upgrade/tower_upgrade.vmdl"] = true,
    ["models/props_structures/tower_good2.vmdl"] = true,
    ["models/props_structures/tower_bad.vmdl"] = true,
    ["models/props_structures/rock_golem/tower_dire_rock_golem.vmdl"] = true,
}

local function valid_entity(entity)
    if not entity then return false end
    if type(entity.IsNull) == "function" and entity:IsNull() then return false end
    if type(IsValidEntity) == "function" then
        local ok, is_valid = pcall(IsValidEntity, entity)
        if ok and not is_valid then return false end
    end
    return true
end

local function safe_call(target, method_name, ...)
    local method = target and target[method_name]
    if type(method) ~= "function" then return false, nil end
    return pcall(method, target, ...)
end

local function clear_activity_modifiers(unit)
    local entindex = unit:entindex()
    if activity_modifiers_by_unit[entindex] then
        safe_call(unit, "ClearActivityModifiers")
    end
    activity_modifiers_by_unit[entindex] = nil
end

local function apply_activity_modifiers(unit, asset)
    if type(unit.AddActivityModifier) ~= "function"
        or type(unit.ClearActivityModifiers) ~= "function" then
        activity_modifiers_by_unit[unit:entindex()] = nil
        return
    end

    local desired = {}
    for _, entry in ipairs(asset and asset.activity_modifiers or {}) do
        local modifier_name = tostring(entry.modifier_name or "")
        if modifier_name ~= "" then desired[#desired + 1] = modifier_name end
    end

    local entindex = unit:entindex()
    local applied = activity_modifiers_by_unit[entindex]
    local unchanged = applied ~= nil and #applied == #desired
    if unchanged then
        for index, modifier_name in ipairs(desired) do
            if applied[index] ~= modifier_name then
                unchanged = false
                break
            end
        end
    end
    if unchanged then return end

    clear_activity_modifiers(unit)
    applied = {}
    for _, modifier_name in ipairs(desired) do
        local ok = safe_call(unit, "AddActivityModifier", modifier_name)
        if ok then applied[#applied + 1] = modifier_name end
    end
    if #applied > 0 then activity_modifiers_by_unit[entindex] = applied end
end

local function clear_particles(unit, replacing_owner)
    local state = particles_by_unit[unit:entindex()]
    if state and state.owner ~= unit and not replacing_owner then return end
    for _, particle in ipairs(state and state.particles or {}) do
        pcall(function()
            ParticleManager:DestroyParticle(particle, false)
            ParticleManager:ReleaseParticleIndex(particle)
        end)
    end
    particles_by_unit[unit:entindex()] = nil
end

local function clear_bodygroups(unit)
    local entindex = unit:entindex()
    for bodygroup_name in pairs(bodygroups_by_unit[entindex] or {}) do
        safe_call(unit, "SetBodygroupByName", bodygroup_name, 0)
    end
    bodygroups_by_unit[entindex] = nil
end

local function apply_bodygroups(unit, asset)
    clear_bodygroups(unit)
    local applied = {}
    for _, bodygroup in ipairs(asset and asset.bodygroups or {}) do
        local bodygroup_name = tostring(bodygroup.bodygroup_name or "")
        local value = tonumber(bodygroup.value)
        if bodygroup_name ~= "" and value then
            local ok = safe_call(
                unit,
                "SetBodygroupByName",
                bodygroup_name,
                value
            )
            if ok then applied[bodygroup_name] = true end
        end
    end
    if next(applied) then bodygroups_by_unit[unit:entindex()] = applied end
end

local function reset_main_animation(unit, asset)
    -- SetModel can leave an existing building entity on the previous model's
    -- sequence/animation graph. Refresh that state before selecting the new
    -- bundle's configured default sequence. Most assets still fall back to
    -- idle when they do not specify one; native tower models explicitly skip
    -- that fallback so the engine can select their own activity graph.
    safe_call(unit, "ResetSequenceInfo")
    local sequence = "idle"
    if asset and asset.default_sequence ~= nil then
        sequence = tostring(asset.default_sequence or "")
    end
    if asset and NATIVE_TOWER_MODELS[tostring(asset.primary_model or "")] then
        sequence = ""
    end
    if sequence ~= "" then safe_call(unit, "ResetSequence", sequence) end
    safe_call(unit, "SetPlaybackRate", 1)
end

local function normalize_particle(asset, entry, index)
    if type(entry) == "string" then
        local owner_id = asset and asset.environment_particle_owners
            and asset.environment_particle_owners[index]
        return { path = entry, owner = owner_id }
    end
    if type(entry) == "table" then
        return entry
    end
    return nil
end

local function configure_particle(particle, owner, descriptor)
    if descriptor.attachment_point == ""
        and descriptor.control_profile ~= "io_base_ambient" then return end
    local origin = owner:GetAbsOrigin()
    local point_follow = rawget(_G, "PATTACH_POINT_FOLLOW") or 5
    if descriptor.attachment_point ~= "" then
        ParticleManager:SetParticleControlEnt(particle, 0, owner,
            point_follow, descriptor.attachment_point, origin, true)
    end
    if descriptor.control_profile == "io_base_ambient" then
        -- Valve's default item 536 creates this body effect independently of
        -- wisp.vmdl. Use the native particle's preview control points: CP11=1
        -- suppresses the red low-health child instead of showing it at CP11=0.
        ParticleManager:SetParticleControlEnt(particle, 1, owner,
            rawget(_G, "PATTACH_ABSORIGIN_FOLLOW") or 1, "", origin, true)
        ParticleManager:SetParticleControl(particle, 10, Vector(1, 1, 0))
        ParticleManager:SetParticleControl(particle, 11, Vector(1, 0, 0))
        ParticleManager:SetParticleControl(particle, 13, Vector(0, 1, 1))
    end
end

local function same_particles(state, unit, asset_id, desired)
    if not state or state.owner ~= unit or state.asset_id ~= asset_id
        or #state.effects ~= #desired then return false end
    for index, effect in ipairs(desired) do
        local previous = state.effects[index]
        if previous.path ~= effect.path or previous.owner ~= effect.owner
            or previous.attach_type ~= effect.attach_type
            or previous.attachment_point ~= effect.attachment_point
            or previous.control_profile ~= effect.control_profile then
            return false
        end
    end
    return true
end

local function apply_particles(unit, asset, components)
    local desired = {}
    for index, entry in ipairs(asset and asset.environment_particles or {}) do
        local descriptor = normalize_particle(asset, entry, index)
        if descriptor and descriptor.path and descriptor.path ~= "" then
            desired[#desired + 1] = {
                path = descriptor.path,
                owner = components and components[descriptor.owner] or unit,
                attach_type = rawget(_G, descriptor.attach_type
                    or "PATTACH_ABSORIGIN_FOLLOW")
                    or rawget(_G, "PATTACH_ABSORIGIN_FOLLOW") or 1,
                attachment_point = descriptor.attachment_point or "",
                control_profile = descriptor.control_profile or "",
            }
        end
    end
    local asset_id = asset and asset.asset_id or "legacy_path"
    if same_particles(particles_by_unit[unit:entindex()], unit, asset_id, desired) then
        return
    end
    clear_particles(unit, true)
    local state = { owner = unit, asset_id = asset_id, effects = {}, particles = {} }
    for _, descriptor in ipairs(desired) do
        local ok, particle = pcall(
            ParticleManager.CreateParticle,
            ParticleManager,
            descriptor.path,
            descriptor.attach_type,
            descriptor.owner
        )
        if ok and particle then
            local configured = pcall(configure_particle,
                particle, descriptor.owner, descriptor)
            if configured then
                table.insert(state.particles, particle)
                table.insert(state.effects, descriptor)
            else
                pcall(ParticleManager.DestroyParticle, ParticleManager, particle, false)
                pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, particle)
                ok = false
            end
        end
        if not ok or not particle then
            logger.warn("BuildingVisual", "particle failed: "
                .. tostring(descriptor.path))
        end
    end
    -- Cache only successfully configured descriptors so failed effects are
    -- retried on the next apply. Attribute-only refreshes retain healthy loops.
    particles_by_unit[unit:entindex()] = state
end

function M.resolve(data)
    data = data or {}
    local requested_asset_id = data.model_asset_id
    if (not requested_asset_id or requested_asset_id == "")
        and type(data.model_name) == "string" and data.model_name ~= ""
        and type(catalog.for_model) == "function" then
        local path_asset = catalog.for_model(data.model_name)
        requested_asset_id = path_asset and path_asset.asset_id or nil
    end
    local model_path, asset = catalog.model(
        requested_asset_id,
        data.model_name
    )
    return model_path, asset, requested_asset_id
end

function M.matches(unit, data)
    if not valid_entity(unit) then return false end
    local model_path, asset, requested_asset_id = M.resolve(data)
    return model_path ~= nil and model_path ~= ""
        and unit.survival_applied_model_path == model_path
        and unit.survival_model_asset_id == requested_asset_id
        and unit.survival_pending_model_asset_id == nil
        and appearance.Matches(unit, asset)
        and unit.survival_native_wearable_hide_mode == nil
end

function M.apply(unit, data)
    if not valid_entity(unit) then return false, "invalid_entity" end
    local model_path, asset, requested_asset_id = M.resolve(data)
    if not model_path or model_path == "" then return false, "model_missing" end
    if unit.survival_upgrade_skip_model_path == model_path then
        unit.survival_upgrade_skip_model_path = nil
        return false, "upgrade_preload_failed"
    end
    local same_model = M.matches(unit, data)
    local previous_asset_id = unit.survival_model_asset_id
    local previous_model_path = unit.survival_applied_model_path

    if requested_asset_id and asset and asset.asset_id == requested_asset_id
        and not preload.is_ready(requested_asset_id) then
        if unit.survival_pending_model_asset_id == requested_asset_id then
            local status = preload.status(requested_asset_id).status
            return status ~= preload.STATE.FAILED
                and status ~= preload.STATE.RETIRED, status
        end
        unit.survival_model_asset_id = requested_asset_id
        unit.survival_pending_model_asset_id = requested_asset_id
        unit.survival_pending_previous_model_asset_id = previous_asset_id
        local queued, status = preload.queue(requested_asset_id, {
            urgent = true,
            on_ready = function()
                if valid_entity(unit)
                    and unit.survival_model_asset_id == requested_asset_id then
                    unit.survival_pending_model_asset_id = nil
                    unit.survival_pending_previous_model_asset_id = nil
                    M.apply(unit, data)
                end
            end,
            on_failed = function()
                if valid_entity(unit)
                    and unit.survival_pending_model_asset_id == requested_asset_id then
                    unit.survival_model_asset_id =
                        unit.survival_pending_previous_model_asset_id
                    unit.survival_pending_model_asset_id = nil
                    unit.survival_pending_previous_model_asset_id = nil
                end
            end,
        })
        if not queued then
            unit.survival_model_asset_id = previous_asset_id
            unit.survival_pending_model_asset_id = nil
            unit.survival_pending_previous_model_asset_id = nil
            return false, status
        end
        return true, status
    end

    if not same_model then
        native_carrier.Clear(unit)
        unit:SetModel(model_path)
        unit:SetOriginalModel(model_path)
    end
    -- Carrier-based visuals used to hide this entity. The Building is now the
    -- body and must remain the visible, selectable combat entity.
    if unit.survival_native_wearable_hide_mode == "render_alpha" then
        safe_call(unit, "SetRenderAlpha",
            tonumber(unit.survival_native_wearable_original_alpha) or 255)
    elseif unit.survival_native_wearable_hide_mode == "no_draw" then
        safe_call(unit, "RemoveNoDraw")
    end
    unit.survival_native_wearable_hide_mode = nil
    unit.survival_native_wearable_original_alpha = nil
    apply_activity_modifiers(unit, asset)
    if not same_model then
        reset_main_animation(unit, asset)
    end
    apply_bodygroups(unit, asset)
    local model_scale = tonumber(data and data.model_scale)
        or (asset and tonumber(asset.model_scale))
    if model_scale then
        unit:SetModelScale(model_scale)
    end
    local model_yaw = tonumber(data and data.model_yaw)
        or (asset and tonumber(asset.model_yaw))
    if model_yaw then
        -- Set an absolute yaw so upgrades and async visual refreshes are
        -- idempotent instead of adding another 180 degrees on every apply.
        safe_call(unit, "SetAngles", 0, model_yaw, 0)
    end
    if asset and tonumber(asset.model_skin) then
        safe_call(unit, "SetSkin", tonumber(asset.model_skin))
    else
        safe_call(unit, "SetSkin", 0)
    end
    local appearance_ok, appearance_status, components = appearance.Refresh(unit, asset)
    if not appearance_ok then
        if previous_model_path and previous_model_path ~= model_path then
            safe_call(unit, "SetModel", previous_model_path)
            safe_call(unit, "SetOriginalModel", previous_model_path)
            local previous_asset = catalog.resolve(previous_asset_id)
            apply_activity_modifiers(unit, previous_asset)
            reset_main_animation(unit, previous_asset)
            apply_bodygroups(unit, previous_asset)
            if previous_asset and tonumber(previous_asset.model_scale) then
                safe_call(unit, "SetModelScale", tonumber(previous_asset.model_scale))
            end
            safe_call(unit, "SetSkin",
                previous_asset and tonumber(previous_asset.model_skin) or 0)
        end
        unit.survival_model_asset_id = previous_asset_id
        unit.survival_applied_model_path = previous_model_path
        unit.survival_pending_model_asset_id = nil
        unit.survival_pending_previous_model_asset_id = nil
        return false, appearance_status
    end
    apply_particles(unit, asset, components)
    unit.survival_model_asset_id = requested_asset_id
    unit.survival_applied_model_path = model_path
    unit.survival_pending_model_asset_id = nil
    unit.survival_pending_previous_model_asset_id = nil

    return true, asset and asset.asset_id or "legacy_path"
end

function M.clear(unit)
    if valid_entity(unit) then
        clear_activity_modifiers(unit)
        appearance.Clear(unit)
        native_carrier.Clear(unit)
        clear_particles(unit)
        clear_bodygroups(unit)
    end
end

function M.precache_asset(asset_id, context)
    local row = catalog.resolve(asset_id)
    if not row then
        logger.warn("BuildingVisual", "asset missing: " .. tostring(asset_id))
        return false
    end
    local ok = pcall(PrecacheResource, "model", row.primary_model, context)
    return ok
end

return M
