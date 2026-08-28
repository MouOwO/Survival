local logger = require("core/logger")
local scheduler = require("core/scheduler")

local M = {}
local wearables_by_unit = {}
local generation_by_unit = {}
local verification_retries_by_unit = {}
local VERIFY_DELAY_SECONDS = 0.05
local MAX_VERIFICATION_RETRIES = 1

local function valid(entity)
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

local function remove_all(wearables)
    for _, wearable in ipairs(wearables or {}) do
        if valid(wearable) then
            if type(UTIL_Remove) == "function" then
                pcall(UTIL_Remove, wearable)
            else
                safe_call(wearable, "RemoveSelf")
            end
        end
    end
end

local function debug_enabled()
    if not Convars or type(Convars.GetBool) ~= "function" then return false end
    local ok, enabled = pcall(
        Convars.GetBool,
        Convars,
        "survival_model_appearance_debug"
    )
    return ok and enabled == true
end

local function log_apply(unit, appearance, wearable_count, status)
    if not debug_enabled() then return end
    local unit_name = "unknown"
    local ok, value = safe_call(unit, "GetUnitName")
    if ok and value then unit_name = value end
    logger.info("Appearance", string.format(
        "unit=%s appearance=%s base=%s wearables=%d status=%s",
        tostring(unit_name),
        tostring(appearance and appearance.asset_id or "legacy_path"),
        tostring(appearance and appearance.primary_model or ""),
        tonumber(wearable_count) or 0,
        tostring(status)
    ))
end

local function normalize(appearance, entry, index)
    if type(entry) == "string" then
        local component_id = appearance and appearance.attachment_ids
            and appearance.attachment_ids[index]
        return component_id or "wearable_" .. tostring(index), entry, {}
    end
    if type(entry) == "table" then
        return entry.component_id or entry.id or "wearable_" .. tostring(index),
            entry.model_path or entry.model,
            entry
    end
    return "wearable_" .. tostring(index), nil, {}
end

local function spawn(appearance, component, model_path)
    local entity_class = tostring(
        component and component.entity_class
            or appearance and appearance.attachment_entity_class
            or "prop_dynamic"
    )
    local data = {
        model = model_path,
        DefaultAnim = component and component.default_sequence
            or appearance and appearance.default_sequence or "idle",
        solid = "0",
        spawnflags = "256",
        DisableBoneFollowers = "1",
    }
    local ok, wearable = pcall(
        SpawnEntityFromTableSynchronous,
        entity_class,
        data
    )
    if (not ok or not valid(wearable)) and entity_class ~= "prop_dynamic" then
        logger.warn("AppearanceWarning", "reason=entity_class_fallback class="
            .. entity_class .. " model=" .. tostring(model_path))
        ok, wearable = pcall(
            SpawnEntityFromTableSynchronous,
            "prop_dynamic",
            data
        )
    end
    return ok, wearable
end

local function schedule_verification(unit, appearance, generation)
    local entindex = unit:entindex()
    local ok = pcall(scheduler.after, VERIFY_DELAY_SECONDS, function()
        if generation_by_unit[entindex] ~= generation or not valid(unit) then return end
        local invalid_component = false
        for _, wearable in ipairs(wearables_by_unit[entindex] or {}) do
            if not valid(wearable) then
                invalid_component = true
                break
            end
        end
        if not invalid_component then
            verification_retries_by_unit[entindex] = 0
            return
        end
        local retries = tonumber(verification_retries_by_unit[entindex]) or 0
        logger.warn("AppearanceWarning", "unit=" .. tostring(entindex)
            .. " appearance=" .. tostring(appearance and appearance.asset_id)
            .. " generation=" .. tostring(generation)
            .. " reason=post_commit_component_invalid retry=" .. tostring(retries))
        if retries >= MAX_VERIFICATION_RETRIES then
            remove_all(wearables_by_unit[entindex])
            wearables_by_unit[entindex] = nil
            verification_retries_by_unit[entindex] = nil
            logger.warn("AppearanceWarning", "unit=" .. tostring(entindex)
                .. " appearance=" .. tostring(appearance and appearance.asset_id)
                .. " generation=" .. tostring(generation)
                .. " reason=post_commit_rollback")
            return
        end
        verification_retries_by_unit[entindex] = retries + 1
        M.Refresh(unit, appearance)
    end, "appearance_verify_" .. tostring(entindex))
    return ok
