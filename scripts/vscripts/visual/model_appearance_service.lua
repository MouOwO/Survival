local logger = require("core/logger")

local M = {}
local wearables_by_unit = {}

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
        return component_id or "wearable_" .. tostring(index), entry
    end
    if type(entry) == "table" then
        return entry.id or "wearable_" .. tostring(index), entry.model
    end
    return "wearable_" .. tostring(index), nil
end

local function spawn(appearance, model_path)
    local entity_class = tostring(
        appearance and appearance.attachment_entity_class or "prop_dynamic"
    )
    local data = {
        model = model_path,
        DefaultAnim = appearance and appearance.default_sequence or "idle",
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

function M.Clear(unit)
    if not valid(unit) or type(unit.entindex) ~= "function" then return false end
    local entindex = unit:entindex()
    remove_all(wearables_by_unit[entindex])
    wearables_by_unit[entindex] = nil
    return true
end

function M.Apply(unit, appearance)
    if not valid(unit) or type(unit.entindex) ~= "function" then
        return false, "invalid_entity", nil
    end
    M.Clear(unit)
    local spawned = {}
    local components = {}
    local entries = appearance and appearance.attachment_models or {}
    for index, entry in ipairs(entries) do
        local component_id, model_path = normalize(appearance, entry, index)
        local ok, wearable = spawn(appearance, model_path)
        if ok and valid(wearable) then
            safe_call(wearable, "SetModel", model_path)
            safe_call(wearable, "SetOriginalModel", model_path)
            local owner_ok = safe_call(wearable, "SetOwner", unit)
            local follow_ok = safe_call(wearable, "FollowEntity", unit, true)
            if owner_ok and follow_ok then
                safe_call(wearable, "SetSolid", rawget(_G, "SOLID_NONE") or 0)
                if appearance and tonumber(appearance.model_skin) then
                    safe_call(wearable, "SetSkin", tonumber(appearance.model_skin))
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
    if #spawned > 0 then wearables_by_unit[unit:entindex()] = spawned end
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