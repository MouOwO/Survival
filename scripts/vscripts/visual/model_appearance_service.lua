local logger = require("core/logger")
local scheduler = require("core/scheduler")

local M = {}
local states_by_unit = {}
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

local function entity_owner(entity)
    for _, method_name in ipairs({ "GetOwner", "GetOwnerEntity" }) do
        local ok, owner = safe_call(entity, method_name)
        if ok and owner ~= nil then return owner end
    end
    return entity and entity.owner or nil
end

local function each_live_entity(class_name, callback)
    if not Entities then return end
    local seen = {}
    local function visit(entity)
        if not valid(entity) then return end
        local index_ok, index = safe_call(entity, "entindex")
        if not index_ok then index = nil end
        if index and seen[index] then return end
        if index then seen[index] = true end
        callback(entity)
    end
    if type(Entities.FindAllByClassname) == "function" then
        local ok, entities = pcall(
            Entities.FindAllByClassname,
            Entities,
            class_name
        )
        if ok then
            for _, entity in ipairs(entities or {}) do visit(entity) end
        end
    end
    if type(Entities.FindByClassname) == "function" then
        local previous = nil
        for _ = 1, 4096 do
            local ok, entity = pcall(
                Entities.FindByClassname,
                Entities,
                previous,
                class_name
            )
            if not ok or not valid(entity) or entity == previous then break end
            visit(entity)
            previous = entity
        end
    end
end

local function remove_legacy_carriers(unit)
    each_live_entity("npc_dota_creature", function(carrier)
        if carrier.survival_is_native_wearable_visual == true
            and entity_owner(carrier) == unit then
            each_live_entity("dota_item_wearable", function(wearable)
                if entity_owner(wearable) == carrier
                    and (wearable.survival_is_native_wearable == true
                        or wearable.survival_native_wearable_key ~= nil) then
                    remove_all({ wearable })
                end
            end)
            remove_all({ carrier })
        end
    end)
end

local function component_owner_matches(unit, component)
    local owner_entindex = unit and type(unit.entindex) == "function"
        and unit:entindex() or nil
    if tonumber(component.survival_model_component_owner_entindex)
        ~= tonumber(owner_entindex) then
        return false
    end
    local owner = entity_owner(component)
    return owner == unit
end

local function component_model_path(component)
    local ok, model_path = safe_call(component, "GetModelName")
    if ok and type(model_path) == "string" and model_path ~= "" then
        return model_path
    end
    return component.survival_model_component_model_path
        or component.model
end

local normalize
local declarations
local component_signature

local function remove_owned_model_components(unit, keep)
    local keep_set = {}
    for _, component in ipairs(keep or {}) do keep_set[component] = true end
    for _, class_name in ipairs({ "prop_dynamic", "dota_item_wearable" }) do
        each_live_entity(class_name, function(component)
            if component.survival_is_model_component == true
                and component_owner_matches(unit, component)
                and not keep_set[component] then
                remove_all({ component })
            end
        end)
    end
end

