local catalog = require("config/asset_catalog")
local preload = require("systems/asset_preload_service")
local logger = require("core/logger")
local appearance = require("visual/model_appearance_service")
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

local function clear_particles(unit)
    for _, particle in ipairs(particles_by_unit[unit:entindex()] or {}) do
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
    -- bundle's configured default sequence.
    -- bundle's configured default sequence. Most assets still fall back to
    -- idle when they do not specify one; native tower models explicitly skip
    -- that fallback so the engine can select their own activity graph.
    safe_call(unit, "ResetSequenceInfo")
    local sequence = "idle"
    if asset and asset.default_sequence ~= nil then
        sequence = tostring(asset.default_sequence or "")
    end
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
        return entry, owner_id
    end
    if type(entry) == "table" then
        return entry.path, entry.owner
    end
    return nil, nil
end

local function apply_particles(unit, asset, components)
    clear_particles(unit)
    local spawned = {}
    local attach_type = rawget(_G, "PATTACH_ABSORIGIN_FOLLOW") or 1
    for index, entry in ipairs(asset and asset.environment_particles or {}) do
        local particle_path, owner_id = normalize_particle(asset, entry, index)
        local owner = components and components[owner_id] or unit
        local ok, particle = pcall(
            ParticleManager.CreateParticle,
            ParticleManager,
            particle_path,
            attach_type,
            owner
        )
        if ok and particle then
            table.insert(spawned, particle)
        else
            logger.warn("BuildingVisual", "particle failed: "
                .. tostring(particle_path))
        end
    end
    if #spawned > 0 then particles_by_unit[unit:entindex()] = spawned end
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
    local model_path, asset, requested_asset_id = M.resolve(data)
    local appearance_matches
    if native_carrier.IsNativeWearableAsset(asset) then
        appearance_matches = native_carrier.Matches(unit, asset)
    else
        appearance_matches = not native_carrier.Has(unit)
    end
    return model_path ~= nil and model_path ~= ""
        and unit.survival_applied_model_path == model_path
        and unit.survival_model_asset_id == requested_asset_id
        and unit.survival_pending_model_asset_id == nil
        and appearance.Matches(unit, asset)
        and appearance_matches
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
    local use_native_carrier = native_carrier.IsNativeWearableAsset(asset)
    local appearance_ok, appearance_status, components
    if use_native_carrier then
        appearance_ok, appearance_status = native_carrier.Refresh(unit, asset)
        if appearance_ok then appearance.Clear(unit) end
    else
        appearance_ok, appearance_status, components =
            appearance.Refresh(unit, asset)
        if appearance_ok then native_carrier.Clear(unit) end
    end
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