end

function M.Clear(unit)
    if not valid(unit) or type(unit.entindex) ~= "function" then return false end
    local entindex = unit:entindex()
    remove_all(wearables_by_unit[entindex])
    wearables_by_unit[entindex] = nil
    generation_by_unit[entindex] = (generation_by_unit[entindex] or 0) + 1
    verification_retries_by_unit[entindex] = nil
    return true
end

function M.Apply(unit, appearance)
    if not valid(unit) or type(unit.entindex) ~= "function" then
        return false, "invalid_entity", nil
    end
    local entindex = unit:entindex()
    local generation = (generation_by_unit[entindex] or 0) + 1
    generation_by_unit[entindex] = generation
    local previous = wearables_by_unit[entindex]
    local spawned = {}
    local components = {}
    local entries = appearance and appearance.components
    if not entries or #entries == 0 then
        entries = appearance and appearance.attachment_models or {}
    end
    for index, entry in ipairs(entries) do
        local component_id, model_path, component = normalize(appearance, entry, index)
        local ok, wearable = spawn(appearance, component, model_path)
        if ok and valid(wearable) then
            safe_call(wearable, "SetModel", model_path)
            safe_call(wearable, "SetOriginalModel", model_path)
            local owner_ok = safe_call(wearable, "SetOwner", unit)
            local follow_ok = safe_call(wearable, "FollowEntity", unit, true)
            if owner_ok and follow_ok then
                safe_call(wearable, "SetSolid", rawget(_G, "SOLID_NONE") or 0)
                local skin = component and component.model_skin
                    or appearance and appearance.model_skin
                if tonumber(skin) then
                    safe_call(wearable, "SetSkin", tonumber(skin))
                end
                local material_group = component and component.material_group
                    or appearance and appearance.material_group
                if material_group then
                    safe_call(wearable, "SetMaterialGroup", material_group)
                end
                local scale = component and tonumber(component.model_scale)
                if scale then
                    safe_call(wearable, "SetModelScale", scale)
                end
                spawned[#spawned + 1] = wearable
                components[component_id] = wearable
            else
                remove_all({ wearable })
                remove_all(spawned)
                logger.warn("AppearanceWarning", "unit="
                    .. tostring(unit:entindex()) .. " appearance="
                    .. tostring(appearance and appearance.asset_id) .. " slot="
                    .. tostring(component_id) .. " reason=attach_failure")
                log_apply(unit, appearance, #spawned, "attachment_failed")
                return false, "attachment_failed:" .. component_id, nil
            end
        else
            remove_all(spawned)
            logger.warn("AppearanceWarning", "unit="
                .. tostring(unit:entindex()) .. " appearance="
                .. tostring(appearance and appearance.asset_id) .. " slot="
                .. tostring(component_id) .. " reason=entity_create_failed model="
                .. tostring(model_path))
            log_apply(unit, appearance, #spawned, "attachment_failed")
            return false, "attachment_failed:" .. component_id, nil
        end
    end
    if generation_by_unit[entindex] ~= generation then
        remove_all(spawned)
        return false, "superseded", nil
    end
    wearables_by_unit[entindex] = #spawned > 0 and spawned or nil
    remove_all(previous)
    schedule_verification(unit, appearance, generation)
    log_apply(unit, appearance, #spawned, "ok")
    return true, appearance and appearance.asset_id or "legacy_path", components
end

function M.Refresh(unit, appearance)
    return M.Apply(unit, appearance)
end

function M._count_for_test(unit)
    if not valid(unit) or type(unit.entindex) ~= "function" then return 0 end
    return #(wearables_by_unit[unit:entindex()] or {})
end

return M