local function recover_live_state(unit, appearance)
    if not valid(unit) or type(unit.entindex) ~= "function" then return nil end
    local expected = declarations(appearance)
    local owner_entindex = unit:entindex()
    local candidates = {}
    for _, class_name in ipairs({ "prop_dynamic", "dota_item_wearable" }) do
        each_live_entity(class_name, function(component)
            if component.survival_is_model_component == true
                and tonumber(component.survival_model_component_owner_entindex)
                    == tonumber(owner_entindex)
                and entity_owner(component) == unit
                and tostring(component.survival_model_component_asset_id or "")
                    == tostring(appearance and appearance.asset_id or "legacy_path") then
                local component_id = tostring(
                    component.survival_model_component_id or ""
                )
                candidates[component_id] = candidates[component_id] or {}
                candidates[component_id][#candidates[component_id] + 1] = component
            end
        end)
    end

    local recovered = {}
    local components = {}
    local used = {}
    for index, entry in ipairs(expected) do
        local component_id, model_path = normalize(appearance, entry, index)
        local selected = nil
        for _, candidate in ipairs(candidates[component_id] or {}) do
            if not used[candidate]
                and component_model_path(candidate) == model_path then
                selected = candidate
                break
            end
        end
        if not selected then return nil end
        used[selected] = true
        recovered[#recovered + 1] = selected
        components[component_id] = selected
    end

    for _, list in pairs(candidates) do
        for _, candidate in ipairs(list) do
            if not used[candidate] then remove_all({ candidate }) end
        end
    end
    local state = {
        owner = unit,
        signature = component_signature(appearance),
        generation = generation_by_unit[owner_entindex] or 0,
        wearables = recovered,
        components = components,
    }
    if #expected == 0 then
        if unit.survival_model_appearance_asset_id
            ~= (appearance and appearance.asset_id or "legacy_path")
            or unit.survival_model_appearance_signature
                ~= state.signature then
            return nil
        end
    end
    states_by_unit[owner_entindex] = state
    return state
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

normalize = function(appearance, entry, index)
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

declarations = function(appearance)
    local entries = appearance and appearance.components
    if not entries or #entries == 0 then
        entries = appearance and appearance.attachment_models or {}
    end
    return entries
end

component_signature = function(appearance)
    local parts = { tostring(appearance and appearance.asset_id or "legacy_path") }
    for index, entry in ipairs(declarations(appearance)) do
        local component_id, model_path, component = normalize(appearance, entry, index)
        parts[#parts + 1] = table.concat({
            tostring(component_id),
            tostring(model_path or ""),
            tostring(component.entity_class
                or appearance and appearance.attachment_entity_class
                or "prop_dynamic"),
            tostring(component.parent_component_id or ""),
            tostring(component.attach_mode or "bone_merge"),
            tostring(component.attachment_point or ""),
            tostring(component.default_sequence
                or appearance and appearance.default_sequence or "idle"),
            tostring(component.model_scale or ""),
            tostring(component.model_skin or appearance and appearance.model_skin or ""),
            tostring(component.material_group
                or appearance and appearance.material_group or ""),
        }, "\31")
    end
    return table.concat(parts, "\30")
end

local function state_matches(unit, appearance, state)
    if not state or state.owner ~= unit
        or state.signature ~= component_signature(appearance) then
        return false
    end
    for _, wearable in ipairs(state.wearables or {}) do
        if not valid(wearable) then return false end
    end
    return true
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
        local state = states_by_unit[entindex]
        if not state or state.owner ~= unit or state.generation ~= generation then return end
        local invalid_component = false
        for _, wearable in ipairs(state.wearables or {}) do
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
            remove_all(state.wearables)
            states_by_unit[entindex] = nil
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
    remove_legacy_carriers(unit)
    local entindex = unit:entindex()
    local state = states_by_unit[entindex]
    if state and state.owner ~= unit then return false end
    remove_all(state and state.wearables)
    states_by_unit[entindex] = nil
    unit.survival_model_appearance_asset_id = nil
    unit.survival_model_appearance_signature = nil
    generation_by_unit[entindex] = (generation_by_unit[entindex] or 0) + 1
    verification_retries_by_unit[entindex] = nil
    return true
end

function M.Matches(unit, appearance)
    if not valid(unit) or type(unit.entindex) ~= "function" then return false end
    local state = states_by_unit[unit:entindex()]
        or recover_live_state(unit, appearance)
    return state_matches(unit, appearance, state)
end

function M.Apply(unit, appearance)
    if not valid(unit) or type(unit.entindex) ~= "function" then
        return false, "invalid_entity", nil
    end
    remove_legacy_carriers(unit)
    local entindex = unit:entindex()
    local previous = states_by_unit[entindex]
        or recover_live_state(unit, appearance)
    if state_matches(unit, appearance, previous) then
        return true, appearance and appearance.asset_id or "legacy_path",
            previous.components
    end
    local generation = (generation_by_unit[entindex] or 0) + 1
    generation_by_unit[entindex] = generation
    local spawned = {}
    local components = {}
    for index, entry in ipairs(declarations(appearance)) do
        local component_id, model_path, component = normalize(appearance, entry, index)
        if type(model_path) ~= "string" or model_path == "" then
            remove_all(spawned)
            return false, "attachment_model_missing:" .. component_id, nil
        end
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
                wearable.survival_is_model_component = true
                wearable.survival_model_component_owner_entindex = entindex
                wearable.survival_model_component_asset_id =
                    appearance and appearance.asset_id or "legacy_path"
                wearable.survival_model_component_id = component_id
                wearable.survival_model_component_model_path = model_path
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
    states_by_unit[entindex] = {
        owner = unit,
        signature = component_signature(appearance),
        generation = generation,
        wearables = spawned,
        components = components,
    }
    remove_all(previous and previous.wearables)
    remove_owned_model_components(unit, spawned)
    unit.survival_model_appearance_asset_id = appearance and appearance.asset_id
        or "legacy_path"
    unit.survival_model_appearance_signature = component_signature(appearance)
    schedule_verification(unit, appearance, generation)
    log_apply(unit, appearance, #spawned, "ok")
    return true, appearance and appearance.asset_id or "legacy_path", components
end

function M.Refresh(unit, appearance)
    return M.Apply(unit, appearance)
end

function M._count_for_test(unit)
    if not valid(unit) or type(unit.entindex) ~= "function" then return 0 end
    local state = states_by_unit[unit:entindex()]
    if not state or state.owner ~= unit then return 0 end
    return #(state.wearables or {})
end

return M