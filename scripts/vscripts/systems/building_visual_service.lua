local catalog = require("config/asset_catalog")
local preload = require("systems/asset_preload_service")
local logger = require("core/logger")

local M = {}
local attachments_by_unit = {}
local particles_by_unit = {}
local bodygroups_by_unit = {}

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

local function spawn_attachment(asset, model_path)
    local entity_class = tostring(
        asset and asset.attachment_entity_class or "prop_dynamic"
    )
    local data = {
        model = model_path,
        DefaultAnim = asset and asset.default_sequence or "idle",
        -- Cosmetic props must never intercept world selection or contribute
        -- bone-follower collision. The owning tower remains the selectable,
        -- authoritative entity.
        solid = "0",
        -- Source 2 prop_dynamic spawnflag 256 is "Start with collision
        -- disabled". Keep it in addition to solid=0 and the runtime
        -- SetSolid(SOLID_NONE) call because model initialization can otherwise
        -- briefly restore collision after bone merge.
        spawnflags = "256",
        DisableBoneFollowers = "1",
    }
    local ok, attachment = pcall(
        SpawnEntityFromTableSynchronous, entity_class, data
    )
    if (not ok or not valid_entity(attachment))
        and entity_class ~= "prop_dynamic" then
        logger.warn("BuildingVisual", "attachment class failed; fallback="
            .. entity_class .. " model=" .. tostring(model_path))
        ok, attachment = pcall(
            SpawnEntityFromTableSynchronous, "prop_dynamic", data
        )
    end
    return ok, attachment
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
    -- bundle's default sequence so hero models resume their idle animation.
    safe_call(unit, "ResetSequenceInfo")
    local sequence = tostring(asset and asset.default_sequence or "idle")
    if sequence ~= "" then safe_call(unit, "ResetSequence", sequence) end
    safe_call(unit, "SetPlaybackRate", 1)
end

local function normalize_attachment(asset, entry, index)
    if type(entry) == "string" then
        local component_id = asset and asset.attachment_ids
            and asset.attachment_ids[index]
        return component_id or "attachment_" .. tostring(index), entry
    end
    if type(entry) == "table" then
        return entry.id or "attachment_" .. tostring(index), entry.model
    end
    return "attachment_" .. tostring(index), nil
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

local function apply_attachments(unit, asset)
    clear_attachments(unit)
    local spawned = {}
    local components = {}
    for index, entry in ipairs(asset and asset.attachment_models or {}) do
        local component_id, model_path = normalize_attachment(asset, entry, index)
        local ok, attachment = spawn_attachment(asset, model_path)
        if ok and valid_entity(attachment) then
            safe_call(attachment, "SetModel", model_path)
            safe_call(attachment, "SetOriginalModel", model_path)
            safe_call(attachment, "SetOwner", unit)
            safe_call(attachment, "FollowEntity", unit, true)
            safe_call(
                attachment,
                "SetSolid",
                rawget(_G, "SOLID_NONE") or 0
            )
            if tonumber(asset.model_skin) then
                safe_call(attachment, "SetSkin", tonumber(asset.model_skin))
            end
            table.insert(spawned, attachment)
            components[component_id] = attachment
        else
            logger.warn("BuildingVisual", "attachment failed: "
                .. tostring(model_path))
        end
    end
    if #spawned > 0 then attachments_by_unit[unit:entindex()] = spawned end
    return components
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
    local model_path = M.resolve(data)
    return model_path ~= nil and model_path ~= ""
        and unit.survival_applied_model_path == model_path
        and unit.survival_pending_model_asset_id == nil
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

    if not same_model then
        unit:SetModel(model_path)
        unit:SetOriginalModel(model_path)
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
    local components = apply_attachments(unit, asset)
    apply_particles(unit, asset, components)
    unit.survival_model_asset_id = requested_asset_id
    unit.survival_applied_model_path = model_path
    unit.survival_pending_model_asset_id = nil
    unit.survival_pending_previous_model_asset_id = nil

    return true, asset and asset.asset_id or "legacy_path"
end

function M.clear(unit)
    if valid_entity(unit) then
        clear_attachments(unit)
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