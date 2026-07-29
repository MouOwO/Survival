local catalog = require("config/asset_catalog")
local preload = require("systems/asset_preload_service")
local logger = require("core/logger")

local M = {}
local attachments_by_unit = {}
local particles_by_unit = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function safe_call(target, method_name, ...)
    local method = target and target[method_name]
    if type(method) ~= "function" then return false, nil end
    return pcall(method, target, ...)
end

local function clear_attachments(unit)
    local entindex = unit:entindex()
    for _, attachment in ipairs(attachments_by_unit[entindex] or {}) do
        if valid_entity(attachment) then
            if type(UTIL_Remove) == "function" then
                pcall(UTIL_Remove, attachment)
            else
                safe_call(attachment, "RemoveSelf")
            end
        end
    end
    attachments_by_unit[entindex] = nil
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

local function apply_attachments(unit, asset)
    clear_attachments(unit)
    local spawned = {}
    for _, model_path in ipairs(asset and asset.attachment_models or {}) do
        local ok, attachment = pcall(
            SpawnEntityFromTableSynchronous,
            "prop_dynamic",
            { model = model_path, DefaultAnim = asset.default_sequence or "idle" }
        )
        if ok and valid_entity(attachment) then
            safe_call(attachment, "SetOwner", unit)
            safe_call(attachment, "FollowEntity", unit, true)
            table.insert(spawned, attachment)
        else
            logger.warn("BuildingVisual", "attachment failed: "
                .. tostring(model_path))
        end
    end
    if #spawned > 0 then attachments_by_unit[unit:entindex()] = spawned end
end

local function apply_particles(unit, asset)
    clear_particles(unit)
    local spawned = {}
    local attach_type = rawget(_G, "PATTACH_ABSORIGIN_FOLLOW") or 1
    for _, particle_path in ipairs(asset and asset.particle_resources or {}) do
        local ok, particle = pcall(
            ParticleManager.CreateParticle,
            ParticleManager,
            particle_path,
            attach_type,
            unit
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
    local model_path, asset = catalog.model(
        data.model_asset_id,
        data.model_name
    )
    return model_path, asset
end

function M.apply(unit, data)
    if not valid_entity(unit) then return false, "invalid_entity" end
    local model_path, asset = M.resolve(data)
    if not model_path or model_path == "" then return false, "model_missing" end

    local requested_asset_id = data and data.model_asset_id or nil
    if requested_asset_id and asset and asset.asset_id == requested_asset_id
        and not preload.is_ready(requested_asset_id) then
        if unit.survival_pending_model_asset_id == requested_asset_id then
            local status = preload.status(requested_asset_id).status
            return status ~= preload.STATE.FAILED
                and status ~= preload.STATE.RETIRED, status
        end
        local previous_asset_id = unit.survival_model_asset_id
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

    unit:SetModel(model_path)
    unit:SetOriginalModel(model_path)
    if asset and tonumber(asset.model_scale) then
        unit:SetModelScale(tonumber(asset.model_scale))
    end
    apply_attachments(unit, asset)
    apply_particles(unit, asset)
    unit.survival_model_asset_id = data and data.model_asset_id or nil
    unit.survival_pending_model_asset_id = nil
    unit.survival_pending_previous_model_asset_id = nil

    return true, asset and asset.asset_id or "legacy_path"
end

function M.clear(unit)
    if valid_entity(unit) then
        clear_attachments(unit)
        clear_particles(unit)
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